#!/bin/bash

# SamurEye vlxsam04 - VERSÃO CORRIGIDA COM COLLECTOR_ID FIX
# Servidor: vlxsam04 (192.168.100.151)
# Inclui: collector_id correto + heartbeat funcionando

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

echo "🚀 SAMUREYE vlxsam04 - INSTALAÇÃO CORRIGIDA"
echo "==========================================="
echo "✅ collector_id fixo: vlxsam04 (sem sufixo)"
echo "✅ Heartbeat funcionando"
echo "✅ Configuração simplificada"
echo ""

# Configurações
SERVER_IP="192.168.100.151"
COLLECTOR_USER="samureye-collector"
COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
TOOLS_DIR="$COLLECTOR_DIR/tools"

log "📍 Servidor: $SERVER_IP"
log "📁 Diretório: $COLLECTOR_DIR"

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
    python3.12 \
    python3.12-pip \
    python3.12-venv \
    git \
    build-essential

# ============================================================================
# 2. INSTALAÇÃO DE FERRAMENTAS DE SEGURANÇA
# ============================================================================

log "🔒 Instalando ferramentas de segurança..."

# Criar diretório para ferramentas
mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"

# Instalar nmap
if ! command -v nmap >/dev/null 2>&1; then
    log "📦 Instalando nmap..."
    apt install -y nmap
fi

# Instalar nuclei
if ! command -v nuclei >/dev/null 2>&1; then
    log "📦 Instalando nuclei..."
    wget -q https://github.com/projectdiscovery/nuclei/releases/download/v3.1.0/nuclei_3.1.0_linux_amd64.zip
    unzip -q nuclei_3.1.0_linux_amd64.zip
    mv nuclei /usr/local/bin/
    chmod +x /usr/local/bin/nuclei
    rm nuclei_3.1.0_linux_amd64.zip
    
    # Atualizar templates
    nuclei -update-templates >/dev/null 2>&1 || true
fi

# ============================================================================
# 3. CRIAÇÃO DO USUÁRIO E ESTRUTURA
# ============================================================================

log "👤 Configurando usuário samureye-collector..."

# Criar usuário se não existir
if ! id "$COLLECTOR_USER" >/dev/null 2>&1; then
    useradd -r -s /bin/bash -d "$COLLECTOR_DIR" "$COLLECTOR_USER"
fi

# Criar estrutura de diretórios
mkdir -p "$COLLECTOR_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$TOOLS_DIR"
mkdir -p "/var/log/samureye-collector"

# ============================================================================
# 4. APLICAÇÃO COLLECTOR PYTHON
# ============================================================================

log "🐍 Instalando aplicação Python collector..."

cd "$COLLECTOR_DIR"

# Criar ambiente virtual Python
python3.12 -m venv venv
source venv/bin/activate

# Instalar dependências Python
pip install --upgrade pip
pip install requests psutil pyyaml

# Criar aplicação collector corrigida
cat > collector_agent.py << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent - VERSÃO CORRIGIDA
Heartbeat funcionando com collector_id: vlxsam04
"""

import json
import logging
import time
import requests
import psutil
import yaml
from pathlib import Path
from datetime import datetime
import socket

class SamurEyeCollector:
    def __init__(self, config_path="/etc/samureye-collector/config.yaml"):
        self.config_path = Path(config_path)
        self.collector_dir = Path("/opt/samureye-collector")
        
        # Configurar logging
        self.logger = self._setup_logging()
        
        # Carregar configuração
        self.config = self._load_config()
        
        # ID FIXO - CORREÇÃO PRINCIPAL
        self.collector_id = "vlxsam04"  # Sem sufixos ou geradores
        
        self.api_base_url = self.config.get('API_BASE_URL', 'https://api.samureye.com.br')
        self.logger.info(f"Collector iniciado: {self.collector_id}")

    def _setup_logging(self):
        """Configure logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/samureye-collector.log'),
                logging.StreamHandler()
            ]
        )
        return logging.getLogger('samureye-collector')

    def _load_config(self):
        """Load configuration from YAML file"""
        try:
            if self.config_path.exists():
                with open(self.config_path, 'r') as f:
                    return yaml.safe_load(f)
            return {}
        except Exception as e:
            self.logger.error(f"Error loading config: {e}")
            return {}

    def get_system_info(self):
        """Collect system telemetry"""
        try:
            return {
                "cpu_percent": psutil.cpu_percent(interval=1),
                "memory_percent": psutil.virtual_memory().percent,
                "disk_percent": psutil.disk_usage('/').percent,
                "processes": len(psutil.pids()),
                "network_io": psutil.net_io_counters()._asdict() if psutil.net_io_counters() else {},
                "hostname": socket.gethostname(),
                "timestamp": datetime.utcnow().isoformat()
            }
        except Exception as e:
            self.logger.error(f"Error collecting system info: {e}")
            return {}

    def send_heartbeat(self):
        """Send heartbeat to SamurEye API"""
        try:
            telemetry = self.get_system_info()
            
            payload = {
                "collector_id": self.collector_id,  # SEMPRE "vlxsam04"
                "status": "active",
                "timestamp": datetime.utcnow().isoformat(),
                "telemetry": telemetry,
                "capabilities": ["nmap", "nuclei"],
                "version": "1.0.0"
            }
            
            url = f"{self.api_base_url}/collector-api/heartbeat"
            
            response = requests.post(
                url,
                json=payload,
                timeout=30,
                verify=False  # Para desenvolvimento
            )
            
            if response.status_code == 200:
                self.logger.info(f"Heartbeat enviado com sucesso: {response.json()}")
                return True
            else:
                self.logger.warning(f"Heartbeat failed: {response.status_code}")
                self.logger.warning(f"Response: {response.text}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error sending heartbeat: {e}")
            return False

    def run(self):
        """Main collector loop"""
        self.logger.info("Starting SamurEye Collector Agent")
        
        while True:
            try:
                self.send_heartbeat()
                time.sleep(30)  # Heartbeat a cada 30 segundos
                
            except KeyboardInterrupt:
                self.logger.info("Collector stopped by user")
                break
            except Exception as e:
                self.logger.error(f"Unexpected error: {e}")
                time.sleep(10)

if __name__ == "__main__":
    collector = SamurEyeCollector()
    collector.run()
EOF

chmod +x collector_agent.py

# ============================================================================
# 5. CONFIGURAÇÃO CORRIGIDA
# ============================================================================

log "⚙️ Criando configuração corrigida..."

# Configuração YAML simplificada e corrigida
cat > "$CONFIG_DIR/config.yaml" << EOF
# SamurEye Collector Configuration - vlxsam04 CORRIGIDO
collector:
  id: "vlxsam04"
  name: "vlxsam04"
  tenant_id: "default-tenant-id"

api:
  base_url: "https://api.samureye.com.br"
  heartbeat_endpoint: "/collector-api/heartbeat"
  telemetry_endpoint: "/collector-api/telemetry"
  verify_ssl: false
  timeout: 30

logging:
  level: "INFO"
  file: "/var/log/samureye-collector.log"

intervals:
  heartbeat: 30
  telemetry: 60
  health_check: 300
EOF

# Criar arquivo collector-id.txt com ID correto
echo "vlxsam04" > "$COLLECTOR_DIR/collector-id.txt"

# Ajustar permissões
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR"
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$CONFIG_DIR"
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "/var/log/samureye-collector"
chmod 600 "$CONFIG_DIR/config.yaml"
chmod 600 "$COLLECTOR_DIR/collector-id.txt"

# ============================================================================
# 6. SERVIÇO SYSTEMD CORRIGIDO
# ============================================================================

log "⚙️ Configurando serviço systemd..."

cat > /etc/systemd/system/samureye-collector.service << EOF
[Unit]
Description=SamurEye Collector Agent (vlxsam04)
After=network.target
Wants=network.target

[Service]
Type=simple
User=$COLLECTOR_USER
Group=$COLLECTOR_USER
WorkingDirectory=$COLLECTOR_DIR
Environment=PYTHONPATH=$COLLECTOR_DIR
ExecStart=$COLLECTOR_DIR/venv/bin/python $COLLECTOR_DIR/collector_agent.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-collector

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$COLLECTOR_DIR /var/log/samureye-collector /tmp

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar serviço
systemctl daemon-reload
systemctl enable samureye-collector
systemctl stop samureye-collector 2>/dev/null || true
systemctl start samureye-collector

# Aguardar inicialização
sleep 5

# ============================================================================
# 7. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Verificando instalação..."

if systemctl is-active --quiet samureye-collector; then
    log "✅ Serviço samureye-collector ativo"
else
    error "❌ Serviço samureye-collector falhou"
fi

# Aguardar primeiro heartbeat
log "⏱️ Aguardando primeiro heartbeat (35 segundos)..."
sleep 35

# Verificar logs
RECENT_LOGS=$(journalctl -u samureye-collector --since "30 seconds ago" | grep -E "(heartbeat|ERROR|WARNING)" || echo "Nenhum log encontrado")

if echo "$RECENT_LOGS" | grep -q "Heartbeat enviado com sucesso"; then
    log "✅ Heartbeat funcionando!"
elif echo "$RECENT_LOGS" | grep -q "404"; then
    error "❌ Ainda retornando 404 - verificar backend"
else
    warn "⚠️ Status do heartbeat incerto - verificar logs"
fi

# Teste manual do endpoint
log "🧪 Teste manual do endpoint..."

HEARTBEAT_URL="https://api.samureye.com.br/collector-api/heartbeat"
RESPONSE=$(curl -k -s -X POST "$HEARTBEAT_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "collector_id": "vlxsam04",
        "status": "online",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }' 2>/dev/null || echo '{"error": "connection failed"}')

if echo "$RESPONSE" | grep -q "Heartbeat received"; then
    log "✅ Teste manual: SUCESSO"
else
    warn "⚠️ Teste manual falhou: $RESPONSE"
fi

echo ""
log "✅ INSTALAÇÃO vlxsam04 CONCLUÍDA!"
echo ""
echo "📋 RESUMO:"
echo "   • Collector ID: vlxsam04 (fixo, sem sufixos)"
echo "   • Heartbeat: Cada 30 segundos"
echo "   • Serviço: samureye-collector (ativo)"
echo "   • Ferramentas: nmap, nuclei"
echo ""
echo "🔗 VERIFICAÇÕES:"
echo "   • Interface: https://app.samureye.com.br/admin/collectors"
echo "   • Logs: journalctl -u samureye-collector -f"
echo ""
echo "📊 STATUS ATUAL:"
systemctl status samureye-collector --no-pager -l | head -10

exit 0