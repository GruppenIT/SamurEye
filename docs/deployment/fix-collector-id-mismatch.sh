#!/bin/bash
# Script para corrigir incompatibilidade de collector_id no vlxsam04

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔧 Correção collector_id vlxsam04"
echo "================================"

log "🔍 Problema identificado: collector envia 'vlxsam04-collector-id' mas banco tem 'vlxsam04'"

# Verificar se existe arquivo collector-id.txt (usado pelo código Python)
COLLECTOR_ID_FILE="/opt/samureye-collector/collector-id.txt"

log "📝 Corrigindo collector-id.txt..."

# Criar/atualizar arquivo com ID correto
echo "vlxsam04" > "$COLLECTOR_ID_FILE"
chown samureye-collector:samureye-collector "$COLLECTOR_ID_FILE" 2>/dev/null || true
chmod 600 "$COLLECTOR_ID_FILE"

log "✅ Arquivo $COLLECTOR_ID_FILE atualizado para: vlxsam04"

# Atualizar configuração YAML também
log "📝 Atualizando config.yaml..."

cat > /etc/samureye-collector/config.yaml << 'EOF'
# SamurEye Collector Configuration - vlxsam04
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

chown samureye-collector:samureye-collector /etc/samureye-collector/config.yaml 2>/dev/null || true
chmod 600 /etc/samureye-collector/config.yaml

log "✅ Configuração atualizada - collector_id: vlxsam04"

# Reiniciar collector para aplicar mudanças
log "🔄 Reiniciando collector com nova configuração..."

systemctl stop samureye-collector
sleep 2
systemctl start samureye-collector
sleep 5

# Verificar se está funcionando
if systemctl is-active --quiet samureye-collector; then
    log "✅ Collector reiniciado com sucesso"
else
    log "❌ Falha ao reiniciar collector"
    systemctl status samureye-collector --no-pager -l
    exit 1
fi

# Monitorar logs por 30 segundos para ver se heartbeat funciona
log "📊 Monitorando heartbeat por 30 segundos..."

# Aguardar primeira tentativa de heartbeat
sleep 35

# Verificar últimos logs
RECENT_LOGS=$(journalctl -u samureye-collector --since "30 seconds ago" | grep -E "(heartbeat|ERROR|WARNING)" || echo "Nenhum log encontrado")

if echo "$RECENT_LOGS" | grep -q "404"; then
    log "❌ Ainda retornando 404 - verificar logs:"
    echo "$RECENT_LOGS"
else
    log "✅ Heartbeat funcionando - sem erros 404 nos últimos 30 segundos"
fi

# Teste manual final
log "🧪 Teste final do endpoint..."

HEARTBEAT_URL="https://api.samureye.com.br/collector-api/heartbeat"
RESPONSE=$(curl -k -s -X POST "$HEARTBEAT_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "collector_id": "vlxsam04",
        "status": "online",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "telemetry": {
            "cpu_percent": 25.0,
            "memory_percent": 45.0,
            "disk_percent": 60.0,
            "processes": 150
        }
    }' 2>/dev/null || echo '{"error": "connection failed"}')

if echo "$RESPONSE" | grep -q "Heartbeat received"; then
    log "✅ Teste manual do heartbeat: SUCESSO"
    echo "   Response: $RESPONSE"
else
    log "❌ Teste manual falhou"
    echo "   Response: $RESPONSE"
fi

echo ""
log "✅ Correção finalizada!"
echo ""
echo "📋 RESUMO:"
echo "   • collector-id.txt: vlxsam04"
echo "   • config.yaml atualizado"
echo "   • Collector reiniciado"
echo ""
echo "🔗 Verificar na interface:"
echo "   https://app.samureye.com.br/admin/collectors"
echo ""
echo "📝 Monitorar logs:"
echo "   journalctl -u samureye-collector -f"

exit 0