#!/bin/bash
# Script para diagnosticar e corrigir problemas de telemetria do collector vlxsam04

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2
}

COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
API_BASE_URL="https://api.samureye.com.br"
CERTS_DIR="$COLLECTOR_DIR/certs"

echo "🔧 Diagnóstico de Telemetria do Collector vlxsam04"
echo "================================================"
echo ""

log "1. Verificando status do serviço..."
if systemctl is-active samureye-collector.service >/dev/null 2>&1; then
    log "✅ Serviço samureye-collector ativo"
    
    # Verificar logs recentes
    log "📋 Logs recentes do collector:"
    journalctl -u samureye-collector.service --no-pager -n 10 | tail -5
else
    error "Serviço samureye-collector inativo"
    log "Iniciando serviço..."
    systemctl start samureye-collector.service
    sleep 3
fi

log "2. Verificando certificados..."
if [[ -f "$CERTS_DIR/collector.crt" && -f "$CERTS_DIR/collector.key" && -f "$CERTS_DIR/ca.crt" ]]; then
    log "✅ Certificados presentes"
    
    # Verificar validade do certificado
    if openssl x509 -in "$CERTS_DIR/collector.crt" -checkend 86400 >/dev/null 2>&1; then
        log "✅ Certificado válido"
    else
        error "Certificado expirado ou inválido"
    fi
else
    error "Certificados ausentes"
    exit 1
fi

log "3. Testando conectividade com API..."
# Testar endpoint de sistema
if curl -k -s --cert "$CERTS_DIR/collector.crt" --key "$CERTS_DIR/collector.key" \
   "$API_BASE_URL/api/system/settings" | grep -q "systemName"; then
    log "✅ API respondendo corretamente"
else
    error "Falha na comunicação com API"
    exit 1
fi

log "4. Testando endpoint de heartbeat..."
# Criar payload de teste de heartbeat
HEARTBEAT_TEST=$(cat <<EOF
{
    "collector_id": "test-$(hostname -s)",
    "status": "online",
    "timestamp": "$(date -Iseconds)",
    "telemetry": {
        "cpu_percent": 10.5,
        "memory_percent": 25.3,
        "disk_percent": 45.2,
        "load_average": [0.5, 0.4, 0.3],
        "processes": 120,
        "uptime": 86400
    },
    "capabilities": ["nmap", "nuclei"]
}
EOF
)

HEARTBEAT_RESPONSE=$(curl -k -s -w "HTTP:%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$HEARTBEAT_TEST" \
    --cert "$CERTS_DIR/collector.crt" \
    --key "$CERTS_DIR/collector.key" \
    "$API_BASE_URL/api/collectors/heartbeat" 2>/dev/null || echo "HTTP:000")

HTTP_CODE=$(echo "$HEARTBEAT_RESPONSE" | grep -o "HTTP:[0-9]*" | cut -d: -f2)

if [[ "$HTTP_CODE" =~ ^(200|201)$ ]]; then
    log "✅ Endpoint heartbeat funcionando (HTTP $HTTP_CODE)"
else
    log "⚠️ Problema no endpoint heartbeat (HTTP $HTTP_CODE)"
    echo "Resposta: $HEARTBEAT_RESPONSE"
fi

log "5. Verificando configuração do collector..."
if [[ -f "$CONFIG_DIR/.env" ]]; then
    log "✅ Arquivo de configuração presente"
    
    # Verificar variáveis importantes
    source "$CONFIG_DIR/.env"
    
    if [[ -n "$COLLECTOR_NAME" && -n "$TENANT_SLUG" ]]; then
        log "✅ Configuração básica correta"
        echo "  Collector: $COLLECTOR_NAME"
        echo "  Tenant: $TENANT_SLUG"
    else
        error "Configuração incompleta"
    fi
else
    error "Arquivo de configuração ausente"
    exit 1
fi

log "6. Criando script de telemetria manual..."
# Criar script para enviar telemetria manualmente
cat > "$COLLECTOR_DIR/send_telemetry.py" << 'EOF'
#!/usr/bin/env python3
"""
Script para enviar telemetria manual do collector
"""

import json
import ssl
import urllib.request
import urllib.parse
import os
import psutil
import socket
from datetime import datetime

def get_system_telemetry():
    """Coleta telemetria do sistema"""
    try:
        return {
            "cpu_percent": psutil.cpu_percent(interval=1),
            "memory_percent": psutil.virtual_memory().percent,
            "disk_percent": psutil.disk_usage('/').percent,
            "load_average": list(os.getloadavg()) if hasattr(os, 'getloadavg') else [0, 0, 0],
            "processes": len(psutil.pids()),
            "uptime": int(psutil.boot_time()),
            "network_io": dict(psutil.net_io_counters()._asdict()) if hasattr(psutil, 'net_io_counters') else {},
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        return {"error": str(e), "timestamp": datetime.now().isoformat()}

def send_heartbeat():
    """Envia heartbeat com telemetria"""
    # Carregar configuração
    config = {}
    try:
        with open('/etc/samureye-collector/.env') as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    key, _, value = line.strip().partition('=')
                    if key and value:
                        config[key] = value
    except Exception as e:
        print(f"Erro ao carregar configuração: {e}")
        return False
    
    # Preparar dados
    heartbeat_data = {
        "collector_id": config.get('COLLECTOR_NAME', socket.gethostname()),
        "status": "online",
        "timestamp": datetime.now().isoformat(),
        "telemetry": get_system_telemetry(),
        "capabilities": ["nmap", "nuclei", "security_scan"],
        "version": "1.0.0"
    }
    
    # Preparar certificados SSL
    cert_file = config.get('TLS_CERT_FILE', '/opt/samureye-collector/certs/collector.crt')
    key_file = config.get('TLS_KEY_FILE', '/opt/samureye-collector/certs/collector.key')
    ca_file = config.get('CA_CERT_FILE', '/opt/samureye-collector/certs/ca.crt')
    
    if not all(os.path.exists(f) for f in [cert_file, key_file, ca_file]):
        print("Erro: Certificados não encontrados")
        return False
    
    try:
        # Criar contexto SSL
        context = ssl.create_default_context(cafile=ca_file)
        context.load_cert_chain(cert_file, key_file)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE  # Para desenvolvimento
        
        # Preparar request
        api_url = config.get('API_BASE_URL', 'https://api.samureye.com.br')
        url = f"{api_url}/api/collectors/heartbeat"
        
        data = json.dumps(heartbeat_data).encode('utf-8')
        
        req = urllib.request.Request(
            url,
            data=data,
            headers={
                'Content-Type': 'application/json',
                'Content-Length': str(len(data))
            }
        )
        
        # Enviar request
        with urllib.request.urlopen(req, context=context) as response:
            result = response.read().decode('utf-8')
            print(f"Sucesso: HTTP {response.status}")
            print(f"Resposta: {result}")
            return True
            
    except Exception as e:
        print(f"Erro ao enviar heartbeat: {e}")
        return False

if __name__ == "__main__":
    print("🔧 Enviando telemetria manual...")
    if send_heartbeat():
        print("✅ Telemetria enviada com sucesso")
    else:
        print("❌ Falha ao enviar telemetria")
EOF

chmod +x "$COLLECTOR_DIR/send_telemetry.py"
chown samureye-collector:samureye-collector "$COLLECTOR_DIR/send_telemetry.py"

log "7. Testando envio de telemetria manual..."
if python3 "$COLLECTOR_DIR/send_telemetry.py"; then
    log "✅ Telemetria manual enviada com sucesso"
else
    log "⚠️ Falha na telemetria manual"
fi

log "8. Verificando processo Python do collector..."
if pgrep -f "collector_agent.py" >/dev/null; then
    log "✅ Processo Python do collector rodando"
    echo "PIDs: $(pgrep -f collector_agent.py)"
else
    log "⚠️ Processo Python não encontrado"
    
    log "Tentando iniciar collector Python manualmente..."
    cd "$COLLECTOR_DIR"
    
    # Iniciar em background
    nohup sudo -u samureye-collector python3 collector_agent.py > /var/log/samureye-collector/agent.log 2>&1 &
    
    sleep 3
    
    if pgrep -f "collector_agent.py" >/dev/null; then
        log "✅ Collector Python iniciado"
    else
        error "Falha ao iniciar collector Python"
    fi
fi

log "9. Verificando logs detalhados..."
echo ""
echo "📋 Últimos logs do collector:"
tail -10 /var/log/samureye-collector/agent.log 2>/dev/null || echo "Log não encontrado"

echo ""
echo "📋 Status final dos serviços:"
echo "  systemd service: $(systemctl is-active samureye-collector.service)"
echo "  Python process: $(pgrep -f collector_agent.py >/dev/null && echo 'running' || echo 'not running')"

echo ""
echo "🔍 Comandos de diagnóstico:"
echo "  journalctl -u samureye-collector.service -f"
echo "  tail -f /var/log/samureye-collector/agent.log"
echo "  python3 $COLLECTOR_DIR/send_telemetry.py"
echo "  systemctl restart samureye-collector.service"

echo ""
log "✅ Diagnóstico de telemetria concluído"