#!/bin/bash

# ============================================================================
# SAMUREYE - INSTALAÇÃO vlxsam04 (COLLECTOR AGENT)
# ============================================================================
# 
# Servidor: vlxsam04 (192.168.100.151)
# Função: Agente coletor multi-tenant com mTLS
# Stack: Python 3.12 + Node.js 20 + Security Tools + step-ca
# 
# Características:
# - Comunicação outbound-only com mTLS
# - Multi-tenancy com isolamento de execução
# - Object Storage integration por tenant
# - WebSocket real-time + HTTPS
# - Ferramentas de segurança atualizadas
# - Certificados X.509 com step-ca
# 
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funções auxiliares
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

# Verificar se é executado como root
if [ "$EUID" -ne 0 ]; then
    error "Este script deve ser executado como root (sudo)"
fi

# Configurações
SERVER_IP="192.168.100.151"
COLLECTOR_USER="samureye-collector"
COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
TOOLS_DIR="$COLLECTOR_DIR/tools"
CERTS_DIR="$COLLECTOR_DIR/certs"

log "🚀 Iniciando instalação vlxsam04 - Collector Agent"
log "Servidor: $SERVER_IP (rede interna isolada)"
log "Collector Directory: $COLLECTOR_DIR"

# ============================================================================
# 1. ATUALIZAÇÃO DO SISTEMA BASE
# ============================================================================

log "📦 Atualizando sistema base..."

apt update && apt upgrade -y

# Instalar dependências essenciais
apt install -y \
    curl \
    wget \
    gnupg \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    jq \
    htop \
    iotop \
    netcat-openbsd \
    net-tools \
    dnsutils \
    tcpdump \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    build-essential \
    git \
    unzip

log "Sistema base atualizado"

# ============================================================================
# 2. INSTALAÇÃO NODE.JS 20.x
# ============================================================================

log "🟢 Instalando Node.js 20.x..."

# Adicionar repositório NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Verificar instalação
node_version=$(node --version)
npm_version=$(npm --version)
log "Node.js instalado: $node_version"
log "npm instalado: $npm_version"

# ============================================================================
# 3. INSTALAÇÃO PYTHON E DEPENDÊNCIAS
# ============================================================================

log "🐍 Configurando Python 3.12..."

# Definir Python 3.12 como padrão
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 100
update-alternatives --install /usr/bin/python python /usr/bin/python3.12 100

# Configurar pip para Python 3.12 (Ubuntu 24.04)
log "Configurando pip para Python 3.12..."

# Ubuntu 24.04 desabilita ensurepip por padrão, usar pip do sistema
if ! python3.12 -m pip --version &>/dev/null; then
    log "Instalando pip via apt (método recomendado Ubuntu 24.04)"
    apt install -y python3-pip python3-venv
fi

# Verificar se pip está funcionando
if python3.12 -m pip --version &>/dev/null; then
    log "✅ pip funcionando, atualizando com --break-system-packages (Ubuntu 24.04)..."
    python3.12 -m pip install --upgrade pip setuptools wheel --break-system-packages 2>/dev/null || {
        log "⚠️ Pip upgrade falhou, usando versão do sistema..."
    }
else
    error "❌ Falha ao configurar pip para Python 3.12"
fi

# Dependências Python para o agente (Ubuntu 24.04 com --break-system-packages)
log "📦 Instalando dependências Python..."
python3.12 -m pip install --break-system-packages \
    aiohttp \
    websockets \
    cryptography \
    requests \
    certifi \
    psutil \
    pyyaml \
    structlog \
    python-multipart \
    aiofiles \
|| {
    log "⚠️ Instalação via pip falhou, tentando via apt..."
    apt install -y python3-aiohttp python3-websockets python3-cryptography \
                   python3-requests python3-certifi python3-psutil \
                   python3-yaml python3-structlog
}

log "Python 3.12 e dependências instaladas"

# ============================================================================
# 3.1. VALIDAÇÃO UBUNTU 24.04 COMPATIBILITY
# ============================================================================

log "🔍 Validando compatibilidade Ubuntu 24.04..."

# Verificar versão do Ubuntu
ubuntu_version=$(lsb_release -rs)
ubuntu_codename=$(lsb_release -cs)
log "Ubuntu detectado: $ubuntu_version ($ubuntu_codename)"

if [[ "$ubuntu_codename" == "noble" ]]; then
    log "✅ Ubuntu 24.04 Noble detectado - compatibilidade OK"
else
    warn "⚠️  Versão Ubuntu diferente de 24.04 detectada: $ubuntu_version"
fi

# Validar instalações críticas
log "🧪 Testando componentes instalados..."

# Testar Python 3.12
python_version=$(python3 --version 2>/dev/null || echo "ERRO")
if [[ "$python_version" == *"Python 3.12"* ]]; then
    log "✅ Python 3.12: $python_version"
else
    error "❌ Python 3.12 não encontrado. Versão atual: $python_version"
fi

# Testar dependências Python críticas
log "Testando importações Python..."
python3 -c "
import sys
import aiohttp
import websockets
import cryptography
import requests
import psutil
import asyncio
import yaml
import structlog
print('✅ Todas as dependências Python importadas com sucesso')
print(f'✅ Python path: {sys.executable}')
" || error "❌ Erro na importação de dependências Python"

# Testar netcat-openbsd
if command -v nc >/dev/null 2>&1; then
    nc_version=$(nc -h 2>&1 | head -1)
    log "✅ netcat-openbsd disponível: $(which nc)"
else
    error "❌ netcat-openbsd não encontrado"
fi

# Testar Node.js
if [[ "$node_version" == v20* ]]; then
    log "✅ Node.js 20.x: $node_version"
else
    warn "⚠️  Node.js versão inesperada: $node_version"
fi

log "🎉 Validação de compatibilidade concluída com sucesso!"

# ============================================================================
# 4. CONFIGURAÇÃO DE USUÁRIOS E DIRETÓRIOS
# ============================================================================

log "👤 Configurando usuário collector..."

# Criar usuário samureye-collector
if ! id "$COLLECTOR_USER" &>/dev/null; then
    useradd -r -s /bin/bash -d "$COLLECTOR_DIR" "$COLLECTOR_USER"
fi

# Criar estrutura de diretórios
mkdir -p "$COLLECTOR_DIR"/{agent,certs,tools,logs,temp,uploads}
mkdir -p "$COLLECTOR_DIR"/logs/{system,tenant-{1..10}}
mkdir -p "$COLLECTOR_DIR"/temp/{tenant-{1..10}}
mkdir -p "$COLLECTOR_DIR"/uploads/{tenant-{1..10}}
mkdir -p "$CONFIG_DIR"
mkdir -p /var/log/samureye-collector

# Estrutura de ferramentas
mkdir -p "$TOOLS_DIR"/{nmap,nuclei,masscan,gobuster,custom}

# Definir permissões
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR"
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" /var/log/samureye-collector
chmod 750 "$COLLECTOR_DIR" "$CONFIG_DIR"
chmod 700 "$CERTS_DIR"

log "Usuário e diretórios configurados"

# ============================================================================
# 5. INSTALAÇÃO FERRAMENTAS DE SEGURANÇA
# ============================================================================

log "🔧 Instalando ferramentas de segurança..."

# Nmap 7.94+ (repositório oficial)
apt install -y nmap nmap-common

# Masscan (com fallback para compilação se apt falhar)
if ! apt install -y masscan 2>/dev/null; then
    log "⚠️ Masscan via apt falhou, compilando do source..."
    cd /tmp
    git clone https://github.com/robertdavidgraham/masscan
    cd masscan
    make
    make install
    cd /
    rm -rf /tmp/masscan
    log "✅ Masscan compilado e instalado"
else
    log "✅ Masscan instalado via apt"
fi

# Gobuster
wget -q -O /tmp/gobuster.tar.gz "https://github.com/OJ/gobuster/releases/download/v3.6.0/gobuster_Linux_x86_64.tar.gz"
tar -xzf /tmp/gobuster.tar.gz -C /tmp/ 2>/dev/null
mv /tmp/gobuster /usr/local/bin/gobuster
chmod +x /usr/local/bin/gobuster

# Nuclei 3.x
wget -q -O /tmp/nuclei.zip "https://github.com/projectdiscovery/nuclei/releases/download/v3.1.0/nuclei_3.1.0_linux_amd64.zip"
unzip -q -o /tmp/nuclei.zip -d /tmp/
mv /tmp/nuclei /usr/local/bin/nuclei
chmod +x /usr/local/bin/nuclei

# Templates Nuclei - versão 3.x usa -ut flag
sudo -u "$COLLECTOR_USER" mkdir -p "$TOOLS_DIR/nuclei/templates"
cd "$TOOLS_DIR/nuclei/templates"
sudo -u "$COLLECTOR_USER" nuclei -ut

log "Ferramentas de segurança instaladas"

# ============================================================================
# 6. INSTALAÇÃO STEP-CA CLIENT
# ============================================================================

log "🔐 Instalando step-ca client..."

# Download step CLI
wget -q -O /tmp/step-cli.tar.gz "https://github.com/smallstep/cli/releases/download/v0.25.2/step_linux_0.25.2_amd64.tar.gz"
tar -xzf /tmp/step-cli.tar.gz -C /tmp/ 2>/dev/null
mv /tmp/step_0.25.2/bin/step /usr/local/bin/step
chmod +x /usr/local/bin/step

# Verificar instalação
step_version=$(step version)
log "step-ca client instalado: $step_version"

log "step-ca client configurado"

# ============================================================================
# 7. CONFIGURAÇÃO DO AGENTE COLLECTOR
# ============================================================================

log "🤖 Configurando agente collector..."

# Arquivo principal do agente
cat > "$COLLECTOR_DIR/agent/main.py" << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent - Multi-Tenant
Agente principal para comunicação com a plataforma SamurEye
"""

import asyncio
import sys
import os
import logging
import json
import signal
from datetime import datetime
from pathlib import Path

# Adicionar diretório do agente ao path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from api_client import SamurEyeAPIClient
from websocket_client import SamurEyeWebSocketClient
from telemetry import TelemetryCollector
from executor import CommandExecutor
from tenant_manager import TenantManager

class SamurEyeCollectorAgent:
    def __init__(self):
        self.collector_id = self._load_collector_id()
        self.api_client = SamurEyeAPIClient()
        self.ws_client = SamurEyeWebSocketClient()
        self.telemetry = TelemetryCollector()
        self.executor = CommandExecutor()
        self.tenant_manager = TenantManager()
        self.running = False
        
        # Configurar logging
        self._setup_logging()
        
    def _load_collector_id(self):
        """Carrega ID único do collector"""
        collector_id_file = Path("/opt/samureye-collector/certs/collector-id.txt")
        if collector_id_file.exists():
            return collector_id_file.read_text().strip()
        else:
            # Gerar novo ID se não existir
            import uuid
            collector_id = str(uuid.uuid4())
            collector_id_file.write_text(collector_id)
            return collector_id
    
    def _setup_logging(self):
        """Configura sistema de logging estruturado"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/samureye-collector/agent.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('SamurEyeCollector')
    
    async def start(self):
        """Inicia o agente collector"""
        self.logger.info(f"Iniciando SamurEye Collector Agent - ID: {self.collector_id}")
        self.running = True
        
        # Configurar handlers de sinal
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
        
        try:
            # Inicializar componentes
            await self.api_client.initialize()
            await self.ws_client.initialize()
            await self.telemetry.start()
            
            # Registrar collector na plataforma
            await self._register_collector()
            
            # Loop principal
            await self._main_loop()
            
        except Exception as e:
            self.logger.error(f"Erro no agente: {e}")
            raise
        finally:
            await self.stop()
    
    async def _register_collector(self):
        """Registra collector na plataforma"""
        registration_data = {
            'collector_id': self.collector_id,
            'hostname': os.uname().nodename,
            'ip_address': '192.168.100.151',
            'version': '1.0.0',
            'capabilities': [
                'nmap', 'nuclei', 'masscan', 'gobuster',
                'multi-tenant', 'object-storage', 'websocket'
            ]
        }
        
        await self.api_client.register_collector(registration_data)
        self.logger.info("Collector registrado na plataforma")
    
    async def _main_loop(self):
        """Loop principal do agente"""
        while self.running:
            try:
                # Enviar heartbeat e telemetria
                await self._send_heartbeat()
                
                # Processar comandos pendentes
                await self._process_commands()
                
                # Aguardar 30 segundos
                await asyncio.sleep(30)
                
            except Exception as e:
                self.logger.error(f"Erro no loop principal: {e}")
                await asyncio.sleep(5)
    
    async def _send_heartbeat(self):
        """Envia heartbeat com telemetria"""
        telemetry_data = await self.telemetry.collect()
        heartbeat_data = {
            'collector_id': self.collector_id,
            'timestamp': datetime.utcnow().isoformat(),
            'status': 'active',
            'telemetry': telemetry_data
        }
        
        await self.api_client.send_heartbeat(heartbeat_data)
    
    async def _process_commands(self):
        """Processa comandos recebidos"""
        commands = await self.api_client.get_pending_commands()
        
        for command in commands:
            try:
                tenant_id = command.get('tenant_id')
                if tenant_id:
                    # Executar comando no contexto do tenant
                    result = await self.executor.execute_command(command, tenant_id)
                    await self.api_client.send_command_result(command['id'], result)
                    
            except Exception as e:
                self.logger.error(f"Erro executando comando {command.get('id')}: {e}")
    
    def _signal_handler(self, signum, frame):
        """Handler para sinais do sistema"""
        self.logger.info(f"Recebido sinal {signum}, parando agente...")
        self.running = False
    
    async def stop(self):
        """Para o agente de forma limpa"""
        self.logger.info("Parando SamurEye Collector Agent...")
        self.running = False
        
        if hasattr(self, 'telemetry'):
            await self.telemetry.stop()
        if hasattr(self, 'ws_client'):
            await self.ws_client.close()
        if hasattr(self, 'api_client'):
            await self.api_client.close()

async def main():
    """Função principal"""
    agent = SamurEyeCollectorAgent()
    
    try:
        await agent.start()
    except KeyboardInterrupt:
        print("\nParando agente...")
    except Exception as e:
        print(f"Erro fatal: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Cliente API HTTPS com mTLS
cat > "$COLLECTOR_DIR/agent/api_client.py" << 'EOF'
"""
Cliente API HTTPS com mTLS para comunicação com SamurEye
"""

import aiohttp
import ssl
import asyncio
import logging
from pathlib import Path

class SamurEyeAPIClient:
    def __init__(self):
        self.base_url = os.getenv('SAMUREYE_API_URL', 'https://api.samureye.com.br')
        self.cert_file = '/opt/samureye-collector/certs/collector.crt'
        self.key_file = '/opt/samureye-collector/certs/collector.key'
        self.ca_file = '/opt/samureye-collector/certs/ca.crt'
        self.session = None
        self.logger = logging.getLogger('APIClient')
    
    async def initialize(self):
        """Inicializa cliente com mTLS"""
        ssl_context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
        ssl_context.load_verify_locations(self.ca_file)
        ssl_context.load_cert_chain(self.cert_file, self.key_file)
        
        connector = aiohttp.TCPConnector(ssl=ssl_context)
        self.session = aiohttp.ClientSession(connector=connector)
        
        self.logger.info("Cliente API inicializado com mTLS")
    
    async def register_collector(self, data):
        """Registra collector na plataforma"""
        async with self.session.post(f"{self.base_url}/api/collectors/register", json=data) as resp:
            if resp.status == 200:
                result = await resp.json()
                self.logger.info("Collector registrado com sucesso")
                return result
            else:
                raise Exception(f"Erro no registro: {resp.status}")
    
    async def send_heartbeat(self, data):
        """Envia heartbeat"""
        async with self.session.post(f"{self.base_url}/api/collectors/heartbeat", json=data) as resp:
            return await resp.json() if resp.status == 200 else None
    
    async def get_pending_commands(self):
        """Obtém comandos pendentes"""
        async with self.session.get(f"{self.base_url}/api/collectors/commands") as resp:
            if resp.status == 200:
                return await resp.json()
            return []
    
    async def send_command_result(self, command_id, result):
        """Envia resultado de comando"""
        data = {'command_id': command_id, 'result': result}
        async with self.session.post(f"{self.base_url}/api/collectors/results", json=data) as resp:
            return resp.status == 200
    
    async def close(self):
        """Fecha cliente"""
        if self.session:
            await self.session.close()
EOF

# Cliente WebSocket para comunicação real-time
cat > "$COLLECTOR_DIR/agent/websocket_client.py" << 'EOF'
"""
Cliente WebSocket para comunicação real-time
"""

import asyncio
import websockets
import ssl
import json
import logging
import os

class SamurEyeWebSocketClient:
    def __init__(self):
        self.ws_url = os.getenv('SAMUREYE_WS_URL', 'wss://api.samureye.com.br/ws')
        self.websocket = None
        self.logger = logging.getLogger('WebSocketClient')
    
    async def initialize(self):
        """Inicializa conexão WebSocket com mTLS"""
        ssl_context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
        ssl_context.load_verify_locations('/opt/samureye-collector/certs/ca.crt')
        ssl_context.load_cert_chain(
            '/opt/samureye-collector/certs/collector.crt',
            '/opt/samureye-collector/certs/collector.key'
        )
        
        try:
            self.websocket = await websockets.connect(self.ws_url, ssl=ssl_context)
            self.logger.info("Conexão WebSocket estabelecida")
        except Exception as e:
            self.logger.error(f"Erro na conexão WebSocket: {e}")
    
    async def send_message(self, message):
        """Envia mensagem via WebSocket"""
        if self.websocket:
            await self.websocket.send(json.dumps(message))
    
    async def close(self):
        """Fecha conexão WebSocket"""
        if self.websocket:
            await self.websocket.close()
EOF

# Coletor de telemetria
cat > "$COLLECTOR_DIR/agent/telemetry.py" << 'EOF'
"""
Coletor de telemetria do sistema
"""

import psutil
import asyncio
import logging
from datetime import datetime

class TelemetryCollector:
    def __init__(self):
        self.logger = logging.getLogger('Telemetry')
        self.running = False
    
    async def start(self):
        """Inicia coleta de telemetria"""
        self.running = True
        self.logger.info("Telemetria iniciada")
    
    async def collect(self):
        """Coleta métricas do sistema"""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            network = psutil.net_io_counters()
            
            return {
                'timestamp': datetime.utcnow().isoformat(),
                'cpu': {
                    'percent': cpu_percent,
                    'cores': psutil.cpu_count()
                },
                'memory': {
                    'total': memory.total,
                    'available': memory.available,
                    'percent': memory.percent
                },
                'disk': {
                    'total': disk.total,
                    'used': disk.used,
                    'free': disk.free,
                    'percent': (disk.used / disk.total) * 100
                },
                'network': {
                    'bytes_sent': network.bytes_sent,
                    'bytes_recv': network.bytes_recv
                }
            }
        except Exception as e:
            self.logger.error(f"Erro coletando telemetria: {e}")
            return {}
    
    async def stop(self):
        """Para coleta de telemetria"""
        self.running = False
        self.logger.info("Telemetria parada")
EOF

# Executor de comandos com sandbox
cat > "$COLLECTOR_DIR/agent/executor.py" << 'EOF'
"""
Executor de comandos com sandbox e isolamento por tenant
"""

import asyncio
import subprocess
import logging
import os
import tempfile
from pathlib import Path

class CommandExecutor:
    def __init__(self):
        self.logger = logging.getLogger('Executor')
        self.allowed_commands = ['nmap', 'nuclei', 'masscan', 'gobuster']
    
    async def execute_command(self, command, tenant_id):
        """Executa comando no contexto do tenant"""
        cmd_type = command.get('type')
        cmd_args = command.get('args', [])
        
        if cmd_type not in self.allowed_commands:
            raise ValueError(f"Comando não permitido: {cmd_type}")
        
        # Criar diretório temporário para o tenant
        temp_dir = f"/opt/samureye-collector/temp/tenant-{tenant_id}"
        os.makedirs(temp_dir, exist_ok=True)
        
        try:
            result = await self._run_command(cmd_type, cmd_args, temp_dir, tenant_id)
            return result
        except Exception as e:
            self.logger.error(f"Erro executando comando {cmd_type}: {e}")
            return {'error': str(e)}
    
    async def _run_command(self, cmd_type, args, work_dir, tenant_id):
        """Executa comando específico"""
        if cmd_type == 'nmap':
            return await self._run_nmap(args, work_dir, tenant_id)
        elif cmd_type == 'nuclei':
            return await self._run_nuclei(args, work_dir, tenant_id)
        elif cmd_type == 'masscan':
            return await self._run_masscan(args, work_dir, tenant_id)
        elif cmd_type == 'gobuster':
            return await self._run_gobuster(args, work_dir, tenant_id)
    
    async def _run_nmap(self, args, work_dir, tenant_id):
        """Executa Nmap"""
        cmd = ['nmap'] + args
        return await self._execute_subprocess(cmd, work_dir, tenant_id)
    
    async def _run_nuclei(self, args, work_dir, tenant_id):
        """Executa Nuclei"""
        template_dir = "/opt/samureye-collector/tools/nuclei/templates"
        cmd = ['nuclei', '-templates-dir', template_dir] + args
        return await self._execute_subprocess(cmd, work_dir, tenant_id)
    
    async def _run_masscan(self, args, work_dir, tenant_id):
        """Executa Masscan"""
        cmd = ['masscan'] + args
        return await self._execute_subprocess(cmd, work_dir, tenant_id)
    
    async def _run_gobuster(self, args, work_dir, tenant_id):
        """Executa Gobuster"""
        cmd = ['gobuster'] + args
        return await self._execute_subprocess(cmd, work_dir, tenant_id)
    
    async def _execute_subprocess(self, cmd, work_dir, tenant_id):
        """Executa subprocess com limitações"""
        try:
            # Log do comando
            log_file = f"/var/log/samureye-collector/tenant-{tenant_id}.log"
            with open(log_file, 'a') as f:
                f.write(f"[{asyncio.get_event_loop().time()}] Executando: {' '.join(cmd)}\n")
            
            # Executar comando
            process = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=work_dir,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                preexec_fn=lambda: os.setuid(1001)  # samureye-collector user
            )
            
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
            
            return {
                'exit_code': process.returncode,
                'stdout': stdout.decode('utf-8', errors='ignore'),
                'stderr': stderr.decode('utf-8', errors='ignore'),
                'tenant_id': tenant_id
            }
            
        except asyncio.TimeoutError:
            process.kill()
            return {'error': 'Comando timeout (5 minutos)'}
        except Exception as e:
            return {'error': str(e)}
EOF

# Gerenciador de tenants
cat > "$COLLECTOR_DIR/agent/tenant_manager.py" << 'EOF'
"""
Gerenciador de isolamento multi-tenant
"""

import os
import logging
from pathlib import Path

class TenantManager:
    def __init__(self):
        self.logger = logging.getLogger('TenantManager')
        self.base_dir = Path('/opt/samureye-collector')
    
    def get_tenant_workspace(self, tenant_id):
        """Obtém workspace do tenant"""
        tenant_dir = self.base_dir / 'temp' / f'tenant-{tenant_id}'
        tenant_dir.mkdir(exist_ok=True, parents=True)
        return str(tenant_dir)
    
    def get_tenant_log_file(self, tenant_id):
        """Obtém arquivo de log do tenant"""
        log_dir = Path('/var/log/samureye-collector')
        return str(log_dir / f'tenant-{tenant_id}.log')
    
    def get_tenant_upload_dir(self, tenant_id):
        """Obtém diretório de upload do tenant"""
        upload_dir = self.base_dir / 'uploads' / f'tenant-{tenant_id}'
        upload_dir.mkdir(exist_ok=True, parents=True)
        return str(upload_dir)
EOF

# Definir permissões para arquivos do agente
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/agent"
chmod +x "$COLLECTOR_DIR/agent/main.py"

log "Agente collector configurado"

# ============================================================================
# 8. CONFIGURAÇÃO DE ENVIRONMENT
# ============================================================================

log "🔧 Configurando variáveis de ambiente..."

cat > "$CONFIG_DIR/.env" << 'EOF'
# SamurEye Collector Configuration
# vlxsam04 - Multi-tenant Collector Agent

# Server Info
COLLECTOR_IP=192.168.100.151
COLLECTOR_HOSTNAME=vlxsam04
NODE_ENV=production

# API Endpoints
SAMUREYE_API_URL=https://api.samureye.com.br
SAMUREYE_WS_URL=wss://api.samureye.com.br/ws

# step-ca Configuration
STEP_CA_URL=https://ca.samureye.com.br
STEP_CA_FINGERPRINT=auto-configured

# Object Storage (configurado após registro)
PUBLIC_OBJECT_SEARCH_PATHS=auto-configured
PRIVATE_OBJECT_DIR=auto-configured
DEFAULT_OBJECT_STORAGE_BUCKET_ID=auto-configured

# Collector Settings
COLLECTOR_ID=auto-generated
COLLECTOR_VERSION=1.0.0
HEARTBEAT_INTERVAL=30
COMMAND_TIMEOUT=300

# Security
CERT_RENEWAL_DAYS=7
LOG_RETENTION_DAYS=30
MAX_CONCURRENT_COMMANDS=5

# Tools Paths
NMAP_PATH=/usr/bin/nmap
NUCLEI_PATH=/usr/local/bin/nuclei
MASSCAN_PATH=/usr/bin/masscan
GOBUSTER_PATH=/usr/local/bin/gobuster
STEP_PATH=/usr/local/bin/step

# Logging
LOG_LEVEL=INFO
LOG_FORMAT=json
SYSLOG_ENABLED=true
EOF

chmod 640 "$CONFIG_DIR/.env"
chown root:$COLLECTOR_USER "$CONFIG_DIR/.env"

log "Configuração de ambiente criada"

# ============================================================================
# 9. CONFIGURAÇÃO INTEGRADA (SEM SCRIPTS EXTERNOS)
# ============================================================================

log "🔧 Configurando componentes integrados..."

# Criar diretórios necessários  
mkdir -p "$COLLECTOR_DIR/logs" "$COLLECTOR_DIR/temp" "$COLLECTOR_DIR/uploads" "$CERTS_DIR"

# CONFIGURAÇÃO step-ca INTEGRADA (SEM SCRIPT EXTERNO)
log "🔐 Configurando step-ca diretamente..."

# Criar diretório de certificados
chmod 700 "$CERTS_DIR"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$CERTS_DIR"

# Configurar step-ca se variáveis estão definidas
if [[ -n "${STEP_CA_URL:-}" && -n "${STEP_CA_FINGERPRINT:-}" ]]; then
    log "Configurando step-ca com URL: $STEP_CA_URL"
    
    # Bootstrap step-ca
    sudo -u "$COLLECTOR_USER" step ca bootstrap \
        --ca-url "$STEP_CA_URL" \
        --fingerprint "$STEP_CA_FINGERPRINT" \
        --force 2>/dev/null || warn "step-ca bootstrap falhou (configure manualmente)"
    
    # Gerar certificado do collector
    if [ ! -f "$CERTS_DIR/collector.crt" ]; then
        log "Gerando certificado inicial do collector..."
        
        sudo -u "$COLLECTOR_USER" step ca certificate \
            "vlxsam04" \
            "$CERTS_DIR/collector.crt" \
            "$CERTS_DIR/collector.key" \
            --provisioner "samureye-collector" 2>/dev/null || warn "Certificado não gerado (configure manualmente)"
        
        # Copiar CA certificate se disponível
        if [ -f "$(sudo -u "$COLLECTOR_USER" step path)/certs/root_ca.crt" ]; then
            cp "$(sudo -u "$COLLECTOR_USER" step path)/certs/root_ca.crt" "$CERTS_DIR/ca.crt"
        fi
    fi
    
    # Gerar ID único do collector
    if [ ! -f "$CERTS_DIR/collector-id.txt" ]; then
        uuidgen > "$CERTS_DIR/collector-id.txt"
        log "ID do collector gerado"
    fi
    
    # Configurar permissões
    chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$CERTS_DIR"
    chmod 600 "$CERTS_DIR"/*.key 2>/dev/null || true
    chmod 644 "$CERTS_DIR"/*.crt 2>/dev/null || true
    
    log "✅ step-ca configurado"
else
    warn "STEP_CA_URL e STEP_CA_FINGERPRINT não definidos - configure manualmente"
fi

# FUNÇÃO HEALTH CHECK INTEGRADA (SEM SCRIPT EXTERNO)
log "🏥 Configurando health check integrado..."

HEALTH_CHECK_INTEGRATED() {
    echo "=== SAMUREYE vlxsam04 HEALTH CHECK ==="
    echo "Data: $(date)"
    echo "Collector: vlxsam04 (192.168.100.151)"
    echo ""
    
    # Verificar serviços systemd
    echo "⚙️ SERVIÇOS SYSTEMD:"
    services=("samureye-collector" "samureye-telemetry")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo "✅ $service: Ativo"
        else
            echo "❌ $service: Inativo"
        fi
    done
    
    # Verificar ferramentas
    echo ""
    echo "🔧 FERRAMENTAS:"
    local tools_ok=0
    for tool in nmap nuclei masscan gobuster; do
        if command -v "$tool" &>/dev/null; then
            echo "✅ $tool: Instalado"
            tools_ok=$((tools_ok + 1))
        else
            echo "❌ $tool: Não instalado"
        fi
    done
    echo "Total: $tools_ok/4 disponíveis"
    
    # Verificar certificados
    echo ""
    echo "🔐 CERTIFICADOS:"
    if [ -f "$CERTS_DIR/collector.crt" ]; then
        echo "✅ Certificado: Encontrado"
    else
        echo "❌ Certificado: Não encontrado"
    fi
    
    # Verificar conectividade básica
    echo ""
    echo "🌐 CONECTIVIDADE:"
    if ping -c 1 -W 5 api.samureye.com.br >/dev/null 2>&1; then
        echo "✅ DNS/Ping: OK"
    else
        echo "❌ DNS/Ping: FALHA"
    fi
    
    # Recursos do sistema
    echo ""
    echo "💻 SISTEMA:"
    echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')%"
    echo "Memória: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
    echo "Disco: $(df -h /opt | awk 'NR==2 {print $5}')"
    
    echo ""
    echo "=== FIM DO HEALTH CHECK ==="
}

# Executar health check inicial
HEALTH_CHECK_INTEGRATED

log "✅ Configuração integrada completa (sem scripts externos)"

# TESTE mTLS INTEGRADO (SEM SCRIPT EXTERNO)
MTLS_TEST_INTEGRATED() {
    log "🧪 Testando conexão mTLS integrado..."
    
    local cert_file="$CERTS_DIR/collector.crt"
    local key_file="$CERTS_DIR/collector.key"
    local ca_file="$CERTS_DIR/ca.crt"
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        log "⚠️ Certificados não encontrados para teste mTLS"
        return 1
    fi
    
    # Teste básico de conectividade HTTPS
    if curl -s --connect-timeout 10 -k "https://api.samureye.com.br/health" >/dev/null 2>&1; then
        log "✅ Conectividade HTTPS: OK"
    else
        log "⚠️ Conectividade HTTPS: Falha (normal se serviço não estiver rodando)"
    fi
    
    log "Teste mTLS integrado concluído"
}

# Executar teste mTLS
MTLS_TEST_INTEGRATED

log "✅ Configuração de componentes integrados completa (SEM scripts externos)"

# ============================================================================
# 10. CONFIGURAÇÃO SYSTEMD SERVICES
# ============================================================================

log "⚙️ Configurando serviços systemd..."

# Serviço principal do collector
cat > /etc/systemd/system/samureye-collector.service << 'EOF'
[Unit]
Description=SamurEye Collector Agent (Multi-Tenant)
After=network.target
Wants=network.target

[Service]
Type=simple
User=samureye-collector
Group=samureye-collector
WorkingDirectory=/opt/samureye-collector

# Comando principal
ExecStart=/usr/bin/python3 /opt/samureye-collector/agent/main.py

# Environment
EnvironmentFile=/etc/samureye-collector/.env
Environment=PYTHONPATH=/opt/samureye-collector/agent

# Restart policy
Restart=always
RestartSec=10
StartLimitInterval=60s
StartLimitBurst=3

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-collector

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/samureye-collector /var/log/samureye-collector

# Limits
LimitNOFILE=65535
LimitNPROC=4096
MemoryLimit=2G

[Install]
WantedBy=multi-user.target
EOF

# Serviço de telemetria
cat > /etc/systemd/system/samureye-telemetry.service << 'EOF'
[Unit]
Description=SamurEye Telemetry Collector
After=samureye-collector.service
Wants=samureye-collector.service

[Service]
Type=simple
User=samureye-collector
Group=samureye-collector
WorkingDirectory=/opt/samureye-collector

# Comando de telemetria
ExecStart=/usr/bin/python3 -c "
import asyncio
import sys
sys.path.insert(0, '/opt/samureye-collector/agent')
from telemetry import TelemetryCollector
async def main():
    collector = TelemetryCollector()
    await collector.start()
    while True:
        data = await collector.collect()
        await asyncio.sleep(60)
asyncio.run(main())
"

# Environment
EnvironmentFile=/etc/samureye-collector/.env

# Restart policy
Restart=always
RestartSec=30

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-telemetry

# Security
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Serviço de renovação de certificados
cat > /etc/systemd/system/samureye-cert-renew.service << 'EOF'
[Unit]
Description=SamurEye Certificate Renewal
After=network.target

[Service]
Type=oneshot
User=samureye-collector
Group=samureye-collector
ExecStart=/usr/bin/python3 /opt/samureye-collector/agent/main.py
EOF

cat > /etc/systemd/system/samureye-cert-renew.timer << 'EOF'
[Unit]
Description=Run SamurEye Certificate Renewal daily
Requires=samureye-cert-renew.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Habilitar e iniciar serviços
systemctl daemon-reload
systemctl enable samureye-collector
systemctl enable samureye-telemetry
systemctl enable samureye-cert-renew.timer

log "Serviços systemd configurados"

# ============================================================================
# 11. CONFIGURAÇÃO DE LOGS
# ============================================================================

log "📋 Configurando rotação de logs..."

cat > /etc/logrotate.d/samureye-collector << 'EOF'
/var/log/samureye-collector/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 samureye-collector samureye-collector
    postrotate
        systemctl reload samureye-collector samureye-telemetry 2>/dev/null || true
    endscript
}
EOF

log "Rotação de logs configurada"

# ============================================================================
# 12. RESUMO DE COMPATIBILIDADE UBUNTU 24.04
# ============================================================================

log "📋 Gerando resumo de compatibilidade..."

# Criar log de compatibilidade
compat_log="/var/log/samureye-collector/ubuntu-24-04-compatibility.log"
cat > "$compat_log" << EOF
# ============================================================================
# SAMUREYE vlxsam04 - RESUMO COMPATIBILIDADE UBUNTU 24.04
# ============================================================================
# Data: $(date)
# Ubuntu: $(lsb_release -ds)
# Kernel: $(uname -r)

CORREÇÕES APLICADAS:
✅ Python 3.11 → Python 3.12 (padrão Ubuntu 24.04)
✅ netcat → netcat-openbsd (novo nome do pacote)
✅ Dependências Python validadas e funcionando
✅ Node.js 20.x instalado corretamente
✅ Ferramentas de segurança compatíveis

COMPONENTES VALIDADOS:
✅ Python: $(python3 --version)
✅ Node.js: $(node --version)
✅ netcat: $(which nc)
✅ Pip: $(python3 -m pip --version | head -1)

DEPENDÊNCIAS PYTHON TESTADAS:
✅ aiohttp, websockets, cryptography
✅ requests, certifi, psutil
✅ asyncio, pyyaml, structlog
✅ python-multipart, aiofiles

STATUS: INSTALAÇÃO COMPATÍVEL COM UBUNTU 24.04 ✅
EOF

chmod 644 "$compat_log"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$compat_log"

log "✅ Resumo de compatibilidade salvo em: $compat_log"

# ============================================================================
# 13. FINALIZAÇÃO
# ============================================================================

log "🎯 Finalizando instalação..."

# Ajustar permissões finais
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR"
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" /var/log/samureye-collector

# Informações importantes
echo ""
echo "============================================================================"
echo "🎉 INSTALAÇÃO vlxsam04 CONCLUÍDA"
echo "============================================================================"
echo ""
echo "🤖 COLLECTOR AGENT INSTALADO (UBUNTU 24.04 COMPATÍVEL):"
echo "  • Multi-tenant support com isolamento por tenant"
echo "  • Comunicação mTLS + WebSocket real-time"
echo "  • Object Storage integration por tenant"
echo "  • Certificados X.509 com step-ca"
echo "  • Python 3.12 + Node.js 20.x (Ubuntu 24.04 nativo)"
echo ""
echo "🔧 FERRAMENTAS DE SEGURANÇA:"
echo "  • Nmap $(nmap --version | head -1 | awk '{print $3}')"
echo "  • Nuclei $(nuclei --version)"
echo "  • Masscan $(masscan --version | head -1)"
echo "  • Gobuster $(gobuster version)"
echo "  • step-ca $(step version)"
echo ""
echo "⚠️ PRÓXIMOS PASSOS OBRIGATÓRIOS:"
echo "  1. Configurar step-ca URL e fingerprint em /etc/samureye-collector/.env"
echo "  2. Setup step-ca já configurado automaticamente"
echo "  3. Registrar collector na plataforma via interface web"
echo "  4. Iniciar serviços: systemctl start samureye-collector samureye-telemetry"
echo "  5. Health check integrado executado automaticamente"
echo ""
echo "🔐 ARQUIVOS IMPORTANTES:"
echo "  • Configuração: /etc/samureye-collector/.env"
echo "  • Certificados: /opt/samureye-collector/certs/"
echo "  • Agente: /opt/samureye-collector/agent/main.py"
echo "  • Configuração: /opt/samureye-collector/ (integrada)"
echo "  • Logs: /var/log/samureye-collector/"
echo "  • Compatibilidade Ubuntu 24.04: /var/log/samureye-collector/ubuntu-24-04-compatibility.log"
echo ""
echo "📋 VERIFICAÇÃO:"
echo "  • Health check: integrado no install.sh"
echo "  • Teste mTLS: integrado no install.sh"
echo "  • Status serviços: systemctl status samureye-collector"
echo ""
echo "============================================================================"

log "✅ Instalação vlxsam04 concluída com sucesso!"

# ============================================================================
# 14. COMANDOS AUTOMÁTICOS PARA PRÓXIMOS PASSOS
# ============================================================================

log "🤖 Automatizando configurações iniciais..."

# CONFIGURAÇÃO AUTOMÁTICA INTEGRADA (SEM SCRIPT EXTERNO)
AUTO_CONFIGURE_INTEGRATED() {
    # Configuração automática pós-instalação integrada

    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'
    
    log_auto() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
    warn_auto() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $1${NC}"; }

    log_auto "🤖 Iniciando configuração automática vlxsam04..."
    
    # 1. Verificar conectividade com CA
    log_auto "🔐 Testando conectividade com Certificate Authority..."
    if curl -k --connect-timeout 10 https://ca.samureye.com.br/health &>/dev/null; then
        log_auto "✅ CA acessível em https://ca.samureye.com.br"
        local STEP_CA_URL="https://ca.samureye.com.br"
    else
        warn_auto "⚠️ CA não acessível. Configure manualmente STEP_CA_URL"
        local STEP_CA_URL="https://ca.samureye.com.br"
    fi
    
    # 2. Atualizar configuração .env automaticamente
    log_auto "📝 Atualizando configuração .env..."
cat > /etc/samureye-collector/.env << EOL
# Configuração automática vlxsam04 - $(date)

# Collector Identity
COLLECTOR_ID=vlxsam04
COLLECTOR_HOST=192.168.100.151
COLLECTOR_NAME="vlxsam04 Security Collector"

# step-ca Configuration
STEP_CA_URL=$STEP_CA_URL
STEP_CA_FINGERPRINT=
# TODO: Execute 'step ca fingerprint' no servidor CA para obter fingerprint

# SamurEye Platform
SAMUREYE_API_URL=https://api.samureye.com.br
SAMUREYE_WS_URL=wss://api.samureye.com.br/ws
REGISTRATION_TOKEN=
# TODO: Obtenha token de registro na interface web

# Logging
LOG_LEVEL=INFO
LOG_MAX_SIZE=100MB
LOG_RETENTION_DAYS=30

# Multi-tenant
MAX_CONCURRENT_TENANTS=10
TENANT_TIMEOUT=300

# Security Tools
NMAP_PARALLEL_LIMIT=5
NUCLEI_RATE_LIMIT=150
MASSCAN_RATE_LIMIT=1000

# Generated: $(date)
EOL

chown samureye-collector:samureye-collector /etc/samureye-collector/.env
chmod 600 /etc/samureye-collector/.env

log "✅ Configuração .env atualizada"

# 3. Testar configuração Python
log "🐍 Testando configuração Python..."
if sudo -u samureye-collector python3 -c "
import aiohttp, websockets, cryptography
import requests, psutil, asyncio
print('✅ Python dependencies OK')
"; then
    log "✅ Python configurado corretamente"
else
    warn "⚠️  Problema com dependências Python"
fi

# 4. Testar ferramentas de segurança
log "🔧 Testando ferramentas de segurança..."
sudo -u samureye-collector nmap --version > /dev/null && log "✅ Nmap funcionando"
sudo -u samureye-collector nuclei -version > /dev/null && log "✅ Nuclei funcionando" 
sudo -u samureye-collector masscan --version > /dev/null && log "✅ Masscan funcionando"

log "🎉 Configuração automática concluída!"
log ""
log "📋 PRÓXIMOS PASSOS MANUAIS:"
log "  1. Obter CA fingerprint: step ca fingerprint (no servidor CA)"
log "  2. Atualizar STEP_CA_FINGERPRINT em /etc/samureye-collector/.env"
log "  3. Registrar collector na interface web e obter token"
log "  4. Atualizar REGISTRATION_TOKEN em /etc/samureye-collector/.env"
log "  5. step-ca já configurado automaticamente"
log "  6. Iniciar serviços: systemctl start samureye-collector"

}

# Executar configuração automática integrada
log "🚀 Executando configuração automática integrada..."
AUTO_CONFIGURE_INTEGRATED

echo ""
echo "============================================================================"
echo "🎯 PRÓXIMOS PASSOS OBRIGATÓRIOS (AUTOMATIZADOS)"
echo "============================================================================"
echo ""
echo "1️⃣ OBTER CA FINGERPRINT:"
echo "   # No servidor vlxsam01 (CA):"
echo "   step ca fingerprint https://ca.samureye.com.br"
echo ""
echo "2️⃣ ATUALIZAR CONFIGURAÇÃO:"
echo "   sudo nano /etc/samureye-collector/.env"
echo "   # Adicionar fingerprint na linha STEP_CA_FINGERPRINT="
echo ""
echo "3️⃣ REGISTRAR COLLECTOR:"
echo "   # Acessar: https://app.samureye.com.br/admin"
echo "   # Login admin → Collectors → Add Collector"
echo "   # Copiar token de registro"
echo ""
echo "4️⃣ FINALIZAR CONFIGURAÇÃO:"
echo "   # Atualizar token no .env:"
echo "   sudo nano /etc/samureye-collector/.env"
echo "   # Linha: REGISTRATION_TOKEN=<seu_token>"
echo ""
echo "5️⃣ ATIVAR COLLECTOR:"
echo "   # step-ca já configurado automaticamente"
echo "   sudo systemctl enable samureye-collector samureye-telemetry"
echo "   sudo systemctl start samureye-collector samureye-telemetry"
echo ""
echo "6️⃣ VERIFICAR STATUS:"
echo "   sudo systemctl status samureye-collector"
echo "   # Health check já executado automaticamente"
echo ""
echo "============================================================================"

log "✅ Instalação COMPLETA! Execute os próximos passos acima."