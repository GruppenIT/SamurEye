#!/bin/bash
# Script para diagnosticar problema de heartbeat 404 do collector vlxsam04

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔍 Diagnóstico Heartbeat Collector vlxsam04"
echo "=========================================="

# Verificar qual collector_id está sendo enviado
log "📋 Verificando configuração do collector..."

if [ -f "/opt/samureye-collector/collector_agent.py" ]; then
    log "🔍 Analisando collector_agent.py..."
    
    # Procurar como o collector_id é gerado
    grep -n "collector_id" /opt/samureye-collector/collector_agent.py | head -5
    
    echo ""
    log "🆔 Método de geração do collector_id:"
    grep -A 5 "_get_collector_id" /opt/samureye-collector/collector_agent.py || echo "Método não encontrado"
fi

# Verificar se existe arquivo de configuração
if [ -f "/etc/samureye-collector/config.yaml" ]; then
    log "⚙️ Configuração atual:"
    cat /etc/samureye-collector/config.yaml
else
    log "⚠️ Arquivo de configuração não encontrado"
fi

# Verificar logs recentes para ver exatamente o que está sendo enviado
log "📝 Últimas tentativas de heartbeat nos logs:"
journalctl -u samureye-collector --since "5 minutes ago" | grep -E "(heartbeat|404|collector_id)" | tail -10

echo ""
log "🔬 Teste manual do endpoint heartbeat..."

# Testar endpoint heartbeat com diferentes IDs
HEARTBEAT_URL="https://api.samureye.com.br/collector-api/heartbeat"

echo ""
log "📡 Testando heartbeat com ID 'vlxsam04':"
curl -k -X POST "$HEARTBEAT_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "collector_id": "vlxsam04",
        "status": "online",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }' \
    -w "\nHTTP Status: %{http_code}\n" 2>/dev/null

echo ""
log "📡 Testando heartbeat com ID 'vlxsam04-collector-id':"
curl -k -X POST "$HEARTBEAT_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "collector_id": "vlxsam04-collector-id",
        "status": "online", 
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }' \
    -w "\nHTTP Status: %{http_code}\n" 2>/dev/null

echo ""
log "🗃️ Verificando collectors registrados no banco..."

# Conectar ao PostgreSQL e verificar collectors
if ping -c 1 vlxsam03 >/dev/null 2>&1; then
    PGPASSWORD='SamurEye2024!' psql -h vlxsam03 -U samureye -d samureye << 'SQL'
-- Mostrar todos os collectors cadastrados
SELECT 
    id,
    name,
    tenant_id,
    status,
    created_at,
    last_seen
FROM collectors 
ORDER BY created_at DESC;

-- Procurar especificamente por vlxsam04
SELECT 
    'Found by name' as search_type,
    id, name, tenant_id, status
FROM collectors 
WHERE name LIKE '%vlxsam04%'

UNION ALL

SELECT 
    'Found by id' as search_type,
    id, name, tenant_id, status  
FROM collectors
WHERE id LIKE '%vlxsam04%';
SQL
else
    log "⚠️ vlxsam03 não acessível - não foi possível verificar banco"
fi

echo ""
log "💡 DICAS PARA RESOLVER:"
echo "====================="
echo "1. Se não aparecer nenhum collector no banco:"
echo "   - Execute: /usr/local/bin/fix-enrolling-collectors.sh no vlxsam03"
echo "   - Ou insira manualmente no banco"
echo ""
echo "2. Se o collector_id não coincidir:"
echo "   - Verifique o ID sendo enviado nos logs"
echo "   - Atualize configuração em /etc/samureye-collector/config.yaml"
echo "   - Reinicie o collector: systemctl restart samureye-collector"
echo ""
echo "3. Para forçar registro:"
echo "   - POST para endpoint com collector_id correto"
echo "   - Verificar se tenant_id existe no banco"

exit 0