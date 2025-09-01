#!/bin/bash

# vlxsam03 - Otimizar Banco para Melhorias dos Collectors
# Otimiza queries de telemetria e status de collectors

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./optimize-database.sh"
fi

echo "🗄️ vlxsam03 - OTIMIZAR BANCO PARA COLLECTORS"
echo "============================================="
echo "Otimizações para melhorias dos collectors:"
echo "1. Índices para consultas de telemetria"
echo "2. Limpeza automática de dados antigos"
echo "3. Otimização de queries de status"
echo ""

# Verificar se PostgreSQL está rodando
if ! systemctl is-active --quiet postgresql; then
    error "PostgreSQL não está rodando"
fi

log "✅ PostgreSQL está ativo"

# ============================================================================
# 1. CONECTAR E VERIFICAR BANCO
# ============================================================================

log "🔍 Verificando banco de dados..."

# Executar como usuário postgres
sudo -u postgres psql -c "SELECT version();" samureye >/dev/null 2>&1 || error "Não é possível conectar ao banco samureye"

log "✅ Conexão com banco OK"

# ============================================================================
# 2. CRIAR ÍNDICES PARA TELEMETRIA
# ============================================================================

log "📊 Criando índices otimizados para telemetria..."

sudo -u postgres psql samureye << 'EOF'
-- Índice para buscar telemetria mais recente por collector
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_collector_telemetry_collector_timestamp 
ON collector_telemetry (collector_id, timestamp DESC);

-- Índice para consultas de status dos collectors
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_collectors_status_last_seen 
ON collectors (status, last_seen DESC);

-- Índice para heartbeats por tenant
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_collectors_tenant_status 
ON collectors (tenant_id, status, last_seen DESC);

\echo 'Índices criados com sucesso'
EOF

log "✅ Índices de telemetria criados"

# ============================================================================
# 3. PROCEDIMENTO DE LIMPEZA AUTOMÁTICA
# ============================================================================

log "🧹 Criando procedimento de limpeza automática..."

sudo -u postgres psql samureye << 'EOF'
-- Função para limpar telemetria antiga (manter últimos 7 dias)
CREATE OR REPLACE FUNCTION cleanup_old_telemetry()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM collector_telemetry 
    WHERE timestamp < NOW() - INTERVAL '7 days';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RAISE NOTICE 'Limpeza automática: % registros de telemetria removidos', deleted_count;
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Função para atualizar status offline de collectors inativos
CREATE OR REPLACE FUNCTION update_offline_collectors()
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE collectors 
    SET status = 'offline'
    WHERE status = 'online' 
    AND (last_seen IS NULL OR last_seen < NOW() - INTERVAL '5 minutes');
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    
    RAISE NOTICE 'Status offline: % collectors atualizados', updated_count;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

\echo 'Funções de limpeza criadas'
EOF

log "✅ Funções de limpeza criadas"

# ============================================================================
# 4. CONFIGURAR CRON JOBS
# ============================================================================

log "⏰ Configurando tarefas automáticas..."

# Criar script de manutenção
cat > /usr/local/bin/samureye-db-maintenance.sh << 'EOF'
#!/bin/bash

# Manutenção automática do banco SamurEye
LOG_FILE="/var/log/samureye-db-maintenance.log"

{
    echo "$(date): Iniciando manutenção automática"
    
    # Limpeza de telemetria antiga
    sudo -u postgres psql samureye -c "SELECT cleanup_old_telemetry();" -t
    
    # Atualizar status offline
    sudo -u postgres psql samureye -c "SELECT update_offline_collectors();" -t
    
    # Vacuum para otimizar tabelas
    sudo -u postgres psql samureye -c "VACUUM ANALYZE collector_telemetry, collectors;"
    
    echo "$(date): Manutenção concluída"
    
} >> "$LOG_FILE" 2>&1
EOF

chmod +x /usr/local/bin/samureye-db-maintenance.sh

# Adicionar ao cron (executa a cada hora)
(crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/samureye-db-maintenance.sh") | crontab -

log "✅ Cron job configurado para manutenção automática"

# ============================================================================
# 5. OTIMIZAR CONFIGURAÇÃO POSTGRESQL
# ============================================================================

log "⚙️ Otimizando configuração do PostgreSQL..."

# Backup da configuração atual
cp /etc/postgresql/*/main/postgresql.conf /etc/postgresql/*/main/postgresql.conf.backup.$(date +%Y%m%d)

# Otimizações específicas para workload do SamurEye
POSTGRES_CONF=$(find /etc/postgresql -name "postgresql.conf" | head -1)

if [ -f "$POSTGRES_CONF" ]; then
    # Configurações para melhor performance com telemetria frequente
    cat >> "$POSTGRES_CONF" << 'EOF'

# SamurEye Collector Optimizations
# Para workload com muitos INSERTs de telemetria

# Aumentar buffer pool para cache
shared_buffers = 256MB

# Otimizar para escritas frequentes
wal_buffers = 16MB
checkpoint_completion_target = 0.9

# Melhorar performance de consultas
effective_cache_size = 1GB
random_page_cost = 1.1

# Configurações para telemetria
max_connections = 200
work_mem = 4MB

# Log slow queries (> 1 segundo)
log_min_duration_statement = 1000
EOF

    log "✅ Configuração do PostgreSQL otimizada"
    
    # Reiniciar PostgreSQL para aplicar mudanças
    systemctl restart postgresql
    
    sleep 5
    
    if systemctl is-active --quiet postgresql; then
        log "✅ PostgreSQL reiniciado com sucesso"
    else
        error "Falha ao reiniciar PostgreSQL"
    fi
else
    warn "Arquivo de configuração do PostgreSQL não encontrado"
fi

# ============================================================================
# 6. EXECUTAR PRIMEIRA MANUTENÇÃO
# ============================================================================

log "🔄 Executando primeira manutenção..."

/usr/local/bin/samureye-db-maintenance.sh

# ============================================================================
# 7. VERIFICAÇÃO E ESTATÍSTICAS
# ============================================================================

log "📊 Coletando estatísticas do banco..."

sudo -u postgres psql samureye << 'EOF'
\echo 'Estatísticas dos Collectors:'
SELECT 
    COUNT(*) as total_collectors,
    COUNT(CASE WHEN status = 'online' THEN 1 END) as online,
    COUNT(CASE WHEN status = 'offline' THEN 1 END) as offline,
    COUNT(CASE WHEN status = 'enrolling' THEN 1 END) as enrolling
FROM collectors;

\echo ''
\echo 'Telemetria (últimas 24h):'
SELECT 
    COUNT(*) as total_records,
    COUNT(DISTINCT collector_id) as collectors_with_data,
    MIN(timestamp) as oldest_record,
    MAX(timestamp) as newest_record
FROM collector_telemetry 
WHERE timestamp > NOW() - INTERVAL '24 hours';

\echo ''
\echo 'Índices criados:'
SELECT schemaname, tablename, indexname 
FROM pg_indexes 
WHERE tablename IN ('collectors', 'collector_telemetry')
AND indexname LIKE '%collector%';
EOF

# ============================================================================
# 8. RESULTADO FINAL
# ============================================================================

echo ""
log "🎯 OTIMIZAÇÕES APLICADAS COM SUCESSO"
echo "════════════════════════════════════════════════"
echo ""
echo "📊 MELHORIAS IMPLEMENTADAS:"
echo "   ✓ Índices otimizados para queries de telemetria"
echo "   ✓ Limpeza automática de dados antigos (7 dias)"
echo "   ✓ Detecção automática de collectors offline (5min)"
echo "   ✓ Configuração PostgreSQL otimizada"
echo "   ✓ Manutenção automática via cron (a cada hora)"
echo ""
echo "📝 ARQUIVOS CRIADOS:"
echo "   • /usr/local/bin/samureye-db-maintenance.sh"
echo "   • /var/log/samureye-db-maintenance.log"
echo ""
echo "⏰ TAREFAS AUTOMÁTICAS:"
echo "   • Limpeza telemetria: A cada hora"
echo "   • Update status offline: A cada hora"
echo "   • VACUUM tabelas: A cada hora"
echo ""
echo "📊 MONITORAMENTO:"
echo "   • Logs: tail -f /var/log/samureye-db-maintenance.log"
echo "   • Status cron: systemctl status cron"
echo ""
echo "💡 PRÓXIMOS PASSOS:"
echo "   1. Aplicar melhorias no vlxsam02"
echo "   2. Testar interface com dados otimizados"
echo "   3. Monitorar performance das queries"

exit 0