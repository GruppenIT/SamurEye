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
    python$PYTHON_VERSION-distutils \
    python3-pip

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

# Nmap (já instalado via apt, configurar scripts)
log "📡 Configurando Nmap..."
if command -v nmap >/dev/null 2>&1; then
    mkdir -p "$TOOLS_DIR/nmap/scripts"
    cp /usr/share/nmap/scripts/* "$TOOLS_DIR/nmap/scripts/" 2>/dev/null || true
    chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$TOOLS_DIR/nmap"
    log "✅ Nmap configurado"
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
wget -q https://github.com/projectdiscovery/nuclei/releases/latest/download/nuclei_3.3.6_linux_amd64.zip
unzip -q nuclei_3.3.6_linux_amd64.zip
mv nuclei /usr/local/bin/
chmod +x /usr/local/bin/nuclei

# Nuclei templates
sudo -u "$COLLECTOR_USER" nuclei -update-templates -silent
mkdir -p "$TOOLS_DIR/nuclei"
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$TOOLS_DIR/nuclei"

if command -v nuclei >/dev/null 2>&1; then
    log "✅ Nuclei instalado"
fi

# Gobuster
log "🔍 Instalando Gobuster..."
wget -q https://github.com/OJ/gobuster/releases/latest/download/gobuster_Linux_x86_64.tar.gz
tar -xzf gobuster_Linux_x86_64.tar.gz
mv gobuster /usr/local/bin/
chmod +x /usr/local/bin/gobuster

if command -v gobuster >/dev/null 2>&1; then
    log "✅ Gobuster instalado"
fi

# Cleanup
rm -f /tmp/*.zip /tmp/*.tar.gz

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

# Instalar dependências Python
pip3 install psutil requests

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
# 15. SCRIPT DE REGISTRO NO SERVIDOR
# ============================================================================

log "📝 Criando script de registro..."

cat > "$COLLECTOR_DIR/scripts/register.sh" << 'EOF'
#!/bin/bash
# Script para registrar collector no servidor SamurEye

API_URL="https://api.samureye.com.br"
COLLECTOR_NAME="vlxsam04-collector"
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo "🔗 Registrando collector no servidor SamurEye..."

# Registrar collector via API
response=$(curl -s -k -X POST "$API_URL/api/collectors" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$COLLECTOR_NAME\",
        \"hostname\": \"$HOSTNAME\",
        \"ipAddress\": \"$IP_ADDRESS\",
        \"status\": \"enrolling\",
        \"description\": \"Collector agent on-premise vlxsam04\"
    }")

if echo "$response" | grep -q "enrollmentToken"; then
    token=$(echo "$response" | jq -r '.enrollmentToken' 2>/dev/null)
    if [ "$token" != "null" ] && [ -n "$token" ]; then
        echo "✅ Collector registrado com sucesso!"
        echo "Token: $token"
        
        # Salvar token no arquivo de configuração
        echo "ENROLLMENT_TOKEN=$token" > /etc/samureye-collector/token.conf
        chmod 600 /etc/samureye-collector/token.conf
        
        echo "Token salvo em: /etc/samureye-collector/token.conf"
        echo "Para aplicar: systemctl restart samureye-collector"
    else
        echo "❌ Erro: Token não recebido"
    fi
else
    echo "❌ Erro no registro:"
    echo "$response"
fi
EOF

chmod +x "$COLLECTOR_DIR/scripts/register.sh"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/scripts/register.sh"

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
echo "   • Status:    systemctl status $SERVICE_NAME"
echo "   • Logs:      tail -f /var/log/samureye-collector/collector.log"
echo "   • Restart:   systemctl restart $SERVICE_NAME"
echo "   • Register:  $COLLECTOR_DIR/scripts/register.sh"
echo "   • Cleanup:   $COLLECTOR_DIR/scripts/cleanup.sh"
echo ""
echo "🔗 Conectividade:"
echo "   • API:       $API_SERVER"
echo "   • Gateway:   $GATEWAY_SERVER"
echo ""
echo "📝 Próximos Passos:"
echo "   1. Registrar collector: $COLLECTOR_DIR/scripts/register.sh"
echo "   2. Verificar logs: tail -f /var/log/samureye-collector/collector.log"
echo "   3. Testar scans: Usar interface web SamurEye"
echo "   4. Monitorar status: systemctl status $SERVICE_NAME"
echo ""
echo "⚠️ IMPORTANTE:"
echo "   • Collector configurado para enviar heartbeat a cada 30s"
echo "   • Limpeza automática configurada para 02:00 diário"
echo "   • Firewall configurado para acesso apenas rede interna"
echo "   • Use o script register.sh para conectar ao servidor"
echo ""

exit 0