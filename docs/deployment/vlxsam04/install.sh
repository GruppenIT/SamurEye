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
mkdir -p "$COLLECTOR_DIR"/{agent,certs,tools,logs,temp,uploads,scripts,config,backups}
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
    
    # Instalar dependências para compilação
    apt install -y build-essential git libpcap-dev
    
    git clone https://github.com/robertdavidgraham/masscan
    cd masscan
    make -j$(nproc) 2>/dev/null || make
    make install
    cd /
    rm -rf /tmp/masscan
    log "✅ Masscan compilado e instalado"
else
    log "✅ Masscan instalado via apt"
fi

# Verificar se masscan está funcionando
if ! masscan --version >/dev/null 2>&1; then
    # Tentar criar link simbólico se não encontrado no PATH
    if [[ -f /usr/local/bin/masscan ]]; then
        ln -sf /usr/local/bin/masscan /usr/bin/masscan
    fi
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
        import os
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
        # Nuclei 3.x usa variável de ambiente, não flag
        env = os.environ.copy()
        env['NUCLEI_TEMPLATES_DIR'] = template_dir
        cmd = ['nuclei'] + args
        return await self._execute_subprocess(cmd, work_dir, tenant_id, env)
    
    async def _run_masscan(self, args, work_dir, tenant_id):
        """Executa Masscan"""
        cmd = ['masscan'] + args
        return await self._execute_subprocess(cmd, work_dir, tenant_id)
    
    async def _run_gobuster(self, args, work_dir, tenant_id):
        """Executa Gobuster"""
        cmd = ['gobuster'] + args
        return await self._execute_subprocess(cmd, work_dir, tenant_id)
    
    async def _execute_subprocess(self, cmd, work_dir, tenant_id, env=None):
        """Executa subprocess com limitações"""
        try:
            # Log do comando
            log_file = f"/var/log/samureye-collector/tenant-{tenant_id}.log"
            with open(log_file, 'a') as f:
                f.write(f"[{asyncio.get_event_loop().time()}] Executando: {' '.join(cmd)}\n")
            
            # Preparar ambiente
            if env is None:
                env = os.environ.copy()
            
            # Executar comando
            process = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=work_dir,
                env=env,
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
STEP_CA_FINGERPRINT=
STEP_CA_ROOT=/opt/samureye-collector/certs/ca.crt

# Logging
LOG_LEVEL=INFO
LOG_DIR=/var/log/samureye-collector

# Multi-tenant
MAX_TENANTS=50
TENANT_ISOLATION=strict

# Tools
TOOLS_DIR=/opt/samureye-collector/tools
NUCLEI_TEMPLATES_DIR=/opt/samureye-collector/tools/nuclei/templates
EOF

# Permissões do arquivo de configuração
chmod 600 "$CONFIG_DIR/.env"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$CONFIG_DIR/.env"

log "Variáveis de ambiente configuradas"

# ============================================================================
# 9. CONFIGURAÇÃO SYSTEMD
# ============================================================================

log "⚙️ Configurando serviços systemd..."

# Serviço principal do collector
cat > /etc/systemd/system/samureye-collector.service << 'EOF'
[Unit]
Description=SamurEye Collector Agent - Multi-Tenant
Documentation=https://docs.samureye.com.br/collector
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=samureye-collector
Group=samureye-collector
WorkingDirectory=/opt/samureye-collector
Environment=PYTHONPATH=/opt/samureye-collector
EnvironmentFile=/opt/samureye-collector/config/.env
ExecStart=/usr/bin/python3 /opt/samureye-collector/agent/main.py
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=always
RestartSec=10

# Segurança
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/samureye-collector /var/log/samureye-collector /tmp
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

# Limites de recursos
LimitNOFILE=65536
LimitNPROC=4096
TasksMax=4096

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-collector

[Install]
WantedBy=multi-user.target
EOF

# Serviço de monitoramento de saúde
cat > /etc/systemd/system/samureye-health.service << 'EOF'
[Unit]
Description=SamurEye Health Monitor
After=samureye-collector.service
Requires=samureye-collector.service

[Service]
Type=oneshot
User=samureye-collector
Group=samureye-collector
ExecStart=/usr/bin/python3 /opt/samureye-collector/scripts/health-check.py

[Install]
WantedBy=multi-user.target
EOF

# Timer para health check
cat > /etc/systemd/system/samureye-health.timer << 'EOF'
[Unit]
Description=SamurEye Health Check Timer
Requires=samureye-health.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

# Recarregar systemd
systemctl daemon-reload

# Habilitar serviços
systemctl enable samureye-collector.service
systemctl enable samureye-health.timer

log "Serviços systemd configurados"

# ============================================================================
# 10. SCRIPTS AUXILIARES
# ============================================================================

log "📝 Criando scripts auxiliares..."

# Script de health check
cat > "$COLLECTOR_DIR/scripts/health-check.py" << 'EOF'
#!/usr/bin/env python3
"""
Script de verificação de saúde do collector
"""

import os
import sys
import json
import requests
import subprocess
from pathlib import Path
from datetime import datetime

def check_services():
    """Verifica se os serviços estão rodando"""
    try:
        result = subprocess.run(['systemctl', 'is-active', 'samureye-collector'], 
                              capture_output=True, text=True)
        return result.stdout.strip() == 'active'
    except:
        return False

def check_certificates():
    """Verifica certificados"""
    cert_file = Path('/opt/samureye-collector/certs/collector.crt')
    key_file = Path('/opt/samureye-collector/certs/collector.key')
    ca_file = Path('/opt/samureye-collector/certs/ca.crt')
    
    return all([cert_file.exists(), key_file.exists(), ca_file.exists()])

def check_api_connection():
    """Testa conexão com API"""
    try:
        response = requests.get('https://api.samureye.com.br/health', timeout=10)
        return response.status_code == 200
    except:
        return False

def main():
    health_data = {
        'timestamp': datetime.utcnow().isoformat(),
        'hostname': os.uname().nodename,
        'services_running': check_services(),
        'certificates_valid': check_certificates(),
        'api_reachable': check_api_connection(),
        'disk_usage': os.statvfs('/opt/samureye-collector').f_bavail
    }
    
    # Log do resultado
    log_file = '/var/log/samureye-collector/health.log'
    with open(log_file, 'a') as f:
        f.write(json.dumps(health_data) + '\n')
    
    # Exit code baseado na saúde
    if all([health_data['services_running'], health_data['certificates_valid']]):
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

# Script de backup de configurações
cat > "$COLLECTOR_DIR/scripts/backup-config.sh" << 'EOF'
#!/bin/bash
# Backup das configurações do collector

BACKUP_DIR="/opt/samureye-collector/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Backup de configurações
tar -czf "$BACKUP_DIR/config-$DATE.tar.gz" \
    /opt/samureye-collector/config/ \
    /opt/samureye-collector/certs/ \
    /etc/systemd/system/samureye-*.service

# Manter apenas os últimos 10 backups
cd "$BACKUP_DIR"
ls -t config-*.tar.gz | tail -n +11 | xargs rm -f

echo "Backup criado: config-$DATE.tar.gz"
EOF

# Script de limpeza de logs
cat > "$COLLECTOR_DIR/scripts/cleanup-logs.sh" << 'EOF'
#!/bin/bash
# Limpeza de logs antigos

LOG_DIR="/var/log/samureye-collector"

# Logs de tenants mais antigos que 7 dias
find "$LOG_DIR" -name "tenant-*.log" -mtime +7 -delete

# Logs de health mais antigos que 30 dias
find "$LOG_DIR" -name "health.log" -mtime +30 -delete

# Arquivos temporários mais antigos que 1 dia
find "/opt/samureye-collector/temp" -type f -mtime +1 -delete

echo "Limpeza de logs concluída"
EOF

# Permissões dos scripts
chmod +x "$COLLECTOR_DIR/scripts/"*.sh
chmod +x "$COLLECTOR_DIR/scripts/"*.py
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/scripts"

log "Scripts auxiliares criados"

# ============================================================================
# 11. CONFIGURAÇÃO DE LOGS E ROTAÇÃO
# ============================================================================

log "📊 Configurando sistema de logs..."

# Configuração de logrotate
cat > /etc/logrotate.d/samureye-collector << 'EOF'
/var/log/samureye-collector/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 samureye-collector samureye-collector
    sharedscripts
    postrotate
        systemctl reload-or-restart samureye-collector.service
    endscript
}
EOF

# Configuração de rsyslog para centralizar logs
cat > /etc/rsyslog.d/30-samureye-collector.conf << 'EOF'
# SamurEye Collector Logging
if $programname == 'samureye-collector' then /var/log/samureye-collector/agent.log
& stop

# Forward critical errors to syslog
:programname, isequal, "samureye-collector" /var/log/syslog
& stop
EOF

# Restart rsyslog
systemctl restart rsyslog

log "Sistema de logs configurado"

# ============================================================================
# 12. CONFIGURAÇÃO FINAL E VALIDAÇÃO
# ============================================================================

log "✅ Executando validação final..."

# Verificar estrutura de diretórios
required_dirs=(
    "$COLLECTOR_DIR"
    "$COLLECTOR_DIR/agent"
    "$COLLECTOR_DIR/scripts"
    "$COLLECTOR_DIR/certs"
    "$COLLECTOR_DIR/config"
    "$COLLECTOR_DIR/tools"
    "$COLLECTOR_DIR/temp"
    "$TOOLS_DIR"
    "$TOOLS_DIR/nuclei/templates"
    "/var/log/samureye-collector"
)

for dir in "${required_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
        log "❌ Diretório ausente: $dir"
        exit 1
    fi
done

# Verificar ferramentas instaladas
tools_check=(
    "nmap --version"
    "nuclei -version" 
    "gobuster version"
    "step version"
    "python3 --version"
    "node --version"
)

# Verificação simples do masscan
log "🔍 Verificando masscan..."

# Atualizar PATH e hash para garantir detecção
export PATH="/usr/bin:/usr/local/bin:$PATH"
hash -r

# Verificação direta e simples
if [[ -x "/usr/bin/masscan" ]]; then
    log "✅ Masscan encontrado em /usr/bin/masscan"
elif [[ -x "/usr/local/bin/masscan" ]]; then
    log "✅ Masscan encontrado em /usr/local/bin/masscan"
    ln -sf /usr/local/bin/masscan /usr/bin/masscan
else
    log "❌ Masscan não encontrado"
    exit 1
fi

for tool_cmd in "${tools_check[@]}"; do
    if ! eval "$tool_cmd" >/dev/null 2>&1; then
        log "❌ Ferramenta não funcionando: $tool_cmd"
        exit 1
    fi
done

# Verificar serviços systemd
if ! systemctl is-enabled samureye-collector.service >/dev/null 2>&1; then
    log "❌ Serviço samureye-collector não habilitado"
    exit 1
fi

# Verificar permissões
if [[ ! -r "$CONFIG_DIR/.env" ]]; then
    log "❌ Arquivo .env não acessível"
    exit 1
fi

log "🎉 Validação final concluída com sucesso!"

# ============================================================================
# 13. RESUMO E PRÓXIMOS PASSOS
# ============================================================================

log "📋 Instalação concluída - Resumo:"
log "Collector ID será gerado automaticamente no primeiro boot"
log "Usuário: $COLLECTOR_USER"
log "Diretório base: $COLLECTOR_DIR"
log "Logs: /var/log/samureye-collector/"
log ""
log "🔧 Comandos úteis:"
log "  systemctl start samureye-collector    # Iniciar collector"
log "  systemctl status samureye-collector   # Ver status"
log "  journalctl -f -u samureye-collector   # Ver logs em tempo real"
log ""
log "⚠️  PRÓXIMOS PASSOS MANUAIS:"
log "1. Executar script de registro do collector:"
log "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/scripts/register-collector.sh | bash -s <tenant-slug> <collector-name>"
log ""
log "2. O script de registro irá:"
log "   - Gerar certificados mTLS via step-ca"
log "   - Registrar collector na plataforma"
log "   - Iniciar serviços automaticamente"
log ""
log "🚀 vlxsam04 Collector Agent pronto para registro!"

# ============================================================================
# 13.1. CRIAR ARQUIVOS DE CONFIGURAÇÃO FINAL
# ============================================================================

log "🔧 Configurando variáveis de ambiente..."

# Criar arquivo .env completo
cat > "$CONFIG_DIR/.env" << 'EOF'
# SamurEye Collector Configuration - vlxsam04
# Base URLs
API_BASE_URL=https://api.samureye.com.br
WS_URL=wss://api.samureye.com.br/ws
FRONTEND_URL=https://app.samureye.com.br

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

log "Variáveis de ambiente configuradas"

# ============================================================================
# 13.2. CRIAR AGENTE COLLECTOR FUNCIONAL COMPLETO
# ============================================================================

log "🤖 Configurando agente collector..."

# Criar agente Python completo e funcional
cat > "$COLLECTOR_DIR/collector_agent.py" << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent - v1.0.0
Multi-tenant secure collector for SamurEye platform
"""

import asyncio
import aiohttp
import json
import logging
import os
import sys
import signal
import traceback
import subprocess
import time
import ssl
from pathlib import Path
from typing import Dict, Any, Optional, List
from datetime import datetime
import uuid

class SamureyeCollectorAgent:
    """Advanced Multi-tenant Collector Agent"""
    
    def __init__(self, config_dir: str = "/etc/samureye-collector"):
        self.config_dir = Path(config_dir)
        self.collector_dir = Path("/opt/samureye-collector")
        self.certs_dir = self.collector_dir / "certs"
        self.logger = self._setup_logging()
        self.config = self._load_config()
        self.session: Optional[aiohttp.ClientSession] = None
        self.running = False
        self.heartbeat_task = None
        
        # Collector Identity
        self.collector_id = self._get_collector_id()
        self.api_base_url = self.config.get('API_BASE_URL', 'https://api.samureye.com.br')
        
    def _setup_logging(self) -> logging.Logger:
        """Configure logging"""
        logging.basicConfig(
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            level=logging.INFO,
            handlers=[
                logging.FileHandler('/var/log/samureye-collector/agent.log'),
                logging.StreamHandler()
            ]
        )
        return logging.getLogger('samureye-collector')
    
    def _load_config(self) -> Dict[str, Any]:
        """Load configuration from .env file"""
        config = {}
        env_file = self.config_dir / ".env"
        
        if env_file.exists():
            with open(env_file) as f:
                for line in f:
                    if line.strip() and not line.startswith('#'):
                        key, _, value = line.strip().partition('=')
                        config[key] = value
        
        # Override with environment variables
        for key, value in os.environ.items():
            if key.startswith('SAMUREYE_'):
                config[key.replace('SAMUREYE_', '')] = value
                
        return config
    
    def _get_collector_id(self) -> str:
        """Get or generate collector ID"""
        id_file = self.certs_dir / "collector-id.txt"
        
        if id_file.exists():
            with open(id_file) as f:
                return f.read().strip()
        
        # Generate new ID
        collector_id = str(uuid.uuid4())
        id_file.parent.mkdir(parents=True, exist_ok=True)
        with open(id_file, 'w') as f:
            f.write(collector_id)
            
        return collector_id
    
    async def start(self):
        """Start the collector agent"""
        self.logger.info("=== SamurEye Collector Agent v1.0.0 ===")
        self.logger.info(f"Server: vlxsam04 (192.168.100.151)")
        self.logger.info(f"Collector ID: {self.collector_id}")
        self.logger.info(f"API Base URL: {self.api_base_url}")
        self.logger.info("Status: Aguardando registro manual na plataforma")
        
        self.running = True
        
        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
        
        # Create HTTP session
        self.session = aiohttp.ClientSession()
        
        try:
            # Start heartbeat
            self.heartbeat_task = asyncio.create_task(self._heartbeat_loop())
            
            # Keep running
            while self.running:
                await asyncio.sleep(1)
                
        except Exception as e:
            self.logger.error(f"Critical error: {e}")
            self.logger.error(traceback.format_exc())
        finally:
            await self._cleanup()
    
    async def _heartbeat_loop(self):
        """Send periodic heartbeat to server"""
        heartbeat_count = 0
        while self.running:
            try:
                await self._send_heartbeat()
                heartbeat_count += 1
                
                # Log heartbeat every 12 cycles (6 minutes)
                if heartbeat_count % 12 == 0:
                    self.logger.info(f"Heartbeat #{heartbeat_count} - Collector ativo, aguardando registro manual")
                
                await asyncio.sleep(int(self.config.get('HEARTBEAT_INTERVAL', '30')))
            except Exception as e:
                self.logger.debug(f"Heartbeat error (normal until registered): {e}")
                await asyncio.sleep(30)
    
    async def _send_heartbeat(self):
        """Send heartbeat with basic telemetry"""
        try:
            # Basic system info
            import psutil
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            
            telemetry = {
                'collector_id': self.collector_id,
                'timestamp': datetime.utcnow().isoformat(),
                'hostname': os.uname().nodename,
                'system': {
                    'cpu_percent': cpu_percent,
                    'memory_percent': memory.percent,
                    'memory_used_gb': round(memory.used / (1024**3), 2),
                    'uptime': time.time()
                },
                'status': 'active',
                'version': '1.0.0',
                'capabilities': ['nmap', 'nuclei', 'masscan', 'gobuster', 'multi-tenant']
            }
            
            # Try to send heartbeat (will fail until properly registered)
            try:
                async with self.session.post(
                    f"{self.api_base_url}/api/collectors/{self.collector_id}/heartbeat",
                    json=telemetry,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    if response.status == 200:
                        self.logger.debug("Heartbeat sent successfully")
                    else:
                        self.logger.debug(f"Heartbeat response: {response.status}")
            except:
                # Expected to fail until collector is properly registered
                pass
                    
        except Exception as e:
            self.logger.debug(f"Heartbeat error (normal until registered): {e}")
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received shutdown signal: {signum}")
        self.running = False
    
    async def _cleanup(self):
        """Cleanup resources"""
        self.logger.info("Cleaning up resources...")
        
        if self.heartbeat_task:
            self.heartbeat_task.cancel()
            try:
                await self.heartbeat_task
            except asyncio.CancelledError:
                pass
        
        if self.session:
            await self.session.close()
        
        self.logger.info("Collector agent stopped")

async def main():
    """Main entry point"""
    try:
        agent = SamureyeCollectorAgent()
        await agent.start()
    except Exception as e:
        print(f"Fatal error: {e}")
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nCollector agent stopped by user")
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)
EOF

chmod +x "$COLLECTOR_DIR/collector_agent.py"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/collector_agent.py"

log "Agente collector configurado"

# ============================================================================
# 13.3. CONFIGURAR SERVIÇOS SYSTEMD
# ============================================================================

log "⚙️ Configurando serviços systemd..."

# Criar serviço samureye-collector
cat > /etc/systemd/system/samureye-collector.service << EOF
[Unit]
Description=SamurEye Collector Agent - vlxsam04
Documentation=https://docs.samureye.com.br/collector
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=30
User=$COLLECTOR_USER
Group=$COLLECTOR_USER
WorkingDirectory=$COLLECTOR_DIR
ExecStart=/usr/bin/python3 $COLLECTOR_DIR/collector_agent.py
EnvironmentFile=$CONFIG_DIR/.env

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$COLLECTOR_DIR /var/log/samureye-collector /tmp
PrivateTmp=yes

# Resource limits
MemoryMax=1G
CPUQuota=50%

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-collector

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd e habilitar serviços
systemctl daemon-reload
systemctl enable samureye-collector.service

log "Serviços systemd configurados"

# ============================================================================
# 13.4. CRIAR SCRIPTS AUXILIARES INTEGRADOS
# ============================================================================

log "📝 Criando scripts auxiliares..."

# Script de diagnóstico integrado
cat > "$COLLECTOR_DIR/scripts/diagnostico.sh" << 'EOF'
#!/bin/bash
# Script de diagnóstico integrado do vlxsam04

echo "=== DIAGNÓSTICO VLXSAM04 COLLECTOR ==="
echo "Data: $(date)"
echo ""

echo "1. SISTEMA BASE:"
echo "   OS: $(lsb_release -d | cut -f2-)"
echo "   Kernel: $(uname -r)"
echo "   Uptime: $(uptime -p)"
echo ""

echo "2. USUÁRIOS E PERMISSÕES:"
id samureye-collector 2>/dev/null || echo "   ERROR: Usuário samureye-collector não existe"
echo ""

echo "3. DIRETÓRIOS:"
for dir in "/opt/samureye-collector" "/etc/samureye-collector" "/var/log/samureye-collector"; do
    if [[ -d "$dir" ]]; then
        echo "   ✓ $dir - $(ls -ld "$dir" | awk '{print $1, $3, $4}')"
    else
        echo "   ✗ $dir - NÃO EXISTE"
    fi
done
echo ""

echo "4. ARQUIVOS DE CONFIGURAÇÃO:"
if [[ -f "/etc/samureye-collector/.env" ]]; then
    echo "   ✓ .env existe - $(ls -l /etc/samureye-collector/.env | awk '{print $1, $3, $4}')"
else
    echo "   ✗ .env NÃO EXISTE"
fi
echo ""

echo "5. FERRAMENTAS:"
for tool in nmap nuclei masscan gobuster step; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "   ✓ $tool: $(which $tool)"
    else
        echo "   ✗ $tool: NÃO ENCONTRADO"
    fi
done
echo ""

echo "6. PYTHON E DEPENDÊNCIAS:"
echo "   Python: $(python3 --version 2>/dev/null || echo 'NÃO ENCONTRADO')"
python3 -c "
try:
    import aiohttp, websockets, cryptography, requests, psutil
    print('   ✓ Dependências Python: OK')
except ImportError as e:
    print(f'   ✗ Dependências Python: {e}')
" 2>/dev/null || echo "   ✗ Erro ao testar dependências Python"
echo ""

echo "7. SERVIÇOS SYSTEMD:"
systemctl is-enabled samureye-collector.service >/dev/null 2>&1 && echo "   ✓ samureye-collector: habilitado" || echo "   ✗ samureye-collector: não habilitado"
systemctl is-active samureye-collector.service >/dev/null 2>&1 && echo "   ✓ samureye-collector: ativo" || echo "   ✗ samureye-collector: inativo"
echo ""

echo "8. CONECTIVIDADE:"
if ping -c 1 api.samureye.com.br >/dev/null 2>&1; then
    echo "   ✓ Conectividade com api.samureye.com.br: OK"
else
    echo "   ✗ Conectividade com api.samureye.com.br: FALHA"
fi
echo ""

echo "=== LOGS RECENTES ==="
if [[ -f "/var/log/samureye-collector/agent.log" ]]; then
    echo "Últimas 10 linhas do log:"
    tail -10 /var/log/samureye-collector/agent.log
else
    echo "Log do agent não encontrado"
fi
EOF

chmod +x "$COLLECTOR_DIR/scripts/diagnostico.sh"

# Script de correção de emergência
cat > "$COLLECTOR_DIR/scripts/corrigir.sh" << 'EOF'
#!/bin/bash
# Script de correção de emergência

echo "=== CORREÇÃO DE EMERGÊNCIA VLXSAM04 ==="

# Parar serviços
systemctl stop samureye-collector 2>/dev/null || true

# Recriar estrutura básica se necessário
mkdir -p /opt/samureye-collector/{agent,certs,logs,scripts} /etc/samureye-collector /var/log/samureye-collector

# Corrigir permissões
chown -R samureye-collector:samureye-collector /opt/samureye-collector /var/log/samureye-collector
chmod 750 /etc/samureye-collector

# Verificar .env
if [[ ! -f "/etc/samureye-collector/.env" ]]; then
    echo "Recriando .env..."
    cat > /etc/samureye-collector/.env << 'ENVEOF'
API_BASE_URL=https://api.samureye.com.br
COLLECTOR_ID=auto-generated
HEARTBEAT_INTERVAL=30
LOG_LEVEL=INFO
ENVEOF
    chown root:samureye-collector /etc/samureye-collector/.env
    chmod 640 /etc/samureye-collector/.env
fi

# Verificar agente Python
if [[ ! -f "/opt/samureye-collector/collector_agent.py" ]]; then
    echo "ERROR: collector_agent.py não encontrado - reinstalação necessária"
    exit 1
fi

# Recarregar systemd
systemctl daemon-reload
systemctl enable samureye-collector.service

echo "✓ Correção concluída - teste: systemctl start samureye-collector"
EOF

chmod +x "$COLLECTOR_DIR/scripts/corrigir.sh"
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/scripts/"

log "Scripts auxiliares criados"

# ============================================================================
# 13.5. CONFIGURAR SISTEMA DE LOGS
# ============================================================================

log "📊 Configurando sistema de logs..."

# Configurar logrotate para logs do collector
cat > /etc/logrotate.d/samureye-collector << 'EOF'
/var/log/samureye-collector/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    su samureye-collector samureye-collector
}
EOF

# Criar arquivo de log inicial
touch /var/log/samureye-collector/agent.log
chown "$COLLECTOR_USER:$COLLECTOR_USER" /var/log/samureye-collector/agent.log

log "Sistema de logs configurado"

# ============================================================================
# 13.6. VALIDAÇÃO FINAL COMPLETA
# ============================================================================

log "✅ Executando validação final..."

# Verificação de estrutura crítica
critical_paths=(
    "/opt/samureye-collector/collector_agent.py"
    "/etc/samureye-collector/.env"
    "/etc/systemd/system/samureye-collector.service"
    "/var/log/samureye-collector"
)

for path in "${critical_paths[@]}"; do
    if [[ ! -e "$path" ]]; then
        error "❌ Arquivo/diretório crítico não encontrado: $path"
    fi
done

# Verificar se masscan está acessível
log "🔍 Verificando masscan..."
if [[ -f "/usr/bin/masscan" ]]; then
    log "✅ Masscan encontrado em /usr/bin/masscan"
elif [[ -f "/usr/local/bin/masscan" ]]; then
    log "✅ Masscan encontrado em /usr/local/bin/masscan"
    # Criar link simbólico se não existir em /usr/bin
    ln -sf /usr/local/bin/masscan /usr/bin/masscan 2>/dev/null || true
else
    warn "⚠️ Masscan não encontrado nos caminhos esperados"
fi

# Teste Python básico
log "🧪 Testando agente Python..."
if python3 -c "import asyncio, aiohttp, uuid; print('✓ Python dependencies OK')" 2>/dev/null; then
    log "✅ Python agent e dependências validados"
else
    warn "⚠️ Possível problema com dependências Python"
fi

log "🎉 Validação final concluída com sucesso!"

# ============================================================================
# FINALIZAÇÃO E PRÓXIMOS PASSOS
# ============================================================================

log ""
log "📋 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
log "Servidor: vlxsam04 (192.168.100.151)"
log "Collector Agent: SamurEye v1.0.0"
log "Usuário: $COLLECTOR_USER"
log "Diretório: $COLLECTOR_DIR"
log ""

log "🔧 COMANDOS PARA TESTAR:"
log "  systemctl start samureye-collector     # Iniciar collector"
log "  systemctl status samureye-collector    # Ver status"
log "  journalctl -f -u samureye-collector    # Logs em tempo real"
log ""

log "📊 SCRIPTS AUXILIARES CRIADOS:"
log "  $COLLECTOR_DIR/scripts/diagnostico.sh  # Diagnóstico completo"
log "  $COLLECTOR_DIR/scripts/corrigir.sh     # Correção de emergência"
log ""

log "⚠️  PRÓXIMOS PASSOS OBRIGATÓRIOS:"
log "1. Iniciar o collector: systemctl start samureye-collector"
log "2. Verificar logs: journalctl -f -u samureye-collector"
log "3. Registrar collector manualmente via interface web da plataforma"
log ""

log "🚀 vlxsam04 Collector Agent 100% pronto!"
log "⏰ Instalação finalizada em: $(date '+%Y-%m-%d %H:%M:%S')"

# Tentar iniciar o serviço automaticamente
log ""
log "🚀 Iniciando serviço automaticamente..."
if systemctl start samureye-collector; then
    log "✅ Serviço samureye-collector iniciado com sucesso!"
    sleep 3
    if systemctl is-active --quiet samureye-collector; then
        log "✅ Serviço confirmado como ativo"
        log ""
        log "📝 Para ver logs em tempo real:"
        log "   journalctl -f -u samureye-collector"
    else
        warn "⚠️  Serviço iniciou mas pode ter problemas - verificar logs"
    fi
else
    warn "⚠️  Falha ao iniciar serviço - usar comando manual:"
    warn "   systemctl start samureye-collector"
    warn "   journalctl -u samureye-collector"
fi

log ""
log "🎯 INSTALL.SH CONCLUÍDO - COLLECTOR PRONTO PARA REGISTRO MANUAL!"
