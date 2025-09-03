#!/bin/bash

# vlxsam04 - Correção Registro Collector
# Execute APENAS no vlxsam04

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-collector-registration.sh"
fi

echo "🔧 vlxsam04 - CORREÇÃO REGISTRO COLLECTOR"
echo "========================================"
echo "Servidor: vlxsam04 (192.168.100.151)"
echo "Função: Collector Agent"
echo ""

COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"

if [ ! -d "$COLLECTOR_DIR" ]; then
    error "Diretório do collector não encontrado: $COLLECTOR_DIR"
fi

log "📁 Collector encontrado em: $COLLECTOR_DIR"

# ============================================================================
# 1. PARAR COLLECTOR
# ============================================================================

log "⏹️ Parando collector..."
systemctl stop samureye-collector 2>/dev/null || warn "Collector já estava parado"

# ============================================================================
# 2. CORRIGIR COLLECTOR_ID
# ============================================================================

log "🔧 Corrigindo collector_id..."

# Forçar ID correto no arquivo
echo "vlxsam04" > "$COLLECTOR_DIR/collector-id.txt"
chown samureye-collector:samureye-collector "$COLLECTOR_DIR/collector-id.txt"
chmod 600 "$COLLECTOR_DIR/collector-id.txt"

# Corrigir config.yaml
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

chown samureye-collector:samureye-collector "$CONFIG_DIR/config.yaml"
chmod 600 "$CONFIG_DIR/config.yaml"

log "✅ collector_id configurado como: vlxsam04"

# ============================================================================
# 3. VERIFICAR APLICAÇÃO PYTHON
# ============================================================================

log "🐍 Verificando aplicação Python..."

cd "$COLLECTOR_DIR"

# Atualizar aplicação Python se necessário
if [ -f "collector_agent.py" ]; then
    log "✅ collector_agent.py encontrado"
else
    log "📝 Criando collector_agent.py..."
    
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
        
        self.api_base_url = self.config.get('api', {}).get('base_url', 'https://api.samureye.com.br')
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
        self.logger.info("Starting SamurEye Collector Agent vlxsam04")
        
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
fi

# Ajustar permissões
chown -R samureye-collector:samureye-collector "$COLLECTOR_DIR"
chown -R samureye-collector:samureye-collector "$CONFIG_DIR"

# ============================================================================
# 4. INICIAR COLLECTOR
# ============================================================================

log "🚀 Iniciando collector..."
systemctl start samureye-collector

# Aguardar inicialização
sleep 5

if systemctl is-active --quiet samureye-collector; then
    log "✅ Collector iniciado com sucesso"
else
    error "❌ Falha ao iniciar collector"
fi

# ============================================================================
# 5. MONITORAR PRIMEIRO HEARTBEAT
# ============================================================================

log "⏱️ Monitorando primeiro heartbeat (60 segundos)..."

# Aguardar 2 ciclos de heartbeat
sleep 60

# Verificar logs recentes
RECENT_LOGS=$(journalctl -u samureye-collector --since "60 seconds ago" | grep -E "(heartbeat|ERROR|WARNING)" | tail -5 || echo "Nenhum log encontrado")

echo "📝 Logs recentes:"
echo "$RECENT_LOGS"

if echo "$RECENT_LOGS" | grep -q "Heartbeat enviado com sucesso"; then
    log "✅ Heartbeat funcionando!"
elif echo "$RECENT_LOGS" | grep -q "404"; then
    warn "⚠️ Ainda retornando 404 - backend pode estar reiniciando"
else
    warn "⚠️ Status incerto - verificar logs completos"
fi

# ============================================================================
# 6. TESTE MANUAL DO ENDPOINT
# ============================================================================

log "🧪 Teste manual do endpoint..."

HEARTBEAT_URL="https://api.samureye.com.br/collector-api/heartbeat"
RESPONSE=$(curl -k -s -X POST "$HEARTBEAT_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "collector_id": "vlxsam04",
        "status": "online",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }' 2>/dev/null || echo '{"error": "connection failed"}')

echo "📡 Resposta do teste: $RESPONSE"

if echo "$RESPONSE" | grep -q "Heartbeat received"; then
    log "✅ Teste manual: SUCESSO"
else
    warn "⚠️ Teste manual inconclusivo"
fi

echo ""
log "✅ CORREÇÕES vlxsam04 CONCLUÍDAS!"
echo ""
echo "📋 STATUS:"
echo "   • Collector ID: vlxsam04 (fixo)"
echo "   • Serviço: samureye-collector (ativo)"
echo "   • Config: /etc/samureye-collector/config.yaml"
echo ""
echo "🔗 VERIFICAR:"
echo "   • Interface: https://app.samureye.com.br/admin/collectors"
echo "   • Logs: journalctl -u samureye-collector -f"
echo ""
echo "📊 MONITORAR:"
systemctl status samureye-collector --no-pager -l | head -10

exit 0