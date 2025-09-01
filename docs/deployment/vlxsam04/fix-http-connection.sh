#!/bin/bash

# vlxsam04 - Corrigir Conexão HTTP do Collector
# Mudar de HTTPS para HTTP baseado na configuração atual

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-http-connection.sh"
fi

echo "🌐 vlxsam04 - CORRIGIR CONEXÃO HTTP"
echo "=================================="

# ============================================================================
# 1. PARAR COLLECTOR
# ============================================================================

log "⏹️ Parando collector..."
systemctl stop samureye-collector

# ============================================================================
# 2. ATUALIZAR CONFIGURAÇÃO PARA HTTP
# ============================================================================

log "🔧 Atualizando configuração para HTTP..."

if [ -f "/etc/samureye/collector.conf" ]; then
    # Backup
    cp /etc/samureye/collector.conf /etc/samureye/collector.conf.backup
    
    # Detectar IP correto do vlxsam01
    GATEWAY_IP="192.168.100.151"  # vlxsam01
    
    # Atualizar configuração para usar HTTP
    cat > /etc/samureye/collector.conf << EOF
{
  "collector_name": "vlxsam04",
  "hostname": "$(hostname)",
  "ip_address": "$(hostname -I | awk '{print $1}')",
  "tenant_slug": "default",
  "server_url": "http://app.samureye.com.br",
  "direct_server": "http://192.168.100.152:5000",
  "heartbeat_interval": 120,
  "log_level": "INFO",
  "capabilities": ["nmap", "nuclei", "system_scan"],
  "version": "1.0.0",
  "use_ssl_verify": false
}
EOF
    
    log "✅ Configuração atualizada para HTTP"
else
    error "Configuração do collector não encontrada"
fi

# ============================================================================
# 3. ATUALIZAR COLLECTOR AGENT
# ============================================================================

log "🤖 Atualizando collector agent para HTTP..."

INSTALL_DIR="/opt/samureye-collector"

cat > "$INSTALL_DIR/collector_agent.py" << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent - Versão HTTP
Conecta via HTTP para ambiente on-premise
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
from datetime import datetime, timezone
from threading import Thread
import signal
import warnings

# Suprimir warnings SSL
warnings.filterwarnings('ignore', message='Unverified HTTPS request')

class SamurEyeCollector:
    def __init__(self, config_file='/etc/samureye/collector.conf'):
        self.config_file = config_file
        self.config = self.load_config()
        self.setup_logging()
        self.running = True
        
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)
        
    def signal_handler(self, signum, frame):
        self.logger.info(f"Sinal {signum} recebido, parando collector...")
        self.running = False
        
    def load_config(self):
        try:
            with open(self.config_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"ERRO ao carregar configuração: {e}")
            sys.exit(1)
    
    def setup_logging(self):
        log_level = getattr(logging, self.config.get('log_level', 'INFO'))
        
        logging.basicConfig(
            level=log_level,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/samureye/collector.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('samureye-collector')
    
    def get_system_telemetry(self):
        """Coletar telemetria real do sistema"""
        try:
            # CPU (média 1 segundo)
            cpu_percent = psutil.cpu_percent(interval=1)
            
            # Memory
            memory = psutil.virtual_memory()
            
            # Disk (root filesystem)
            disk = psutil.disk_usage('/')
            
            # Network I/O
            network = psutil.net_io_counters()
            
            # Processes
            process_count = len(psutil.pids())
            
            # Load average
            load_avg = os.getloadavg()
            
            return {
                'cpuUsage': round(cpu_percent, 2),
                'memoryUsage': round(memory.percent, 2),
                'diskUsage': round((disk.used / disk.total) * 100, 2),
                'memoryDetails': {
                    'used_gb': round(memory.used / (1024**3), 2),
                    'total_gb': round(memory.total / (1024**3), 2),
                    'available_gb': round(memory.available / (1024**3), 2)
                },
                'diskDetails': {
                    'used_gb': round(disk.used / (1024**3), 2),
                    'total_gb': round(disk.total / (1024**3), 2),
                    'free_gb': round(disk.free / (1024**3), 2)
                },
                'networkIO': {
                    'bytes_sent': network.bytes_sent,
                    'bytes_recv': network.bytes_recv
                },
                'processCount': process_count,
                'loadAverage': list(load_avg),
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'hostname': self.config.get('hostname'),
                'collector_version': self.config.get('version', '1.0.0')
            }
        except Exception as e:
            self.logger.error(f"Erro coletando telemetria: {e}")
            return None
    
    def send_heartbeat(self):
        """Enviar heartbeat com telemetria"""
        try:
            telemetry = self.get_system_telemetry()
            
            if not telemetry:
                self.logger.warning("Telemetria indisponível")
                return
            
            payload = {
                'collector_id': self.config['collector_name'],
                'hostname': self.config.get('hostname'),
                'ip_address': self.config.get('ip_address'),
                'status': 'active',
                'telemetry': telemetry,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'capabilities': self.config.get('capabilities', []),
                'version': self.config.get('version', '1.0.0')
            }
            
            # Tentar múltiplas URLs
            urls = [
                f"{self.config['server_url']}/collector-api/heartbeat",
                f"{self.config.get('direct_server', 'http://192.168.100.152:5000')}/collector-api/heartbeat"
            ]
            
            for url in urls:
                try:
                    self.logger.info(f"Enviando heartbeat para {url}")
                    
                    response = requests.post(
                        url, 
                        json=payload, 
                        timeout=15,
                        verify=False,
                        headers={'Content-Type': 'application/json'}
                    )
                    
                    if response.status_code == 200:
                        self.logger.info("✅ Heartbeat enviado com sucesso")
                        return
                    else:
                        self.logger.warning(f"Resposta HTTP {response.status_code}: {response.text[:100]}")
                        
                except requests.exceptions.RequestException as e:
                    self.logger.warning(f"Falha em {url}: {e}")
                    continue
            
            self.logger.error("❌ Falha em enviar heartbeat para todas URLs")
            
        except Exception as e:
            self.logger.error(f"Erro geral no heartbeat: {e}")
    
    def start_scheduler(self):
        """Scheduler de tarefas"""
        schedule.every(2).minutes.do(self.send_heartbeat)
        
        self.logger.info("Scheduler iniciado - heartbeat a cada 2 minutos")
        
        while self.running:
            schedule.run_pending()
            time.sleep(10)
    
    def run(self):
        """Loop principal"""
        self.logger.info(f"🚀 Iniciando SamurEye Collector Agent: {self.config['collector_name']}")
        self.logger.info(f"🌐 Server URL: {self.config['server_url']}")
        self.logger.info(f"💻 Hostname: {self.config.get('hostname')}")
        self.logger.info(f"🆔 IP: {self.config.get('ip_address')}")
        
        # Heartbeat inicial
        self.send_heartbeat()
        
        # Iniciar scheduler
        scheduler_thread = Thread(target=self.start_scheduler, daemon=True)
        scheduler_thread.start()
        
        try:
            while self.running:
                time.sleep(60)
        except KeyboardInterrupt:
            self.logger.info("Collector interrompido")
        except Exception as e:
            self.logger.error(f"Erro no collector: {e}")
        finally:
            self.running = False
            self.logger.info("Collector finalizado")

if __name__ == '__main__':
    collector = SamurEyeCollector()
    collector.run()
EOF

chmod +x "$INSTALL_DIR/collector_agent.py"
chown -R samureye:samureye "$INSTALL_DIR"
chown samureye:samureye /etc/samureye/collector.conf

log "✅ Collector agent atualizado para HTTP"

# ============================================================================
# 4. INICIAR COLLECTOR
# ============================================================================

log "🚀 Iniciando collector..."
systemctl start samureye-collector

sleep 15

# ============================================================================
# 5. VERIFICAÇÃO
# ============================================================================

log "🧪 Verificando funcionamento..."

if systemctl is-active --quiet samureye-collector; then
    log "✅ Serviço ativo"
    
    # Verificar logs recentes
    log "📝 Últimos logs:"
    journalctl -u samureye-collector --no-pager -n 10
    
    # Testar conectividade manual
    log "🌐 Testando conectividade manual..."
    
    if curl -s http://192.168.100.152:5000/collector-api/health | grep -q "ok"; then
        log "✅ vlxsam02 acessível via HTTP"
    else
        warn "⚠️ vlxsam02 pode não estar respondendo"
    fi
    
    if curl -s http://app.samureye.com.br/collector-api/health | grep -q "ok"; then
        log "✅ Gateway vlxsam01 proxy funcionando"
    else
        warn "⚠️ Gateway proxy pode ter problemas"
    fi
    
else
    error "❌ Serviço não está ativo"
fi

# ============================================================================
# 6. RESULTADO
# ============================================================================

echo ""
log "🎯 CONEXÃO HTTP CORRIGIDA"
echo "════════════════════════════════════════════════"
echo ""
echo "🔧 CONFIGURAÇÃO:"
echo "   ✓ Mudou de HTTPS para HTTP"
echo "   ✓ URL: http://app.samureye.com.br"
echo "   ✓ Direto: http://192.168.100.152:5000"
echo "   ✓ SSL verify desabilitado"
echo ""
echo "🤖 COLLECTOR:"
echo "   ✓ Agent atualizado para HTTP"
echo "   ✓ Múltiplas URLs de fallback"
echo "   ✓ Telemetria real coletada"
echo ""
echo "📝 MONITORAMENTO:"
echo "   journalctl -u samureye-collector -f"
echo ""
echo "💡 AGUARDE 2-3 MINUTOS:"
echo "   O collector enviará heartbeat automático"
echo "   Verifique na interface se aparece online"

exit 0