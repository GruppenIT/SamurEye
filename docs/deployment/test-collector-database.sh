#!/bin/bash
# Script para testar collector no banco de dados PostgreSQL

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔍 Teste Collector Database - vlxsam03"
echo "===================================="

# Verificar se PostgreSQL está ativo
if ! systemctl is-active postgresql >/dev/null 2>&1; then
    log "❌ PostgreSQL não está ativo"
    exit 1
fi

log "✅ PostgreSQL ativo"

# 1. Verificar se existe a tabela collectors
log "1. Verificando tabela collectors..."
TABLE_EXISTS=$(sudo -u postgres psql -d samureye -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'collectors');" 2>/dev/null | tr -d ' ')

if [[ "$TABLE_EXISTS" == "t" ]]; then
    log "✅ Tabela 'collectors' existe"
else
    log "❌ Tabela 'collectors' não existe"
    exit 1
fi

# 2. Listar estrutura da tabela
log "2. Estrutura da tabela collectors:"
sudo -u postgres psql -d samureye -c "\d collectors" 2>/dev/null || log "❌ Erro ao mostrar estrutura"

# 3. Contar collectors por status
log "3. Status dos collectors:"
sudo -u postgres psql -d samureye -c "
SELECT 
    status,
    COUNT(*) as quantidade,
    MAX(last_seen) as ultimo_visto
FROM collectors 
GROUP BY status 
ORDER BY status;
" 2>/dev/null || log "❌ Erro na consulta de status"

# 4. Mostrar todos os collectors
log "4. Lista completa de collectors:"
sudo -u postgres psql -d samureye -c "
SELECT 
    name,
    status,
    created_at,
    last_seen,
    tenant_id
FROM collectors 
ORDER BY created_at DESC;
" 2>/dev/null || log "❌ Erro na consulta de collectors"

# 5. Verificar se vlxsam04 está registrado
log "5. Procurando collector vlxsam04..."
VLXSAM04_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE name LIKE '%vlxsam04%';" 2>/dev/null | tr -d ' ')

if [[ "$VLXSAM04_COUNT" -gt 0 ]]; then
    log "✅ Collector vlxsam04 encontrado ($VLXSAM04_COUNT registros)"
    
    # Mostrar detalhes do vlxsam04
    sudo -u postgres psql -d samureye -c "
    SELECT 
        id,
        name,
        status,
        created_at,
        last_seen,
        tenant_id,
        endpoint,
        capabilities
    FROM collectors 
    WHERE name LIKE '%vlxsam04%';
    " 2>/dev/null
else
    log "❌ Collector vlxsam04 não encontrado"
fi

# 6. Verificar últimos heartbeats (se existir tabela de telemetria)
log "6. Verificando telemetria recente..."
TELEMETRY_EXISTS=$(sudo -u postgres psql -d samureye -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'collector_telemetry');" 2>/dev/null | tr -d ' ')

if [[ "$TELEMETRY_EXISTS" == "t" ]]; then
    log "✅ Tabela 'collector_telemetry' existe"
    
    RECENT_TELEMETRY=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collector_telemetry WHERE timestamp > NOW() - INTERVAL '10 minutes';" 2>/dev/null | tr -d ' ')
    log "📊 Telemetria recente (10min): $RECENT_TELEMETRY registros"
    
    # Mostrar últimas 5 entradas de telemetria
    sudo -u postgres psql -d samureye -c "
    SELECT 
        collector_id,
        timestamp,
        cpu_percent,
        memory_percent,
        disk_percent
    FROM collector_telemetry 
    ORDER BY timestamp DESC 
    LIMIT 5;
    " 2>/dev/null || log "⚠️ Sem telemetria recente"
else
    log "⚠️ Tabela 'collector_telemetry' não existe"
fi

echo ""
log "✅ Teste de database concluído"
echo ""
echo "🔧 Se vlxsam04 não aparece como registrado:"
echo "  1. Execute no vlxsam04: systemctl restart samureye-collector"
echo "  2. Verifique logs: journalctl -u samureye-collector -f"
echo "  3. Teste heartbeat manual:"
echo "     curl -k -X POST -H 'Content-Type: application/json' \\"
echo "       --cert /opt/samureye-collector/certs/collector.crt \\"
echo "       --key /opt/samureye-collector/certs/collector.key \\"
echo "       -d '{\"collector_id\":\"vlxsam04\",\"status\":\"online\"}' \\"
echo "       https://api.samureye.com.br/collector-api/heartbeat"