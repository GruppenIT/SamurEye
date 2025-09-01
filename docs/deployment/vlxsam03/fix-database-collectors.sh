#!/bin/bash

# vlxsam03 - Corrigir Banco para Collectors (Situação Real)
# Criar tabelas necessárias e otimizações

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-database-collectors.sh"
fi

echo "🗄️ vlxsam03 - CORRIGIR BANCO PARA COLLECTORS"
echo "============================================="
echo ""

# ============================================================================
# 1. VERIFICAR POSTGRESQL
# ============================================================================

log "🔍 Verificando PostgreSQL..."

if ! systemctl is-active --quiet postgresql; then
    error "PostgreSQL não está rodando"
fi

# Encontrar versão do PostgreSQL
PG_VERSION=$(sudo -u postgres psql -t -c "SELECT version();" | head -1 | grep -oP '\d+\.\d+' | head -1)
log "✅ PostgreSQL $PG_VERSION ativo"

# Testar conexão com banco samureye
if ! sudo -u postgres psql -d samureye -c "SELECT 1;" >/dev/null 2>&1; then
    error "Não é possível conectar ao banco samureye"
fi

log "✅ Conexão com banco samureye OK"

# ============================================================================
# 2. VERIFICAR E CRIAR TABELAS NECESSÁRIAS
# ============================================================================

log "📋 Verificando estrutura das tabelas..."

# Verificar quais tabelas existem
EXISTING_TABLES=$(sudo -u postgres psql -d samureye -t -c "
SELECT string_agg(tablename, ', ') 
FROM pg_tables 
WHERE schemaname = 'public';
" | tr -d ' ')

log "Tabelas existentes: $EXISTING_TABLES"

# Criar tabela collector_telemetry se não existir
sudo -u postgres psql samureye << 'EOF'
-- Criar tabela de telemetria se não existir
CREATE TABLE IF NOT EXISTS collector_telemetry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collector_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    cpu_usage DECIMAL(5,2),
    memory_usage DECIMAL(5,2),
    disk_usage DECIMAL(5,2),
    network_io JSONB,
    process_count INTEGER,
    additional_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Adicionar colunas na tabela collectors se não existirem
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'collectors' AND column_name = 'latest_telemetry') THEN
        ALTER TABLE collectors ADD COLUMN latest_telemetry JSONB;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'collectors' AND column_name = 'last_seen') THEN
        ALTER TABLE collectors ADD COLUMN last_seen TIMESTAMP WITH TIME ZONE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'collectors' AND column_name = 'heartbeat_interval') THEN
        ALTER TABLE collectors ADD COLUMN heartbeat_interval INTEGER DEFAULT 120;
    END IF;
END $$;

\echo 'Tabelas verificadas/criadas com sucesso'
EOF

log "✅ Estrutura de tabelas atualizada"

# ============================================================================
# 3. CRIAR ÍNDICES OTIMIZADOS
# ============================================================================

log "📊 Criando índices otimizados..."

sudo -u postgres psql samureye << 'EOF'
-- Índices para performance de consultas de telemetria
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_collector_telemetry_collector_timestamp 
ON collector_telemetry (collector_id, timestamp DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_collector_telemetry_timestamp 
ON collector_telemetry (timestamp DESC);

-- Índices para consultas de status dos collectors
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_collectors_status_last_seen 
ON collectors (status, last_seen DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_collectors_tenant_status 
ON collectors (tenant_id, status);

-- Índice para heartbeat lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_collectors_last_seen 
ON collectors (last_seen DESC) WHERE status = 'online';

\echo 'Índices otimizados criados'
EOF

log "✅ Índices criados"

# ============================================================================
# 4. FUNÇÕES DE LIMPEZA E MANUTENÇÃO
# ============================================================================

log "🧹 Criando funções de manutenção..."

sudo -u postgres psql samureye << 'EOF'
-- Função para limpar telemetria antiga
CREATE OR REPLACE FUNCTION cleanup_old_telemetry(days_to_keep INTEGER DEFAULT 7)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM collector_telemetry 
    WHERE timestamp < NOW() - (days_to_keep || ' days')::INTERVAL;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RAISE NOTICE 'Limpeza: % registros de telemetria removidos (>% dias)', deleted_count, days_to_keep;
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Função para atualizar status offline baseado em heartbeat
CREATE OR REPLACE FUNCTION update_offline_collectors(timeout_minutes INTEGER DEFAULT 5)
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE collectors 
    SET status = 'offline'
    WHERE status = 'online' 
    AND (last_seen IS NULL OR last_seen < NOW() - (timeout_minutes || ' minutes')::INTERVAL);
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    
    IF updated_count > 0 THEN
        RAISE NOTICE 'Status offline: % collectors atualizados (timeout: %min)', updated_count, timeout_minutes;
    END IF;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- Função para atualizar latest_telemetry nos collectors
CREATE OR REPLACE FUNCTION update_collector_latest_telemetry()
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER := 0;
    collector_record RECORD;
BEGIN
    FOR collector_record IN 
        SELECT DISTINCT collector_id FROM collector_telemetry
        WHERE timestamp > NOW() - INTERVAL '1 hour'
    LOOP
        UPDATE collectors 
        SET latest_telemetry = (
            SELECT jsonb_build_object(
                'cpuUsage', cpu_usage,
                'memoryUsage', memory_usage,
                'diskUsage', disk_usage,
                'networkIO', network_io,
                'processCount', process_count,
                'timestamp', timestamp
            )
            FROM collector_telemetry 
            WHERE collector_id = collector_record.collector_id
            ORDER BY timestamp DESC 
            LIMIT 1
        )
        WHERE id = collector_record.collector_id;
        
        updated_count := updated_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Latest telemetry: % collectors atualizados', updated_count;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

\echo 'Funções de manutenção criadas'
EOF

log "✅ Funções de manutenção criadas"

# ============================================================================
# 5. SCRIPT DE MANUTENÇÃO AUTOMÁTICA
# ============================================================================

log "⏰ Configurando manutenção automática..."

cat > /usr/local/bin/samureye-db-maintenance.sh << 'EOF'
#!/bin/bash

# Manutenção automática do banco SamurEye
LOG_FILE="/var/log/samureye-db-maintenance.log"

{
    echo "$(date): Iniciando manutenção automática do banco"
    
    # Atualizar status offline (collectors inativos > 5min)
    sudo -u postgres psql samureye -c "SELECT update_offline_collectors(5);" -t
    
    # Atualizar latest_telemetry
    sudo -u postgres psql samureye -c "SELECT update_collector_latest_telemetry();" -t
    
    # Limpeza de telemetria antiga (manter últimos 7 dias)
    sudo -u postgres psql samureye -c "SELECT cleanup_old_telemetry(7);" -t
    
    # Vacuum para otimizar performance
    sudo -u postgres psql samureye -c "VACUUM ANALYZE collector_telemetry, collectors;" -q
    
    echo "$(date): Manutenção automática concluída"
    
} >> "$LOG_FILE" 2>&1
EOF

chmod +x /usr/local/bin/samureye-db-maintenance.sh

# Adicionar ao cron para executar a cada 5 minutos
(crontab -l 2>/dev/null | grep -v samureye-db-maintenance; echo "*/5 * * * * /usr/local/bin/samureye-db-maintenance.sh") | crontab -

log "✅ Manutenção automática configurada (a cada 5 minutos)"

# ============================================================================
# 6. EXECUTAR PRIMEIRA MANUTENÇÃO
# ============================================================================

log "🔄 Executando primeira manutenção..."

/usr/local/bin/samureye-db-maintenance.sh

# ============================================================================
# 7. VERIFICAR DADOS DE TESTE
# ============================================================================

log "🧪 Verificando dados de collectors..."

sudo -u postgres psql samureye << 'EOF'
\echo 'Collectors cadastrados:'
SELECT 
    id,
    name,
    status,
    last_seen,
    CASE 
        WHEN latest_telemetry IS NOT NULL THEN 'Com telemetria'
        ELSE 'Sem telemetria'
    END as telemetry_status
FROM collectors
ORDER BY name;

\echo ''
\echo 'Telemetria recente (últimas 24h):'
SELECT 
    COUNT(*) as total_records,
    COUNT(DISTINCT collector_id) as collectors_with_data,
    MIN(timestamp) as oldest_record,
    MAX(timestamp) as newest_record
FROM collector_telemetry 
WHERE timestamp > NOW() - INTERVAL '24 hours';

\echo ''
\echo 'Estrutura da tabela collector_telemetry:'
\d collector_telemetry;
EOF

# ============================================================================
# 8. RESULTADO FINAL
# ============================================================================

echo ""
log "🎯 BANCO CORRIGIDO E OTIMIZADO"
echo "════════════════════════════════════════════════"
echo ""
echo "📊 TABELAS CRIADAS/VERIFICADAS:"
echo "   ✓ collector_telemetry - Dados de telemetria"
echo "   ✓ collectors - Atualizada com campos necessários"
echo ""
echo "🔧 FUNCIONALIDADES:"
echo "   ✓ Detecção automática offline (5min timeout)"
echo "   ✓ Limpeza automática telemetria (7 dias)"
echo "   ✓ Atualização latest_telemetry automática"
echo "   ✓ Índices otimizados para performance"
echo ""
echo "⏰ MANUTENÇÃO AUTOMÁTICA:"
echo "   ✓ Executa a cada 5 minutos via cron"
echo "   ✓ Log: /var/log/samureye-db-maintenance.log"
echo ""
echo "📝 MONITORAMENTO:"
echo "   • Logs: tail -f /var/log/samureye-db-maintenance.log"
echo "   • Status: sudo -u postgres psql samureye -c 'SELECT * FROM collectors;'"
echo ""
echo "💡 PRÓXIMO PASSO:"
echo "   Continuar com vlxsam02 (aplicação)"

exit 0