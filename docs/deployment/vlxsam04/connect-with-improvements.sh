#!/bin/bash

# vlxsam04 - Conectar collector com telemetria real melhorada

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./connect-with-improvements.sh"
fi

echo "📡 vlxsam04 - COLLECTOR COM TELEMETRIA MELHORADA"
echo "==============================================="

# ============================================================================
# 1. CONFIGURAR COLLECTOR COM TELEMETRIA REAL
# ============================================================================

log "🔧 Configurando collector com telemetria real..."

# Criar script de telemetria melhorado
cat > /opt/samureye/telemetry.py << 'EOF'
#!/usr/bin/env python3

import psutil
import requests
import json
import time
import subprocess
import socket
from datetime import datetime

def get_real_telemetry():
    """Coletar telemetria real do sistema"""
    
    # CPU usage (average over 1 second)
    cpu_percent = psutil.cpu_percent(interval=1)
    
    # Memory usage
    memory = psutil.virtual_memory()
    memory_percent = memory.percent
    memory_used_gb = memory.used / (1024**3)
    memory_total_gb = memory.total / (1024**3)
    
    # Disk usage
    disk = psutil.disk_usage('/')
    disk_percent = disk.percent
    disk_used_gb = disk.used / (1024**3)
    disk_total_gb = disk.total / (1024**3)
    
    # Process count
    process_count = len(psutil.pids())
    
    # Load average
    load_avg = psutil.getloadavg()[0] if hasattr(psutil, 'getloadavg') else 0
    
    # Network info
    hostname = socket.gethostname()
    
    # Check if security tools are running
    security_tools = []
    for proc in psutil.process_iter(['pid', 'name']):
        try:
            name = proc.info['name'].lower()
            if any(tool in name for tool in ['nmap', 'nuclei', 'masscan', 'openvas']):
                security_tools.append({
                    'name': proc.info['name'],
                    'pid': proc.info['pid']
                })
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    
    return {
        'timestamp': datetime.now().isoformat(),
        'hostname': hostname,
        'cpu': {
            'usage_percent': round(cpu_percent, 2),
            'load_average': round(load_avg, 2)
        },
        'memory': {
            'usage_percent': round(memory_percent, 2),
            'used_gb': round(memory_used_gb, 2),
            'total_gb': round(memory_total_gb, 2)
        },
        'disk': {
            'usage_percent': round(disk_percent, 2),
            'used_gb': round(disk_used_gb, 2),
            'total_gb': round(disk_total_gb, 2)
        },
        'processes': {
            'total_count': process_count,
            'security_tools': security_tools
        },
        'status': 'online'
    }

def send_heartbeat():
    """Enviar heartbeat com telemetria para o servidor"""
    try:
        telemetry = get_real_telemetry()
        
        # Configuração do collector
        collector_config = {
            'collector_id': 'vlxsam04-collector-1685e108',
            'name': 'vlxsam04',
            'ipAddress': '192.168.100.154',
            'version': '1.0.0'
        }
        
        # Combinar dados
        heartbeat_data = {
            **collector_config,
            'telemetry': telemetry,
            'lastSeen': telemetry['timestamp']
        }
        
        # Enviar para o servidor
        response = requests.post(
            'http://192.168.100.152:5000/collector-api/heartbeat',
            json=heartbeat_data,
            timeout=10,
            headers={'Content-Type': 'application/json'}
        )
        
        if response.status_code == 200:
            print(f"✅ Heartbeat enviado - CPU: {telemetry['cpu']['usage_percent']}%, RAM: {telemetry['memory']['usage_percent']}%, Disk: {telemetry['disk']['usage_percent']}%")
            return True
        else:
            print(f"❌ Erro no heartbeat: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ Erro ao enviar heartbeat: {e}")
        return False

if __name__ == "__main__":
    print(f"🚀 Iniciando telemetria melhorada - {datetime.now()}")
    print("📊 Enviando telemetria real: CPU, Memória, Disco, Processos")
    
    while True:
        send_heartbeat()
        time.sleep(30)  # Enviar a cada 30 segundos
EOF

chmod +x /opt/samureye/telemetry.py

# ============================================================================
# 2. INSTALAR DEPENDÊNCIAS PYTHON
# ============================================================================

log "📦 Instalando dependências Python..."

apt update
apt install -y python3 python3-pip
pip3 install psutil requests

# ============================================================================
# 3. CRIAR SERVIÇO SYSTEMD PARA TELEMETRIA
# ============================================================================

log "🔧 Criando serviço systemd para telemetria..."

cat > /etc/systemd/system/samureye-telemetry.service << 'EOF'
[Unit]
Description=SamurEye Collector Telemetry
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/samureye
ExecStart=/usr/bin/python3 /opt/samureye/telemetry.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-telemetry

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable samureye-telemetry

# ============================================================================
# 4. PARAR SERVIÇOS ANTIGOS E INICIAR NOVO
# ============================================================================

log "🔄 Parando serviços antigos e iniciando telemetria melhorada..."

# Parar qualquer serviço antigo
systemctl stop samureye-collector 2>/dev/null || true
systemctl stop samureye-app 2>/dev/null || true

# Iniciar nova telemetria
systemctl start samureye-telemetry

sleep 10

# ============================================================================
# 5. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Verificando telemetria..."

if systemctl is-active --quiet samureye-telemetry; then
    log "✅ Serviço de telemetria rodando"
    
    # Verificar logs recentes
    log "📝 Logs recentes da telemetria:"
    journalctl -u samureye-telemetry --no-pager -n 3
    
    # Testar conectividade
    if curl -s http://192.168.100.152:5000/collector-api/health | grep -q "ok"; then
        log "✅ Conectividade com servidor OK"
    else
        warn "⚠️ Problemas de conectividade com servidor"
    fi
    
else
    error "❌ Serviço de telemetria não iniciou"
fi

echo ""
log "🎯 COLLECTOR COM TELEMETRIA REAL ATIVO"
echo "======================================"
echo ""
echo "✅ MELHORIAS IMPLEMENTADAS:"
echo "   • Telemetria real: CPU, Memória, Disco"
echo "   • Contagem de processos"
echo "   • Detecção de ferramentas de segurança"
echo "   • Heartbeat a cada 30 segundos"
echo "   • Detecção offline automática (5min timeout)"
echo ""
echo "📊 DADOS COLETADOS:"
echo "   • CPU usage % em tempo real"
echo "   • RAM usage % e GB"
echo "   • Disk usage % e GB"
echo "   • Process count"
echo "   • Security tools running"
echo ""
echo "📡 Enviando telemetria para: http://192.168.100.152:5000"
echo ""
echo "💡 Para verificar logs: journalctl -u samureye-telemetry -f"

exit 0