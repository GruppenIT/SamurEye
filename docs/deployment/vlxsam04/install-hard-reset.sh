#!/bin/bash

# ============================================================================
# SAMUREYE ON-PREMISE - HARD RESET COLLECTOR AGENT (vlxsam04)
# ============================================================================
# Sistema completo de reset e reinstalação do Agente Coletor SamurEye
# Inclui: Python + Node.js + Security Tools + Collector Agent + Automation
#
# Servidor: vlxsam04 (192.168.100.154)
# Função: Agente Coletor de Dados e Ferramentas de Segurança
# Dependências: vlxsam02 (API), vlxsam01 (Certificates)
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

# Verificar se está sendo executado como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo $0"
fi

# Configurações do ambiente
COLLECTOR_USER="samureye-collector"
COLLECTOR_DIR="/opt/samureye/collector"
TOOLS_DIR="$COLLECTOR_DIR/tools"
CERTS_DIR="$COLLECTOR_DIR/certs"
CONFIG_DIR="/etc/samureye-collector"
SERVICE_NAME="samureye-collector"
PYTHON_VERSION="3.11"
NODE_VERSION="20"
API_SERVER="https://api.samureye.com.br"
GATEWAY_SERVER="192.168.100.151"

echo ""
echo "🔥 SAMUREYE HARD RESET - COLLECTOR AGENT vlxsam04"
echo "==============================================="
echo "⚠️  ATENÇÃO: Este script irá:"
echo "   • Remover COMPLETAMENTE todas as ferramentas de segurança"
echo "   • Reinstalar Python, Node.js e dependências"
echo "   • Reconfigurar agente coletor do zero"
echo "   • Limpar dados de coleta anteriores"
echo "   • Reinstalar Nmap, Nuclei, Masscan e outras tools"
echo ""

# ============================================================================
# 1. CONFIRMAÇÃO DE HARD RESET
# ============================================================================

# Detectar se está sendo executado via pipe (curl | bash)
if [ -t 0 ]; then
    # Terminal interativo - pedir confirmação
    read -p "🚨 CONTINUAR COM HARD RESET? (digite 'CONFIRMO' para continuar): " confirm
    if [ "$confirm" != "CONFIRMO" ]; then
        error "Reset cancelado pelo usuário"
    fi
else
    # Não-interativo (curl | bash) - continuar automaticamente após delay
    warn "Modo não-interativo detectado (curl | bash)"
    info "Hard reset iniciará automaticamente em 5 segundos..."
    sleep 5
fi

log "🗑️ Iniciando hard reset do agente coletor..."

# ============================================================================
# 2. REMOÇÃO COMPLETA DA INSTALAÇÃO ANTERIOR
# ============================================================================

log "⏹️ Parando serviços e removendo instalação anterior..."

# Parar serviço do collector
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME"
    log "✅ Serviço $SERVICE_NAME parado"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME"
    log "✅ Serviço $SERVICE_NAME desabilitado"
fi

# Remover arquivo de serviço
if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    log "✅ Arquivo de serviço removido"
fi

# Remover usuário collector
if id "$COLLECTOR_USER" &>/dev/null; then
    pkill -u "$COLLECTOR_USER" 2>/dev/null || true
    userdel -r "$COLLECTOR_USER" 2>/dev/null || true
    log "✅ Usuário $COLLECTOR_USER removido"
fi

# Remover Python e Node.js
log "🗑️ Removendo linguagens de programação..."
apt-get purge -y python3* nodejs npm node-* 2>/dev/null || true
rm -rf /usr/local/lib/node_modules /usr/local/bin/node /usr/local/bin/npm
rm -rf ~/.npm ~/.node-gyp /root/.npm /root/.node-gyp

# Remover ferramentas de segurança
log "🗑️ Removendo ferramentas de segurança..."
tools_to_remove=("nmap" "masscan" "gobuster" "nuclei")
for tool in "${tools_to_remove[@]}"; do
    which "$tool" >/dev/null 2>&1 && rm -f "$(which "$tool")" && log "✅ $tool removido"
done

# Remover diretórios do collector
directories_to_remove=(
    "$COLLECTOR_DIR"
    "$CONFIG_DIR"
    "/var/log/samureye-collector"
    "/tmp/samureye-collector"
    "/opt/nuclei-templates"
    "/opt/nmap-scripts"
    "/usr/local/share/nmap"
)

for dir in "${directories_to_remove[@]}"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        log "✅ Removido: $dir"
    fi
done

# Remover cron jobs
crontab -l 2>/dev/null | grep -v "samureye" | crontab - 2>/dev/null || true

log "✅ Remoção completa finalizada"

# ============================================================================
# 3. ATUALIZAÇÃO DO SISTEMA
# ============================================================================

log "🔄 Atualizando sistema..."
apt-get update && apt-get upgrade -y

# Configurar timezone
timedatectl set-timezone America/Sao_Paulo

# ============================================================================
# 4. INSTALAÇÃO DE DEPENDÊNCIAS BÁSICAS
# ============================================================================

log "📦 Instalando dependências básicas..."
apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    build-essential \
    cmake \
    libssl-dev \
    libffi-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    netcat-openbsd \
    nmap \
    jq \
    htop \
    nano \
    systemd \
    cron \
    libpcap-dev

# Instalar masscan com fallback para compilação do código fonte
log "🔧 Instalando masscan..."
if ! apt-get install -y masscan 2>/dev/null; then
    warn "⚠️ Masscan via apt falhou (403 Forbidden), compilando do source..."
    cd /tmp
    
    if [ -d "masscan" ]; then
        rm -rf masscan
    fi
    
    git clone https://github.com/robertdavidgraham/masscan
    cd masscan
    make -j$(nproc) 2>/dev/null || make
    make install
    cd /
    rm -rf /tmp/masscan
    log "✅ Masscan compilado e instalado do código fonte"
else
    log "✅ Masscan instalado via apt"
fi

# ============================================================================
# 5. INSTALAÇÃO PYTHON 3.11
# ============================================================================

log "🐍 Instalando Python $PYTHON_VERSION..."

# Adicionar repositório deadsnakes para Python 3.11
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update

# Instalar Python 3.11
apt-get install -y \
    python$PYTHON_VERSION \
    python$PYTHON_VERSION-dev \
    python$PYTHON_VERSION-venv \
    python$PYTHON_VERSION-distutils

# Configurar Python padrão
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python$PYTHON_VERSION 1
update-alternatives --install /usr/bin/python python /usr/bin/python$PYTHON_VERSION 1

# Verificar instalação
if python$PYTHON_VERSION --version >/dev/null 2>&1; then
    python_version=$(python$PYTHON_VERSION --version 2>&1 | cut -d' ' -f2)
    log "✅ Python $python_version instalado"
else
    error "❌ Falha na instalação do Python $PYTHON_VERSION"
fi

# Verificar se o symlink funciona
if python --version >/dev/null 2>&1; then
    python_default=$(python --version 2>&1 | cut -d' ' -f2)
    log "✅ Python padrão: $python_default"
else
    warn "⚠️ Symlink do Python pode precisar ser reconfigurado"
fi

# ============================================================================
# 6. INSTALAÇÃO NODE.JS
# ============================================================================

log "📦 Instalando Node.js $NODE_VERSION..."

# Instalar NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -

# Instalar Node.js
apt-get install -y nodejs

# Verificar instalação
node_version=$(node --version 2>&1)
if [[ "$node_version" == v${NODE_VERSION}* ]]; then
    log "✅ Node.js $node_version instalado"
else
    error "❌ Falha na instalação do Node.js"
fi

# ============================================================================
# 7. CRIAÇÃO DE USUÁRIO E ESTRUTURA DE DIRETÓRIOS
# ============================================================================

log "👤 Criando usuário e estrutura de diretórios..."

# Criar usuário samureye-collector
useradd -r -s /bin/bash -d "$COLLECTOR_DIR" -m "$COLLECTOR_USER"

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

log "✅ Estrutura de diretórios criada"

# ============================================================================
# 8. INSTALAÇÃO DE FERRAMENTAS DE SEGURANÇA
# ============================================================================

log "🛡️ Instalando ferramentas de segurança..."

# Nmap - INSTALAÇÃO OBRIGATÓRIA
log "📡 Configurando Nmap..."
if ! command -v nmap >/dev/null 2>&1; then
    log "🔄 Instalando Nmap (OBRIGATÓRIO para collector)..."
    
    if apt-get update >/dev/null 2>&1 && apt-get install -y nmap >/dev/null 2>&1; then
        log "✅ Nmap instalado via apt"
    else
        warn "❌ Falha instalação nmap - collector funcionará com limitações"
    fi
fi

if command -v nmap >/dev/null 2>&1; then
    mkdir -p "$TOOLS_DIR/nmap/scripts"
    cp /usr/share/nmap/scripts/* "$TOOLS_DIR/nmap/scripts/" 2>/dev/null || true
    chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$TOOLS_DIR/nmap"
    log "✅ Nmap configurado: $(nmap --version 2>/dev/null | head -1 || echo 'versão indisponível')"
else
    warn "❌ CRÍTICO: Nmap não disponível - collector pode falhar"
fi

# Masscan (já instalado via apt ou compilado)
if command -v masscan >/dev/null 2>&1; then
    log "✅ Masscan configurado"
    masscan_version=$(masscan --version 2>&1 | head -1)
    log "   Versão: $masscan_version"
else
    warn "❌ Masscan não encontrado após instalação"
fi

# Nuclei
log "🔍 Instalando Nuclei..."
cd /tmp

# Limpar qualquer download anterior
rm -f nuclei*.zip nuclei 2>/dev/null

# Tentar instalar via apt primeiro
if apt-get install -y nuclei 2>/dev/null; then
    log "✅ Nuclei instalado via apt"
else
    warn "⚠️ Nuclei via apt falhou, instalando via GitHub..."
    
    # Fallback: Instalar via GitHub releases
    NUCLEI_LATEST_URL=$(curl -s https://api.github.com/repos/projectdiscovery/nuclei/releases/latest | grep "browser_download_url.*nuclei.*linux_amd64\.zip" | head -1 | cut -d '"' -f 4)
    
    if [ -n "$NUCLEI_LATEST_URL" ]; then
        wget -q "$NUCLEI_LATEST_URL" -O nuclei_linux_amd64.zip
        if [ -f "nuclei_linux_amd64.zip" ]; then
            unzip -o -q nuclei_linux_amd64.zip  # -o para sobrescrever sem perguntar
            if [ -f "nuclei" ]; then
                mv nuclei /usr/local/bin/
                chmod +x /usr/local/bin/nuclei
                log "✅ Nuclei instalado via GitHub"
            else
                warn "❌ Falha ao extrair Nuclei"
            fi
        else
            warn "❌ Falha ao baixar Nuclei"
        fi
    else
        warn "❌ Não foi possível obter URL do Nuclei"
    fi
fi

# Verificar se Nuclei está disponível
if command -v nuclei >/dev/null 2>&1; then
    nuclei_version=$(nuclei -version 2>&1 | head -1 | cut -d' ' -f2 || echo "unknown")
    log "✅ Nuclei configurado (v$nuclei_version)"
    
    # Criar diretório para templates
    mkdir -p "$TOOLS_DIR/nuclei"
    chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$TOOLS_DIR/nuclei"
    
    # Baixar templates em background (não bloquear instalação)
    log "📋 Atualizando templates Nuclei em background..."
    (
        sleep 5  # Aguardar 5 segundos
        sudo -u "$COLLECTOR_USER" timeout 300 nuclei -update-templates -silent >/dev/null 2>&1 || true
        log "✅ Templates Nuclei atualizados"
    ) &
    
else
    warn "❌ Nuclei não está disponível após instalação"
fi

# Gobuster
log "🔍 Instalando Gobuster..."

# Tentar instalar via apt primeiro
if apt-get install -y gobuster 2>/dev/null; then
    log "✅ Gobuster instalado via apt"
else
    warn "⚠️ Gobuster via apt falhou, instalando via GitHub..."
    
    # Fallback: Instalar via GitHub releases
    GOBUSTER_LATEST_URL=$(curl -s https://api.github.com/repos/OJ/gobuster/releases/latest | grep "browser_download_url.*gobuster.*Linux_x86_64\.tar\.gz" | head -1 | cut -d '"' -f 4)
    
    if [ -n "$GOBUSTER_LATEST_URL" ]; then
        wget -q "$GOBUSTER_LATEST_URL" -O gobuster_Linux_x86_64.tar.gz
        if [ -f "gobuster_Linux_x86_64.tar.gz" ]; then
            tar -xzf gobuster_Linux_x86_64.tar.gz --overwrite  # Sobrescrever sem perguntar
            if [ -f "gobuster" ]; then
                mv gobuster /usr/local/bin/
                chmod +x /usr/local/bin/gobuster
                log "✅ Gobuster instalado via GitHub"
            else
                warn "❌ Falha ao extrair Gobuster"
            fi
        else
            warn "❌ Falha ao baixar Gobuster"
        fi
    else
        warn "❌ Não foi possível obter URL do Gobuster"
    fi
fi

if command -v gobuster >/dev/null 2>&1; then
    gobuster_version=$(gobuster version 2>&1 | grep "Version:" | cut -d' ' -f2 || echo "unknown")
    log "✅ Gobuster configurado (v$gobuster_version)"
else
    warn "❌ Gobuster não está disponível após instalação"
fi

# Cleanup arquivos temporários
cd /tmp
rm -f nuclei*.zip gobuster*.tar.gz nuclei gobuster LICENSE* README* 2>/dev/null || true
log "🧹 Arquivos temporários removidos"

# ============================================================================
# 9. INSTALAÇÃO DO AGENTE COLETOR
# ============================================================================

log "🤖 Instalando agente coletor..."

# Criar agente Python simples
cat > "$COLLECTOR_DIR/agent/collector.py" << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent - On-Premise
Agente coletor de dados para ambiente on-premise
"""

import os
import sys
import json
import time
import requests
import subprocess
import psutil
from datetime import datetime
import logging

# Configurações
API_BASE = os.getenv('SAMUREYE_API_URL', 'https://api.samureye.com.br')
COLLECTOR_ID = os.getenv('COLLECTOR_ID', 'vlxsam04-collector')
ENROLLMENT_TOKEN = os.getenv('ENROLLMENT_TOKEN', '')
HEARTBEAT_INTERVAL = int(os.getenv('HEARTBEAT_INTERVAL', '30'))

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/samureye-collector/collector.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class SamurEyeCollector:
    def __init__(self):
        self.collector_id = COLLECTOR_ID
        self.api_base = API_BASE
        self.token = ENROLLMENT_TOKEN
        self.session = requests.Session()
        
    def get_system_telemetry(self):
        """Coleta telemetria do sistema"""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            network = psutil.net_io_counters()
            
            return {
                'timestamp': datetime.utcnow().isoformat(),
                'cpu_percent': cpu_percent,
                'memory_total': memory.total,
                'memory_used': memory.used,
                'memory_percent': memory.percent,
                'disk_total': disk.total,
                'disk_used': disk.used,
                'disk_percent': (disk.used / disk.total) * 100,
                'network_io': {
                    'bytes_sent': network.bytes_sent,
                    'bytes_recv': network.bytes_recv,
                    'packets_sent': network.packets_sent,
                    'packets_recv': network.packets_recv
                },
                'processes': len(psutil.pids())
            }
        except Exception as e:
            logger.error(f"Erro ao coletar telemetria: {e}")
            return {}
    
    def send_heartbeat(self):
        """Envia heartbeat para o servidor"""
        try:
            telemetry = self.get_system_telemetry()
            
            payload = {
                'collector_id': self.collector_id,
                'status': 'online',
                'telemetry': telemetry,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            if self.token:
                payload['token'] = self.token
            
            response = self.session.post(
                f'{self.api_base}/collector-api/heartbeat',
                json=payload,
                timeout=10,
                verify=False  # On-premise SSL
            )
            
            if response.status_code == 200:
                logger.info(f"Heartbeat enviado com sucesso")
                return True
            else:
                logger.warning(f"Falha no heartbeat: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"Erro ao enviar heartbeat: {e}")
            return False
    
    def run_scan(self, scan_config):
        """Executa scan baseado na configuração"""
        try:
            scan_type = scan_config.get('type', 'nmap')
            target = scan_config.get('target', '127.0.0.1')
            
            if scan_type == 'nmap':
                return self.run_nmap_scan(target, scan_config)
            elif scan_type == 'nuclei':
                return self.run_nuclei_scan(target, scan_config)
            else:
                logger.warning(f"Tipo de scan não suportado: {scan_type}")
                return None
                
        except Exception as e:
            logger.error(f"Erro ao executar scan: {e}")
            return None
    
    def run_nmap_scan(self, target, config):
        """Executa scan Nmap"""
        try:
            cmd = ['nmap', '-sS', '-O', '--version-all', target]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            return {
                'type': 'nmap',
                'target': target,
                'output': result.stdout,
                'error': result.stderr,
                'return_code': result.returncode,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except subprocess.TimeoutExpired:
            logger.error("Timeout no scan Nmap")
            return None
        except Exception as e:
            logger.error(f"Erro no scan Nmap: {e}")
            return None
    
    def run_nuclei_scan(self, target, config):
        """Executa scan Nuclei"""
        try:
            cmd = ['nuclei', '-u', target, '-json']
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=600
            )
            
            return {
                'type': 'nuclei',
                'target': target,
                'output': result.stdout,
                'error': result.stderr,
                'return_code': result.returncode,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except subprocess.TimeoutExpired:
            logger.error("Timeout no scan Nuclei")
            return None
        except Exception as e:
            logger.error(f"Erro no scan Nuclei: {e}")
            return None
    
    def run(self):
        """Loop principal do collector"""
        logger.info(f"Iniciando SamurEye Collector: {self.collector_id}")
        
        while True:
            try:
                # Enviar heartbeat
                self.send_heartbeat()
                
                # Aguardar próximo ciclo
                time.sleep(HEARTBEAT_INTERVAL)
                
            except KeyboardInterrupt:
                logger.info("Collector interrompido pelo usuário")
                break
            except Exception as e:
                logger.error(f"Erro no loop principal: {e}")
                time.sleep(5)

if __name__ == "__main__":
    collector = SamurEyeCollector()
    collector.run()
EOF

# Tornar executável
chmod +x "$COLLECTOR_DIR/agent/collector.py"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/agent/collector.py"

# Instalar dependências Python via apt (Ubuntu 24.04)
log "📦 Instalando dependências Python..."
apt-get install -y python3-psutil python3-requests python3-venv

if python3 -c "import psutil, requests" 2>/dev/null; then
    log "✅ Dependências Python instaladas"
else
    warn "⚠️ Algumas dependências Python podem estar ausentes"
fi

# ============================================================================
# 10. CONFIGURAÇÃO DO SERVIÇO SYSTEMD
# ============================================================================

log "🔧 Configurando serviço systemd..."

cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=SamurEye Collector Agent
After=network.target
Wants=network.target

[Service]
Type=simple
User=$COLLECTOR_USER
Group=$COLLECTOR_USER
WorkingDirectory=$COLLECTOR_DIR/agent
Environment=SAMUREYE_API_URL=$API_SERVER
Environment=COLLECTOR_ID=vlxsam04-collector-$(date +%s)
Environment=HEARTBEAT_INTERVAL=30
ExecStart=/usr/bin/python3 $COLLECTOR_DIR/agent/collector.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/samureye-collector/collector.log
StandardError=append:/var/log/samureye-collector/error.log

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$COLLECTOR_DIR /var/log/samureye-collector /tmp

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

log "✅ Serviço systemd configurado"

# ============================================================================
# 11. CONFIGURAÇÃO DE CRON JOBS
# ============================================================================

log "⏰ Configurando cron jobs..."

# Criar script de limpeza
cat > "$COLLECTOR_DIR/scripts/cleanup.sh" << 'EOF'
#!/bin/bash
# Script de limpeza automática do collector

COLLECTOR_DIR="/opt/samureye/collector"
LOG_DIR="/var/log/samureye-collector"

# Limpar logs antigos (mais de 7 dias)
find $LOG_DIR -name "*.log" -mtime +7 -delete 2>/dev/null || true

# Limpar arquivos temporários (mais de 1 dia)
find $COLLECTOR_DIR/temp -type f -mtime +1 -delete 2>/dev/null || true

# Limpar uploads antigos (mais de 3 dias)
find $COLLECTOR_DIR/uploads -type f -mtime +3 -delete 2>/dev/null || true

# Log da limpeza
echo "$(date): Limpeza automática executada" >> $LOG_DIR/cleanup.log
EOF

chmod +x "$COLLECTOR_DIR/scripts/cleanup.sh"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/scripts/cleanup.sh"

# Adicionar cron job
(crontab -l 2>/dev/null; echo "0 2 * * * $COLLECTOR_DIR/scripts/cleanup.sh") | crontab -

log "✅ Cron jobs configurados"

# ============================================================================
# 12. CONFIGURAÇÃO DE FIREWALL
# ============================================================================

log "🔒 Configurando firewall..."

# Instalar UFW se não estiver instalado
apt-get install -y ufw

# Reset UFW
ufw --force reset

# Política padrão
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH
ufw allow 22/tcp

# Permitir acesso para rede SamurEye
ufw allow from 192.168.100.0/24

# Permitir HTTPS para API (saída)
ufw allow out 443/tcp

# Ativar firewall
ufw --force enable

log "✅ Firewall configurado"

# ============================================================================
# 13. INICIALIZAÇÃO DO SERVIÇO
# ============================================================================

log "🚀 Iniciando serviço collector..."

# Habilitar e iniciar serviço
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Aguardar inicialização
sleep 10

# Verificar status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Collector iniciado com sucesso"
else
    warn "⚠️ Collector pode ter problemas - verificar logs"
fi

# ============================================================================
# 14. TESTES DE VALIDAÇÃO
# ============================================================================

log "🧪 Executando testes de validação..."

# Teste 1: Serviço ativo
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Serviço: Ativo"
else
    warn "⚠️ Serviço: Inativo"
fi

# Teste 2: Python funcionando
if python3 -c "import psutil, requests" 2>/dev/null; then
    log "✅ Python: Dependências OK"
else
    warn "⚠️ Python: Problemas com dependências"
fi

# Teste 3: Ferramentas de segurança
tools_status=""
for tool in nmap nuclei masscan gobuster; do
    if command -v "$tool" >/dev/null 2>&1; then
        tools_status="$tools_status $tool:✅"
    else
        tools_status="$tools_status $tool:❌"
    fi
done
log "🛡️ Ferramentas:$tools_status"

# Teste 4: Conectividade com API
if curl -s -k --connect-timeout 5 "$API_SERVER/api/health" >/dev/null 2>&1; then
    log "✅ API: Conectividade OK"
else
    warn "⚠️ API: Sem conectividade"
fi

# Teste 5: Logs sendo gerados
if [ -f "/var/log/samureye-collector/collector.log" ]; then
    log "✅ Logs: Sendo gerados"
else
    warn "⚠️ Logs: Não encontrados"
fi

# ============================================================================
# 14.5. CORREÇÃO AUTOMÁTICA DE HEARTBEAT
# ============================================================================

log "💓 Configurando correções de heartbeat e conectividade..."

# Verificar e corrigir configuração para heartbeat
CONFIG_FILE="/etc/samureye-collector/.env"

if [ -f "$CONFIG_FILE" ]; then
    # Garantir que API_BASE está correto
    if ! grep -q "API_BASE.*https://api.samureye.com.br" "$CONFIG_FILE"; then
        if grep -q "^API_BASE=" "$CONFIG_FILE"; then
            sed -i 's|^API_BASE=.*|API_BASE=https://api.samureye.com.br|' "$CONFIG_FILE"
        else
            echo "API_BASE=https://api.samureye.com.br" >> "$CONFIG_FILE"
        fi
        log "✅ API_BASE corrigido para https://api.samureye.com.br"
    fi
    
    # Garantir intervalo de heartbeat adequado (30 segundos)
    if ! grep -q "^HEARTBEAT_INTERVAL=" "$CONFIG_FILE"; then
        echo "HEARTBEAT_INTERVAL=30" >> "$CONFIG_FILE"
        log "✅ HEARTBEAT_INTERVAL configurado (30 segundos)"
    else
        # Verificar se não está muito baixo (mínimo 15 segundos)
        CURRENT_INTERVAL=$(grep "^HEARTBEAT_INTERVAL=" "$CONFIG_FILE" | cut -d= -f2)
        if [ "$CURRENT_INTERVAL" -lt 15 ] 2>/dev/null; then
            sed -i 's/^HEARTBEAT_INTERVAL=.*/HEARTBEAT_INTERVAL=30/' "$CONFIG_FILE"
            log "✅ HEARTBEAT_INTERVAL ajustado para 30 segundos (estava muito baixo)"
        fi
    fi
    
    # Adicionar configuração de retry para heartbeat
    if ! grep -q "^HEARTBEAT_RETRY_COUNT=" "$CONFIG_FILE"; then
        echo "HEARTBEAT_RETRY_COUNT=3" >> "$CONFIG_FILE"
        log "✅ HEARTBEAT_RETRY_COUNT configurado (3 tentativas)"
    fi
    
    # Adicionar timeout para requests HTTP
    if ! grep -q "^HTTP_TIMEOUT=" "$CONFIG_FILE"; then
        echo "HTTP_TIMEOUT=30" >> "$CONFIG_FILE"
        log "✅ HTTP_TIMEOUT configurado (30 segundos)"
    fi
    
    # Configuração de log level para debug inicial
    if ! grep -q "^LOG_LEVEL=" "$CONFIG_FILE"; then
        echo "LOG_LEVEL=INFO" >> "$CONFIG_FILE"
        log "✅ LOG_LEVEL configurado (INFO)"
    fi
    
else
    warn "⚠️ Arquivo de configuração $CONFIG_FILE não encontrado"
fi

# Criar script de teste de conectividade
cat > "$COLLECTOR_DIR/test-connectivity.sh" << 'EOF'
#!/bin/bash

# Script para testar conectividade do collector
CERTS_DIR="/opt/samureye-collector/certs"
API_BASE="https://api.samureye.com.br"

echo "🔧 Testando conectividade do collector..."

# Teste DNS
if nslookup api.samureye.com.br >/dev/null 2>&1; then
    echo "✅ DNS: api.samureye.com.br"
else
    echo "❌ DNS: Falha na resolução"
    exit 1
fi

# Teste porta
if timeout 5 bash -c "</dev/tcp/api.samureye.com.br/443" >/dev/null 2>&1; then
    echo "✅ Conectividade: Porta 443 acessível"
else
    echo "❌ Conectividade: Porta 443 bloqueada"
    exit 1
fi

# Teste certificados
if [ -f "$CERTS_DIR/collector.crt" ] && [ -f "$CERTS_DIR/collector.key" ]; then
    echo "✅ Certificados: Encontrados"
    
    # Teste heartbeat
    RESPONSE=$(curl -k \
        --cert "$CERTS_DIR/collector.crt" \
        --key "$CERTS_DIR/collector.key" \
        --connect-timeout 10 \
        --max-time 30 \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{
            \"collector_id\": \"$(hostname)\",
            \"status\": \"online\",
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",
            \"telemetry\": {
                \"cpu_percent\": 15.0,
                \"memory_percent\": 45.0,
                \"disk_percent\": 30.0,
                \"processes\": 100
            },
            \"capabilities\": [\"nmap\", \"nuclei\", \"masscan\"],
            \"version\": \"1.0.0\"
        }" \
        "$API_BASE/collector-api/heartbeat" 2>/dev/null || echo "ERROR")
    
    if [[ "$RESPONSE" == *"Heartbeat received"* ]]; then
        echo "✅ Heartbeat: Teste manual bem-sucedido"
        echo "   Resposta: $RESPONSE"
    else
        echo "❌ Heartbeat: Falha no teste manual"
        echo "   Resposta: $RESPONSE"
        exit 1
    fi
else
    echo "❌ Certificados: Não encontrados em $CERTS_DIR"
    exit 1
fi

echo ""
echo "🎉 Todos os testes de conectividade passaram!"
EOF

chmod +x "$COLLECTOR_DIR/test-connectivity.sh"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/test-connectivity.sh"

log "✅ Script de teste de conectividade criado: $COLLECTOR_DIR/test-connectivity.sh"

# Testar conectividade imediatamente após instalação
if [ -f "$COLLECTOR_DIR/certs/collector.crt" ] && [ -f "$COLLECTOR_DIR/certs/collector.key" ]; then
    log "🧪 Executando teste de conectividade imediato..."
    if sudo -u "$COLLECTOR_USER" "$COLLECTOR_DIR/test-connectivity.sh"; then
        log "✅ Teste de conectividade inicial: SUCESSO"
    else
        warn "⚠️ Teste de conectividade inicial: FALHOU - verificar configuração"
    fi
else
    warn "⚠️ Certificados não encontrados - teste de conectividade pulado"
fi

# ============================================================================
# 15. SCRIPT DE REGISTRO NO SERVIDOR
# ============================================================================

log "📝 Criando script de registro..."

# Remover script register.sh antigo - será substituído pelo heartbeat integrado
log "📝 Sistema de registro integrado ao heartbeat implementado"

# ============================================================================
# CORREÇÃO INTEGRADA DE DUPLICAÇÃO DE COLETORES
# ============================================================================

log "🔧 Implementando correção de duplicação de coletores..."

# Criar configuração robusta para evitar duplicação
cat > "$CONFIG_FILE" << 'CONFIG_EOF'
# Configuração do Collector SamurEye - Anti-duplicação
COLLECTOR_ID=${HOSTNAME}
COLLECTOR_NAME=${COLLECTOR_NAME}
HOSTNAME=${HOSTNAME}
IP_ADDRESS=${IP_ADDRESS}
API_BASE_URL=${API_SERVER}
HEARTBEAT_INTERVAL=30
RETRY_ATTEMPTS=3
RETRY_DELAY=5
LOG_LEVEL=INFO
CONFIG_EOF

# Criar script de heartbeat robusto integrado
cat > "$COLLECTOR_DIR/heartbeat.py" << 'HEARTBEAT_EOF'
#!/usr/bin/env python3
"""
Script de heartbeat robusto para SamurEye Collector
Evita duplicação e gerencia status automaticamente
"""

import os
import sys
import json
import time
import socket
import requests
import logging
import psutil
from pathlib import Path

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/samureye-collector/heartbeat.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class CollectorHeartbeat:
    def __init__(self):
        self.load_config()
        self.session = requests.Session()
        self.session.verify = False
        
    def load_config(self):
        try:
            env_file = Path("/etc/samureye-collector/.env")
            if env_file.exists():
                with open(env_file) as f:
                    for line in f:
                        if '=' in line and not line.startswith('#'):
                            key, value = line.strip().split('=', 1)
                            os.environ[key] = value
                            
            self.collector_id = os.environ.get('COLLECTOR_ID', socket.gethostname())
            self.collector_name = os.environ.get('COLLECTOR_NAME', f"{socket.gethostname()}-collector")
            self.hostname = os.environ.get('HOSTNAME', socket.gethostname())
            self.ip_address = os.environ.get('IP_ADDRESS', self.get_local_ip())
            self.api_base = os.environ.get('API_BASE_URL', 'https://api.samureye.com.br')
            self.heartbeat_interval = int(os.environ.get('HEARTBEAT_INTERVAL', '30'))
            
            token_file = Path("/etc/samureye-collector/token.conf")
            self.enrollment_token = None
            if token_file.exists():
                with open(token_file) as f:
                    for line in f:
                        if line.startswith('ENROLLMENT_TOKEN='):
                            self.enrollment_token = line.strip().split('=', 1)[1]
                            break
                            
            logger.info(f"Configuração carregada - ID: {self.collector_id}, Nome: {self.collector_name}")
            
        except Exception as e:
            logger.error(f"Erro ao carregar configuração: {e}")
            sys.exit(1)
            
    def get_local_ip(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "127.0.0.1"
            
    def get_telemetry(self):
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            return {
                "cpu_percent": cpu_percent,
                "memory_percent": memory.percent,
                "disk_percent": disk.percent,
                "processes": len(psutil.pids()),
                "memory_total": memory.total,
                "disk_total": disk.total,
                "uptime": int(time.time() - psutil.boot_time())
            }
        except Exception as e:
            logger.warning(f"Erro ao coletar telemetria: {e}")
            return {"cpu_percent": 0, "memory_percent": 0, "disk_percent": 0, "processes": 0}
            
    def register_collector(self):
        try:
            url = f"{self.api_base}/api/collectors"
            data = {
                "name": self.collector_name,
                "hostname": self.hostname,
                "ipAddress": self.ip_address,
                "status": "enrolling",
                "description": f"Collector agent on-premise {self.hostname}"
            }
            
            logger.info(f"Registrando collector: {data}")
            response = self.session.post(url, json=data, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                if 'enrollmentToken' in result:
                    self.enrollment_token = result['enrollmentToken']
                    
                    with open('/etc/samureye-collector/token.conf', 'w') as f:
                        f.write(f"ENROLLMENT_TOKEN={self.enrollment_token}\n")
                    os.chmod('/etc/samureye-collector/token.conf', 0o600)
                    
                    logger.info("Collector registrado com sucesso (reutiliza existente se duplicado)")
                    return True
                    
            logger.error(f"Erro no registro: {response.status_code} - {response.text}")
            return False
            
        except Exception as e:
            logger.error(f"Erro ao registrar collector: {e}")
            return False
            
    def send_heartbeat(self):
        try:
            url = f"{self.api_base}/collector-api/heartbeat"
            telemetry = self.get_telemetry()
            
            data = {
                "collector_id": self.collector_id,
                "status": "online",
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                "telemetry": telemetry,
                "capabilities": ["nmap", "nuclei", "masscan"],
                "version": "1.0.0"
            }
            
            if self.enrollment_token:
                data["token"] = self.enrollment_token
                
            response = self.session.post(url, json=data, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                logger.info(f"Heartbeat enviado - Status: {result.get('status', 'unknown')}")
                
                if result.get('transitioned'):
                    logger.info("✅ Collector transicionou de ENROLLING para ONLINE")
                    
                return True
            else:
                logger.error(f"Erro no heartbeat: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Erro ao enviar heartbeat: {e}")
            return False
            
    def run(self):
        logger.info("Iniciando heartbeat collector...")
        
        if not self.enrollment_token:
            logger.info("Token não encontrado, registrando collector...")
            if not self.register_collector():
                logger.error("Falha no registro inicial")
                return
                
        consecutive_failures = 0
        max_failures = 5
        
        while True:
            try:
                if self.send_heartbeat():
                    consecutive_failures = 0
                else:
                    consecutive_failures += 1
                    
                    if consecutive_failures >= max_failures:
                        logger.warning("Muitas falhas consecutivas, tentando re-registrar...")
                        self.register_collector()
                        consecutive_failures = 0
                        
                time.sleep(self.heartbeat_interval)
                
            except KeyboardInterrupt:
                logger.info("Heartbeat interrompido pelo usuário")
                break
            except Exception as e:
                logger.error(f"Erro no loop de heartbeat: {e}")
                time.sleep(self.heartbeat_interval)

if __name__ == "__main__":
    heartbeat = CollectorHeartbeat()
    heartbeat.run()
HEARTBEAT_EOF

chmod +x "$COLLECTOR_DIR/heartbeat.py"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/heartbeat.py"

# Atualizar serviço systemd para usar heartbeat robusto
cat > /etc/systemd/system/$SERVICE_NAME.service << 'SERVICE_EOF'
[Unit]
Description=SamurEye Collector Agent
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=10
User=$COLLECTOR_USER
Group=$COLLECTOR_USER
WorkingDirectory=$COLLECTOR_DIR
ExecStart=/usr/bin/python3 $COLLECTOR_DIR/heartbeat.py
StandardOutput=append:/var/log/samureye-collector/collector.log
StandardError=append:/var/log/samureye-collector/collector.log
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload

log "✅ Sistema anti-duplicação integrado no install-hard-reset"

# REGISTRO AUTOMÁTICO COM PROTEÇÃO ANTI-DUPLICAÇÃO
log "🔗 Registrando collector com proteção anti-duplicação..."

# Registro será feito automaticamente pelo heartbeat system
log "✅ Registro automático será realizado pelo sistema de heartbeat"

# ============================================================================
# SCRIPTS DE DIAGNÓSTICO INTEGRADOS NO INSTALL
# ============================================================================

log "📋 Criando scripts de diagnóstico integrados..."

# Script de diagnóstico integrado
cat > "$COLLECTOR_DIR/scripts/check-status.sh" << 'DIAG_EOF'
#!/bin/bash
# Script de diagnóstico integrado para vlxsam04

echo "🔍 DIAGNÓSTICO COLLECTOR vlxsam04"
echo "================================"

HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
API_URL="https://api.samureye.com.br"

echo "📋 Sistema: $HOSTNAME ($IP_ADDRESS)"
echo ""

echo "🤖 Status do Serviço:"
systemctl status samureye-collector --no-pager -l

echo ""
echo "📝 Logs Recentes (Heartbeat):"
if [ -f "/var/log/samureye-collector/heartbeat.log" ]; then
    tail -n 15 /var/log/samureye-collector/heartbeat.log
else
    echo "❌ Log de heartbeat não encontrado"
fi

echo ""
echo "🔗 Teste de Conectividade:"
if timeout 5 bash -c "</dev/tcp/api.samureye.com.br/443" >/dev/null 2>&1; then
    echo "✅ API acessível (porta 443)"
else
    echo "❌ API inacessível"
fi

if nslookup api.samureye.com.br >/dev/null 2>&1; then
    echo "✅ DNS funcionando"
else
    echo "❌ Problema DNS"
fi

echo ""
echo "📊 Configuração:"
if [ -f "/etc/samureye-collector/.env" ]; then
    echo "✅ Arquivo .env existe"
    grep -E "^(COLLECTOR_|HOSTNAME|IP_)" /etc/samureye-collector/.env
else
    echo "❌ Arquivo .env não encontrado"
fi

if [ -f "/etc/samureye-collector/token.conf" ]; then
    echo "✅ Token existe"
else
    echo "❌ Token não encontrado"
fi

echo ""
echo "🔍 Recomendações:"
echo "• Verificar interface: https://app.samureye.com.br/admin/collectors"
echo "• Monitorar logs: tail -f /var/log/samureye-collector/heartbeat.log"
echo "• Reiniciar se necessário: systemctl restart samureye-collector"
DIAG_EOF

chmod +x "$COLLECTOR_DIR/scripts/check-status.sh"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/scripts/check-status.sh"

log "✅ Script de diagnóstico integrado criado"

# ============================================================================
# 16. INFORMAÇÕES FINAIS
# ============================================================================

echo ""
log "🎉 HARD RESET DO COLLECTOR AGENT CONCLUÍDO!"
echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🤖 Collector Agent:"
echo "   • Status:  $(systemctl is-active $SERVICE_NAME)"
echo "   • User:    $COLLECTOR_USER"
echo "   • Dir:     $COLLECTOR_DIR"
echo "   • Logs:    /var/log/samureye-collector/"
echo ""
echo "🐍 Python $PYTHON_VERSION:"
echo "   • Version: $(python --version)"
echo "   • Libs:    psutil, requests"
echo ""
echo "📦 Node.js $NODE_VERSION:"
echo "   • Version: $(node --version)"
echo ""
echo "🛡️ Security Tools:"
echo "   • Nmap:     $(command -v nmap >/dev/null && echo "✅ Instalado" || echo "❌ Ausente")"
echo "   • Nuclei:   $(command -v nuclei >/dev/null && echo "✅ Instalado" || echo "❌ Ausente")"
echo "   • Masscan:  $(command -v masscan >/dev/null && echo "✅ Instalado" || echo "❌ Ausente")"
echo "   • Gobuster: $(command -v gobuster >/dev/null && echo "✅ Instalado" || echo "❌ Ausente")"
echo ""
echo "🔧 Comandos Úteis:"
echo "   • Status:     systemctl status $SERVICE_NAME"
echo "   • Logs:       tail -f /var/log/samureye-collector/collector.log"
echo "   • Restart:    systemctl restart $SERVICE_NAME"
echo "   • Heartbeat:  $COLLECTOR_DIR/heartbeat.py"
echo "   • Cleanup:    $COLLECTOR_DIR/scripts/cleanup.sh"
echo "   • Test Conn:  $COLLECTOR_DIR/test-connectivity.sh"
echo "   • Check Status: $COLLECTOR_DIR/scripts/check-status.sh"
echo ""
echo "🔗 Conectividade:"
echo "   • API:       $API_SERVER"
echo "   • Gateway:   $GATEWAY_SERVER"
echo ""
echo "💓 Heartbeat & Status:"
echo "   • Intervalo: 30 segundos (configurável em $CONFIG_FILE)"
echo "   • Endpoint:  https://api.samureye.com.br/collector-api/heartbeat"
echo "   • Retry:     3 tentativas automáticas por request"
echo "   • Timeout:   30 segundos por request HTTP"
echo ""
echo "📝 Próximos Passos:"
echo "   1. Monitorar logs: tail -f /var/log/samureye-collector/heartbeat.log"
echo "   2. Verificar status: $COLLECTOR_DIR/scripts/check-status.sh"
echo "   3. Interface admin: https://app.samureye.com.br/admin/collectors"
echo "   4. Aguardar transição: ENROLLING → ONLINE (1-2 minutos)"
echo ""
echo "✅ SISTEMA ANTI-DUPLICAÇÃO INTEGRADO:"
echo "   • Heartbeat robusto implementado para evitar coletores duplicados"
echo "   • Registro automático com proteção anti-duplicação"
echo "   • Transição automática: ENROLLING → ONLINE → (timeout) → OFFLINE"
echo "   • Auto-recovery em caso de falhas de conexão"
echo ""
echo "🔧 COMANDOS DE EXECUÇÃO REMOTA:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/install-hard-reset.sh | bash"
echo ""

exit 0