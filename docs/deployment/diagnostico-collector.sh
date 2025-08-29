#!/bin/bash
# Script de diagnóstico completo para Collector SamurEye

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔍 Diagnóstico Collector SamurEye - vlxsam04"
echo "==========================================="

# Definir variáveis
COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
API_BASE_URL="https://api.samureye.com.br"

# 1. Status do serviço
log "1. Verificando status do serviço..."
echo "Status systemd:"
systemctl status samureye-collector --no-pager -l || echo "Serviço não encontrado"

echo ""
echo "Processo Python:"
pgrep -f collector_agent.py || echo "Processo não encontrado"

# 2. Arquivos de configuração
log "2. Verificando arquivos de configuração..."
if [[ -f "$CONFIG_DIR/.env" ]]; then
    echo "✅ Arquivo .env encontrado:"
    source "$CONFIG_DIR/.env"
    echo "  COLLECTOR_NAME: $COLLECTOR_NAME"
    echo "  TENANT_SLUG: $TENANT_SLUG" 
    echo "  API_BASE_URL: $API_BASE_URL"
else
    echo "❌ Arquivo .env não encontrado: $CONFIG_DIR/.env"
fi

# 3. Certificados
log "3. Verificando certificados..."
CERT_FILES=(
    "$COLLECTOR_DIR/certs/collector.crt"
    "$COLLECTOR_DIR/certs/collector.key"
    "$COLLECTOR_DIR/certs/ca.crt"
)

for cert in "${CERT_FILES[@]}"; do
    if [[ -f "$cert" ]]; then
        echo "✅ $cert"
        if [[ "$cert" == *.crt ]]; then
            echo "  Validade: $(openssl x509 -in "$cert" -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2 || echo 'Erro ao verificar')"
        fi
    else
        echo "❌ $cert"
    fi
done

# 4. Conectividade
log "4. Testando conectividade..."

# DNS
if nslookup api.samureye.com.br >/dev/null 2>&1; then
    echo "✅ DNS: api.samureye.com.br resolve"
else
    echo "❌ DNS: Falha ao resolver api.samureye.com.br"
fi

# Porta 443
if nc -z api.samureye.com.br 443 2>/dev/null; then
    echo "✅ Conectividade: Porta 443 acessível"
else
    echo "❌ Conectividade: Porta 443 inacessível"
fi

# SSL básico
if curl -k -s --connect-timeout 5 "$API_BASE_URL/api/system/settings" | grep -q "systemName"; then
    echo "✅ API: Endpoint acessível sem certificado"
else
    echo "❌ API: Endpoint não acessível"
fi

# 5. Teste com certificados mTLS
log "5. Testando mTLS..."
if [[ -f "$COLLECTOR_DIR/certs/collector.crt" && -f "$COLLECTOR_DIR/certs/collector.key" ]]; then
    RESPONSE=$(curl -k -s -w "HTTP:%{http_code}" \
        --connect-timeout 10 \
        --cert "$COLLECTOR_DIR/certs/collector.crt" \
        --key "$COLLECTOR_DIR/certs/collector.key" \
        "$API_BASE_URL/api/system/settings" 2>/dev/null || echo "HTTP:000")
    
    HTTP_CODE=$(echo "$RESPONSE" | grep -o "HTTP:[0-9]*" | cut -d: -f2)
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "✅ mTLS: Autenticação funcionando (HTTP $HTTP_CODE)"
    else
        echo "❌ mTLS: Falha na autenticação (HTTP $HTTP_CODE)"
    fi
else
    echo "❌ mTLS: Certificados não encontrados"
fi

# 6. Teste do heartbeat
log "6. Testando endpoint heartbeat..."
HEARTBEAT_DATA=$(cat <<EOF
{
    "collector_id": "$COLLECTOR_NAME",
    "status": "online",
    "timestamp": "$(date -Iseconds)",
    "telemetry": {
        "cpu_percent": $(awk '{print $1}' /proc/loadavg | awk '{printf "%.1f", $1*100/4}'),
        "memory_percent": $(free | awk 'NR==2{printf "%.1f", $3*100/$2}'),
        "disk_percent": $(df / | awk 'NR==2{printf "%.1f", $5}' | tr -d '%'),
        "processes": $(ps aux | wc -l)
    },
    "capabilities": ["nmap", "nuclei", "masscan"]
}
EOF
)

if [[ -f "$COLLECTOR_DIR/certs/collector.crt" && -f "$COLLECTOR_DIR/certs/collector.key" ]]; then
    HEARTBEAT_RESPONSE=$(curl -k -s -w "HTTP:%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$HEARTBEAT_DATA" \
        --cert "$COLLECTOR_DIR/certs/collector.crt" \
        --key "$COLLECTOR_DIR/certs/collector.key" \
        "$API_BASE_URL/collector-api/heartbeat" 2>/dev/null || echo "HTTP:000")
    
    HEARTBEAT_CODE=$(echo "$HEARTBEAT_RESPONSE" | grep -o "HTTP:[0-9]*" | cut -d: -f2)
    if [[ "$HEARTBEAT_CODE" == "200" ]]; then
        echo "✅ Heartbeat: Endpoint funcionando (HTTP $HEARTBEAT_CODE)"
        echo "  Resposta: $(echo "$HEARTBEAT_RESPONSE" | sed 's/HTTP:[0-9]*$//')"
    else
        echo "❌ Heartbeat: Endpoint com problema (HTTP $HEARTBEAT_CODE)"
    fi
fi

# 7. Logs recentes
log "7. Logs recentes..."
if [[ -f "/var/log/samureye-collector/agent.log" ]]; then
    echo "Últimas 5 linhas do log:"
    tail -5 /var/log/samureye-collector/agent.log | sed 's/^/  /'
    
    echo ""
    echo "Erros recentes:"
    grep -i "error\|failed\|exception" /var/log/samureye-collector/agent.log | tail -3 | sed 's/^/  /' || echo "  Nenhum erro encontrado"
else
    echo "❌ Log não encontrado: /var/log/samureye-collector/agent.log"
fi

# 8. Status no banco de dados (consulta via API)
log "8. Verificando status na API..."
if [[ -f "$COLLECTOR_DIR/certs/collector.crt" && -f "$COLLECTOR_DIR/certs/collector.key" ]]; then
    # Não temos acesso direto ao banco, mas podemos tentar verificar via API
    echo "Consulta direta ao banco não disponível do collector"
    echo "Status deve ser verificado via interface web ou logs do vlxsam02"
fi

# 9. Informações do sistema
log "9. Informações do sistema..."
echo "Hostname: $(hostname)"
echo "IP Address: $(ip route get 8.8.8.8 | awk 'NR==1 {print $7}')"
echo "Uptime: $(uptime -p)"
echo "Carga: $(cat /proc/loadavg)"
echo "Memória: $(free -h | awk 'NR==2{printf "%s/%s (%.1f%%)", $3,$2,$3*100/$2}')"

echo ""
log "✅ Diagnóstico concluído"
echo ""
echo "🔧 Para corrigir problemas identificados:"
echo "  curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/install.sh | sudo bash"