#!/bin/bash
# Script de correção para vlxsam04 (Collector) - SamurEye On-Premise

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔧 Correção Collector vlxsam04 - SamurEye"
echo "======================================="

COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
API_BASE_URL="https://api.samureye.com.br"

# 1. Atualizar script de instalação
log "1. Atualizando script de instalação..."
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/install.sh > /tmp/install-vlxsam04.sh
chmod +x /tmp/install-vlxsam04.sh

# 2. Verificar serviço do collector
log "2. Verificando serviço do collector..."
if systemctl is-active samureye-collector >/dev/null 2>&1; then
    log "✅ samureye-collector ativo"
else
    log "❌ samureye-collector inativo - iniciando..."
    systemctl restart samureye-collector
    sleep 3
fi

# 3. Verificar certificados mTLS
log "3. Verificando certificados..."
CERT_FILES=(
    "$COLLECTOR_DIR/certs/collector.crt"
    "$COLLECTOR_DIR/certs/collector.key" 
    "$COLLECTOR_DIR/certs/ca.crt"
)

for cert in "${CERT_FILES[@]}"; do
    if [[ -f "$cert" ]]; then
        log "✅ Certificado presente: $cert"
        
        # Verificar validade (apenas para .crt)
        if [[ "$cert" == *.crt ]]; then
            if openssl x509 -in "$cert" -checkend 86400 >/dev/null 2>&1; then
                log "  ✅ Certificado válido"
            else
                log "  ⚠️ Certificado expira em menos de 24h"
            fi
        fi
    else
        log "❌ Certificado ausente: $cert"
        log "  Execute: /tmp/install-vlxsam04.sh"
        exit 1
    fi
done

# 4. Verificar configuração
log "4. Verificando configuração..."
if [[ -f "$CONFIG_DIR/.env" ]]; then
    log "✅ Arquivo de configuração presente"
    source "$CONFIG_DIR/.env"
    
    if [[ -n "$COLLECTOR_NAME" && -n "$TENANT_SLUG" ]]; then
        log "  Collector: $COLLECTOR_NAME"
        log "  Tenant: $TENANT_SLUG"
    else
        log "⚠️ Configuração incompleta"
    fi
else
    log "❌ Arquivo de configuração ausente"
    exit 1
fi

# 5. Testar conectividade com API
log "5. Testando conectividade com API..."
if curl -k -s --connect-timeout 5 \
   --cert "$COLLECTOR_DIR/certs/collector.crt" \
   --key "$COLLECTOR_DIR/certs/collector.key" \
   "$API_BASE_URL/api/system/settings" | grep -q "systemName"; then
    log "✅ API acessível com mTLS"
else
    log "❌ Falha na conectividade com API"
    log "  Verifique: $API_BASE_URL"
fi

# 6. Testar endpoint de heartbeat atualizado
log "6. Testando endpoint de heartbeat..."
HEARTBEAT_DATA=$(cat <<EOF
{
    "collector_id": "$COLLECTOR_NAME",
    "status": "online",
    "timestamp": "$(date -Iseconds)",
    "telemetry": {
        "cpu_percent": 10.5,
        "memory_percent": 25.3,
        "disk_percent": 35.2,
        "processes": 120
    },
    "capabilities": ["nmap", "nuclei"]
}
EOF
)

RESPONSE=$(curl -k -s -w "HTTP:%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$HEARTBEAT_DATA" \
    --cert "$COLLECTOR_DIR/certs/collector.crt" \
    --key "$COLLECTOR_DIR/certs/collector.key" \
    "$API_BASE_URL/collector-api/heartbeat" 2>/dev/null || echo "HTTP:000")

HTTP_CODE=$(echo "$RESPONSE" | grep -o "HTTP:[0-9]*" | cut -d: -f2)

if [[ "$HTTP_CODE" == "200" ]]; then
    log "✅ Endpoint heartbeat funcionando"
    echo "  Resposta: $(echo "$RESPONSE" | sed 's/HTTP:[0-9]*$//')"
else
    log "❌ Problema no endpoint heartbeat (HTTP $HTTP_CODE)"
fi

# 7. Verificar processo Python
log "7. Verificando processo collector..."
if pgrep -f "collector_agent.py" >/dev/null; then
    log "✅ Processo Python ativo"
    echo "  PID: $(pgrep -f collector_agent.py)"
else
    log "⚠️ Processo Python não encontrado"
fi

# 8. Corrigir endpoint no collector se necessário
log "8. Atualizando endpoint do heartbeat..."
if grep -q "/api/collectors/heartbeat" "$COLLECTOR_DIR/collector_agent.py" 2>/dev/null; then
    log "⚠️ Endpoint antigo detectado - corrigindo..."
    sed -i 's|/api/collectors/heartbeat|/collector-api/heartbeat|g' "$COLLECTOR_DIR/collector_agent.py"
    systemctl restart samureye-collector
    log "✅ Endpoint atualizado e serviço reiniciado"
fi

# 9. Verificar logs recentes
log "9. Verificando logs..."
if [[ -f /var/log/samureye-collector/agent.log ]]; then
    RECENT_ERRORS=$(tail -50 /var/log/samureye-collector/agent.log | grep -i "error\|failed\|warning" | wc -l)
    if [[ $RECENT_ERRORS -gt 0 ]]; then
        log "⚠️ $RECENT_ERRORS problemas nos logs recentes"
        echo "  Últimos problemas:"
        tail -20 /var/log/samureye-collector/agent.log | grep -i "error\|failed\|warning" | tail -3 | sed 's/^/    /'
    else
        log "✅ Logs sem problemas críticos"
    fi
else
    log "⚠️ Arquivo de log não encontrado"
fi

# 10. Status final
log "10. Status final:"
echo "  Serviço: $(systemctl is-active samureye-collector)"
echo "  Processo Python: $(pgrep -f collector_agent.py >/dev/null && echo 'running' || echo 'stopped')"
echo "  Último heartbeat: $(date)"

echo ""
log "✅ Verificação do Collector concluída"
echo ""
echo "🔍 Para executar correção completa:"
echo "  bash /tmp/install-vlxsam04.sh"
echo ""
echo "🔍 Comandos úteis:"
echo "  journalctl -u samureye-collector -f"
echo "  tail -f /var/log/samureye-collector/agent.log"
echo "  systemctl restart samureye-collector"
echo ""
echo "🔍 Teste manual de heartbeat:"
echo "  curl -X POST -H 'Content-Type: application/json' \\"
echo "    -d '{\"collector_id\":\"$COLLECTOR_NAME\",\"status\":\"online\"}' \\"
echo "    --cert $COLLECTOR_DIR/certs/collector.crt \\"
echo "    --key $COLLECTOR_DIR/certs/collector.key \\"
echo "    $API_BASE_URL/collector-api/heartbeat"
echo ""
echo "🌐 Verificar interface admin:"
echo "  1. https://app.samureye.com.br/admin"
echo "  2. Login: admin@samureye.com.br / SamurEye2024!"
echo "  3. Gestão de Coletores"