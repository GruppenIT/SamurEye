#!/bin/bash

# SamurEye Collector - Script de Instalação e Registro Unificado
# Uso: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/install-collector.sh | sudo bash -s -- --tenant-slug="empresa-x" --collector-name="servidor-01" --server-url="https://app.samureye.com.br"

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

# Parâmetros padrão
TENANT_SLUG=""
COLLECTOR_NAME=""
SERVER_URL="https://app.samureye.com.br"
INSTALL_DIR="/opt/samureye-collector"
SERVICE_USER="samureye"

# Parse argumentos
while [[ $# -gt 0 ]]; do
  case $1 in
    --tenant-slug=*)
      TENANT_SLUG="${1#*=}"
      shift
      ;;
    --collector-name=*)
      COLLECTOR_NAME="${1#*=}"
      shift
      ;;
    --server-url=*)
      SERVER_URL="${1#*=}"
      shift
      ;;
    *)
      error "Parâmetro desconhecido: $1"
      ;;
  esac
done

# Validar parâmetros obrigatórios
if [ -z "$TENANT_SLUG" ] || [ -z "$COLLECTOR_NAME" ]; then
    error "Parâmetros obrigatórios: --tenant-slug e --collector-name"
fi

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo $0"
fi

clear
echo "🔥 SAMUREYE COLLECTOR - INSTALAÇÃO AUTOMÁTICA"
echo "==============================================="
echo "Tenant: $TENANT_SLUG"
echo "Collector: $COLLECTOR_NAME"
echo "Server: $SERVER_URL"
echo "==============================================="
echo ""

# ============================================================================
# 1. DETECÇÃO DO SISTEMA
# ============================================================================

info "Detectando sistema operacional..."
if ! command -v lsb_release >/dev/null 2>&1; then
    error "Sistema não suportado. Requer Ubuntu/Debian com lsb_release"
fi

OS_ID=$(lsb_release -si)
OS_VERSION=$(lsb_release -sr)

if [[ "$OS_ID" != "Ubuntu" ]] && [[ "$OS_ID" != "Debian" ]]; then
    error "Sistema operacional não suportado: $OS_ID. Requer Ubuntu ou Debian"
fi

log "Sistema detectado: $OS_ID $OS_VERSION"

# ============================================================================
# 2. INSTALAÇÃO DE DEPENDÊNCIAS
# ============================================================================

log "Atualizando sistema e instalando dependências..."
apt-get update -q
apt-get install -y curl python3 python3-pip python3-venv jq systemd wget gnupg2 \
                   software-properties-common apt-transport-https ca-certificates

# Instalar ferramentas de segurança
log "Instalando ferramentas de segurança..."

# Nmap
if ! command -v nmap >/dev/null 2>&1; then
    apt-get install -y nmap
    log "✅ Nmap instalado"
else
    log "✅ Nmap já instalado"
fi

# Nuclei
NUCLEI_VERSION="3.1.2"
if ! command -v nuclei >/dev/null 2>&1; then
    wget -q "https://github.com/projectdiscovery/nuclei/releases/download/v${NUCLEI_VERSION}/nuclei_${NUCLEI_VERSION}_linux_amd64.zip" -O /tmp/nuclei.zip
    cd /tmp && unzip -q nuclei.zip && chmod +x nuclei
    mv nuclei /usr/local/bin/
    rm -f nuclei.zip LICENSE.md README.md
    log "✅ Nuclei v${NUCLEI_VERSION} instalado"
else
    log "✅ Nuclei já instalado"
fi

# Atualizar templates do Nuclei
log "Atualizando templates do Nuclei..."
nuclei -update-templates -silent 2>/dev/null || warn "Falha ao atualizar templates do Nuclei"

# ============================================================================
# 3. CRIAR USUÁRIO E DIRETÓRIOS
# ============================================================================

log "Configurando usuário e diretórios..."

# Criar usuário do serviço
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd -r -s /bin/false -m -d "/home/$SERVICE_USER" "$SERVICE_USER"
    log "✅ Usuário $SERVICE_USER criado"
else
    log "✅ Usuário $SERVICE_USER já existe"
fi

# Criar diretórios
mkdir -p "$INSTALL_DIR"
mkdir -p "/var/log/samureye"
mkdir -p "/etc/samureye"

# ============================================================================
# 4. BAIXAR E INSTALAR COLLECTOR AGENT
# ============================================================================

log "Baixando SamurEye Collector Agent..."

# Criar ambiente virtual Python
python3 -m venv "$INSTALL_DIR/venv"
source "$INSTALL_DIR/venv/bin/activate"

# Instalar dependências Python
pip install --upgrade pip
pip install requests psutil schedule pycryptodome

# Baixar o agente collector
cat > "$INSTALL_DIR/collector_agent.py" << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent
Sends system telemetry and executes security scans
"""

import json
import time
import requests
import psutil
import subprocess
import logging
import schedule
import os
import sys
from datetime import datetime
from threading import Thread

class SamurEyeCollector:
    def __init__(self, config_file='/etc/samureye/collector.conf'):
        self.config_file = config_file
        self.config = self.load_config()
        self.setup_logging()
        
    def load_config(self):
        """Load collector configuration"""
        try:
            with open(self.config_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logging.error(f"Configuration file not found: {self.config_file}")
            sys.exit(1)
        except json.JSONDecodeError:
            logging.error(f"Invalid JSON in configuration file: {self.config_file}")
            sys.exit(1)
    
    def setup_logging(self):
        """Configure logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/samureye/collector.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('samureye-collector')
    
    def get_system_info(self):
        """Collect system telemetry"""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            
            # Memory usage
            memory = psutil.virtual_memory()
            memory_percent = memory.percent
            
            # Disk usage
            disk = psutil.disk_usage('/')
            disk_percent = (disk.used / disk.total) * 100
            
            # Network I/O
            network = psutil.net_io_counters()
            
            # Process count
            process_count = len(psutil.pids())
            
            return {
                'cpu_percent': cpu_percent,
                'memory_percent': memory_percent,
                'disk_percent': disk_percent,
                'network_io': {
                    'bytes_sent': network.bytes_sent,
                    'bytes_recv': network.bytes_recv
                },
                'processes': process_count,
                'timestamp': datetime.utcnow().isoformat(),
            }
        except Exception as e:
            self.logger.error(f"Error collecting system info: {e}")
            return None
    
    def send_heartbeat(self):
        """Send heartbeat with telemetry to server"""
        try:
            telemetry = self.get_system_info()
            
            payload = {
                'collector_id': self.config['collector_name'],
                'status': 'active',
                'telemetry': telemetry,
                'timestamp': datetime.utcnow().isoformat(),
                'version': '1.0.0'
            }
            
            url = f"{self.config['server_url']}/collector-api/heartbeat"
            
            response = requests.post(url, json=payload, timeout=30)
            response.raise_for_status()
            
            self.logger.info("Heartbeat sent successfully")
            
        except Exception as e:
            self.logger.error(f"Failed to send heartbeat: {e}")
    
    def run_scan(self, scan_type, target):
        """Execute security scan"""
        try:
            if scan_type == 'nmap':
                cmd = ['nmap', '-sS', '-O', target]
            elif scan_type == 'nuclei':
                cmd = ['nuclei', '-t', '/root/nuclei-templates/', '-target', target]
            else:
                raise ValueError(f"Unknown scan type: {scan_type}")
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            
            return {
                'scan_type': scan_type,
                'target': target,
                'exit_code': result.returncode,
                'stdout': result.stdout,
                'stderr': result.stderr,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            self.logger.error(f"Scan failed: {e}")
            return None
    
    def start_scheduler(self):
        """Start the scheduled tasks"""
        # Send heartbeat every 2 minutes
        schedule.every(2).minutes.do(self.send_heartbeat)
        
        self.logger.info("Scheduler started")
        
        while True:
            schedule.run_pending()
            time.sleep(10)
    
    def run(self):
        """Main collector loop"""
        self.logger.info(f"Starting SamurEye Collector Agent {self.config['collector_name']}")
        
        # Send initial heartbeat
        self.send_heartbeat()
        
        # Start scheduler in background thread
        scheduler_thread = Thread(target=self.start_scheduler, daemon=True)
        scheduler_thread.start()
        
        try:
            # Keep main thread alive
            while True:
                time.sleep(60)
                
        except KeyboardInterrupt:
            self.logger.info("Collector stopped by user")
        except Exception as e:
            self.logger.error(f"Collector error: {e}")

if __name__ == '__main__':
    collector = SamurEyeCollector()
    collector.run()
EOF

chmod +x "$INSTALL_DIR/collector_agent.py"
log "✅ Collector Agent instalado"

# ============================================================================
# 5. CONFIGURAÇÃO DO COLLECTOR
# ============================================================================

log "Criando configuração do collector..."

cat > "/etc/samureye/collector.conf" << EOF
{
  "collector_name": "$COLLECTOR_NAME",
  "tenant_slug": "$TENANT_SLUG",
  "server_url": "$SERVER_URL",
  "heartbeat_interval": 120,
  "log_level": "INFO"
}
EOF

log "✅ Configuração criada"

# ============================================================================
# 6. CRIAR SERVIÇO SYSTEMD
# ============================================================================

log "Criando serviço systemd..."

cat > "/etc/systemd/system/samureye-collector.service" << EOF
[Unit]
Description=SamurEye Collector Agent - $COLLECTOR_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/collector_agent.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ============================================================================
# 7. AJUSTAR PERMISSÕES
# ============================================================================

log "Ajustando permissões..."
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "/var/log/samureye"
chown "$SERVICE_USER:$SERVICE_USER" "/etc/samureye/collector.conf"
chmod 600 "/etc/samureye/collector.conf"

# ============================================================================
# 8. HABILITAR E INICIAR SERVIÇO
# ============================================================================

log "Habilitando e iniciando serviço..."
systemctl daemon-reload
systemctl enable samureye-collector.service
systemctl start samureye-collector.service

# Aguardar inicialização
sleep 5

# ============================================================================
# 9. VERIFICAÇÃO E REGISTRO AUTOMÁTICO
# ============================================================================

log "Verificando status do serviço..."
if systemctl is-active --quiet samureye-collector.service; then
    log "✅ Serviço ativo"
    
    # Verificar se está enviando heartbeats
    log "Verificando conectividade com servidor..."
    sleep 10
    
    if systemctl status samureye-collector.service --no-pager | grep -q "Heartbeat sent successfully"; then
        log "✅ Heartbeats sendo enviados com sucesso"
    else
        warn "⚠️ Heartbeats ainda não confirmados, verificar logs"
    fi
else
    error "❌ Serviço não está ativo"
fi

# ============================================================================
# 10. REGISTRO NO SISTEMA SAMUREYE
# ============================================================================

log "Registrando collector no sistema SamurEye..."

# Tentar registrar o collector via API
REGISTER_PAYLOAD=$(cat << EOF
{
  "name": "$COLLECTOR_NAME",
  "hostname": "$(hostname)",
  "ipAddress": "$(hostname -I | awk '{print $1}')",
  "version": "1.0.0",
  "capabilities": ["nmap", "nuclei"],
  "tenant_slug": "$TENANT_SLUG"
}
EOF
)

# Fazer o registro
if curl -s -X POST "$SERVER_URL/api/collectors" \
     -H "Content-Type: application/json" \
     -d "$REGISTER_PAYLOAD" >/dev/null 2>&1; then
    log "✅ Collector registrado no sistema"
else
    warn "⚠️ Registro automático falhou, mas collector funcionará via heartbeat"
fi

# ============================================================================
# INSTALAÇÃO CONCLUÍDA
# ============================================================================

echo ""
log "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "   • Collector: $COLLECTOR_NAME"
echo "   • Tenant: $TENANT_SLUG"  
echo "   • Server: $SERVER_URL"
echo "   • Diretório: $INSTALL_DIR"
echo "   • Usuário: $SERVICE_USER"
echo ""
echo "🔍 VERIFICAÇÃO:"
echo "   • Status: systemctl status samureye-collector"
echo "   • Logs: journalctl -u samureye-collector -f"
echo "   • Config: /etc/samureye/collector.conf"
echo ""
echo "🌐 INTERFACE WEB:"
echo "   • Admin: $SERVER_URL/admin/collectors"
echo "   • Tenant: $SERVER_URL/collectors"
echo ""
echo "⚡ O collector já está enviando telemetria automaticamente!"

exit 0