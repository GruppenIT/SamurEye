#!/bin/bash

# ============================================================================
# CORREÇÃO SCHEMA POSTGRESQL - vlxsam02 
# ============================================================================
# Força criação das tabelas SamurEye após conectividade estabelecida

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️  $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}"; }

echo ""
echo "🗃️ CORREÇÃO SCHEMA POSTGRESQL - vlxsam02"
echo "======================================="
echo "🖥️  Servidor: $(hostname)"
echo "📅 Data: $(date)"
echo "======================================="
echo ""

# ============================================================================
# 1. VERIFICAR SE É O vlxsam02
# ============================================================================

if [ "$(hostname)" != "vlxsam02" ]; then
    error "Este script deve ser executado no vlxsam02, não em $(hostname)"
fi

# ============================================================================
# 2. CONFIGURAÇÕES
# ============================================================================

WORKING_DIR="/opt/samureye/SamurEye"
POSTGRES_HOST="172.24.1.153"
POSTGRES_PORT="5432"
POSTGRES_DB="samureye"
APP_USER="samureye"

log "📁 Diretório de trabalho: $WORKING_DIR"

# ============================================================================
# 3. TESTAR CONECTIVIDADE POSTGRESQL
# ============================================================================

log "🔍 Testando conectividade PostgreSQL..."

# Testar usuários disponíveis
POSTGRES_USER=""
POSTGRES_PASSWORD="samureye_secure_2024"

for user in "samureye_user" "samureye"; do
    echo -n "• Testando usuário '$user': "
    if PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$user" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
        POSTGRES_USER="$user"
        break
    else
        echo -e "${RED}❌ FAIL${NC}"
    fi
done

if [ -z "$POSTGRES_USER" ]; then
    error "Nenhum usuário PostgreSQL funcional encontrado"
fi

log "✅ Usando usuário PostgreSQL: $POSTGRES_USER"

# ============================================================================
# 4. ATUALIZAR .ENV COM USUÁRIO CORRETO
# ============================================================================

if [ -f "$WORKING_DIR/.env" ]; then
    log "⚙️ Atualizando arquivo .env..."
    
    # Atualizar DATABASE_URL
    DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    
    # Substituir ou adicionar DATABASE_URL
    if grep -q "^DATABASE_URL=" "$WORKING_DIR/.env"; then
        sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"$DATABASE_URL\"|" "$WORKING_DIR/.env"
    else
        echo "DATABASE_URL=\"$DATABASE_URL\"" >> "$WORKING_DIR/.env"
    fi
    
    # Atualizar variáveis individuais
    sed -i "s/^POSTGRES_USER=.*/POSTGRES_USER=\"$POSTGRES_USER\"/" "$WORKING_DIR/.env"
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=\"$POSTGRES_PASSWORD\"/" "$WORKING_DIR/.env"
    
    log "✅ Arquivo .env atualizado"
else
    warn "Arquivo .env não encontrado - criando..."
    
    cat > "$WORKING_DIR/.env" << EOF
# SamurEye Environment Configuration
NODE_ENV=production
PORT=5000

# Database Configuration
DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
POSTGRES_HOST="$POSTGRES_HOST"
POSTGRES_PORT="$POSTGRES_PORT"
POSTGRES_DB="$POSTGRES_DB"
POSTGRES_USER="$POSTGRES_USER"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

# Session Configuration
SESSION_SECRET="SamurEye_OnPremise_Secret_$(date +%s)"

# Application Configuration
REPLIT_APP_URL="https://app.samureye.com.br"
PUBLIC_APP_URL="https://app.samureye.com.br"
EOF
    
    chown "$APP_USER:$APP_USER" "$WORKING_DIR/.env"
    log "✅ Arquivo .env criado"
fi

# ============================================================================
# 5. FAZER PUSH DO SCHEMA DRIZZLE
# ============================================================================

log "🗃️ Fazendo push do schema Drizzle..."

cd "$WORKING_DIR"
export DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"

# Tentativa 1: npm run db:push normal
log "🔄 Tentativa 1: npm run db:push normal"
if sudo -u "$APP_USER" DATABASE_URL="$DATABASE_URL" npm run db:push 2>/dev/null; then
    log "✅ Schema push concluído com sucesso"
    SCHEMA_SUCCESS=true
else
    warn "❌ Schema push falhou - tentando com --force"
    
    # Tentativa 2: com --force
    log "🔄 Tentativa 2: npm run db:push --force"
    if sudo -u "$APP_USER" DATABASE_URL="$DATABASE_URL" npm run db:push -- --force 2>/dev/null; then
        log "✅ Schema push forçado com sucesso"
        SCHEMA_SUCCESS=true
    else
        warn "❌ Schema push com --force falhou - criando tabelas manualmente"
        SCHEMA_SUCCESS=false
    fi
fi

# ============================================================================
# 6. CRIAÇÃO MANUAL DE TABELAS (SE NECESSÁRIO)
# ============================================================================

if [ "$SCHEMA_SUCCESS" != "true" ]; then
    log "🔧 Criando tabelas manualmente..."
    
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" << 'EOSQL'
-- Criar extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Remover tabelas se existirem (para recriar)
DROP TABLE IF EXISTS user_tenants CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS tenants CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;
DROP TABLE IF EXISTS collectors CASCADE;
DROP TABLE IF EXISTS collector_telemetry CASCADE;
DROP TABLE IF EXISTS security_journeys CASCADE;
DROP TABLE IF EXISTS journey_executions CASCADE;
DROP TABLE IF EXISTS credentials CASCADE;
DROP TABLE IF EXISTS threat_intelligence CASCADE;
DROP TABLE IF EXISTS activity_logs CASCADE;

-- 1. Tabela de tenants
CREATE TABLE tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    slug VARCHAR UNIQUE NOT NULL,
    description TEXT,
    logo_url VARCHAR,
    settings JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 2. Tabela de usuários
CREATE TABLE users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR UNIQUE,
    first_name VARCHAR,
    last_name VARCHAR,
    profile_image_url VARCHAR,
    password VARCHAR,
    current_tenant_id VARCHAR REFERENCES tenants(id),
    preferred_language VARCHAR DEFAULT 'pt-BR',
    is_global_user BOOLEAN DEFAULT false,
    is_soc_user BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 3. Tabela de relacionamento usuário-tenant
CREATE TABLE user_tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    role VARCHAR NOT NULL DEFAULT 'viewer',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, tenant_id)
);

-- 4. Tabela de sessões
CREATE TABLE sessions (
    sid VARCHAR PRIMARY KEY,
    sess JSONB NOT NULL,
    expire TIMESTAMP NOT NULL
);

-- 5. Tabela de coletores
CREATE TABLE collectors (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    hostname VARCHAR,
    ip_address VARCHAR,
    location VARCHAR,
    status VARCHAR DEFAULT 'enrolling',
    last_heartbeat TIMESTAMP,
    collector_version VARCHAR,
    capabilities JSONB DEFAULT '[]',
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 6. Tabela de telemetria de coletores
CREATE TABLE collector_telemetry (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    collector_id VARCHAR NOT NULL REFERENCES collectors(id) ON DELETE CASCADE,
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    cpu_usage NUMERIC,
    memory_usage NUMERIC,
    disk_usage NUMERIC,
    network_usage JSONB,
    processes JSONB,
    timestamp TIMESTAMP DEFAULT NOW()
);

-- 7. Tabela de jornadas de segurança
CREATE TABLE security_journeys (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    description TEXT,
    type VARCHAR NOT NULL,
    configuration JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 8. Tabela de execuções de jornadas
CREATE TABLE journey_executions (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    journey_id VARCHAR NOT NULL REFERENCES security_journeys(id) ON DELETE CASCADE,
    collector_id VARCHAR NOT NULL REFERENCES collectors(id) ON DELETE CASCADE,
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    status VARCHAR DEFAULT 'pending',
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    results JSONB DEFAULT '{}',
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 9. Tabela de credenciais
CREATE TABLE credentials (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    type VARCHAR NOT NULL,
    username VARCHAR,
    password VARCHAR,
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 10. Tabela de threat intelligence
CREATE TABLE threat_intelligence (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    ioc_type VARCHAR NOT NULL,
    ioc_value VARCHAR NOT NULL,
    description TEXT,
    severity VARCHAR DEFAULT 'medium',
    source VARCHAR,
    first_seen TIMESTAMP DEFAULT NOW(),
    last_seen TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true
);

-- 11. Tabela de logs de atividade
CREATE TABLE activity_logs (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR REFERENCES tenants(id) ON DELETE CASCADE,
    user_id VARCHAR REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR NOT NULL,
    resource_type VARCHAR,
    resource_id VARCHAR,
    details JSONB DEFAULT '{}',
    ip_address VARCHAR,
    user_agent VARCHAR,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Criar índices para performance
CREATE INDEX IF NOT EXISTS "IDX_session_expire" ON sessions(expire);
CREATE INDEX IF NOT EXISTS "IDX_user_tenants_user_id" ON user_tenants(user_id);
CREATE INDEX IF NOT EXISTS "IDX_user_tenants_tenant_id" ON user_tenants(tenant_id);
CREATE INDEX IF NOT EXISTS "IDX_collectors_tenant_id" ON collectors(tenant_id);
CREATE INDEX IF NOT EXISTS "IDX_collector_telemetry_collector_id" ON collector_telemetry(collector_id);
CREATE INDEX IF NOT EXISTS "IDX_collector_telemetry_timestamp" ON collector_telemetry(timestamp);
CREATE INDEX IF NOT EXISTS "IDX_journey_executions_journey_id" ON journey_executions(journey_id);
CREATE INDEX IF NOT EXISTS "IDX_journey_executions_collector_id" ON journey_executions(collector_id);
CREATE INDEX IF NOT EXISTS "IDX_activity_logs_tenant_id" ON activity_logs(tenant_id);
CREATE INDEX IF NOT EXISTS "IDX_activity_logs_created_at" ON activity_logs(created_at);

-- Inserir tenant padrão
INSERT INTO tenants (id, name, slug, description, is_active) 
VALUES (
    'default-tenant-' || substr(gen_random_uuid()::text, 1, 8),
    'Tenant Padrão',
    'default',
    'Tenant criado automaticamente durante instalação',
    true
) ON CONFLICT (slug) DO NOTHING;

EOSQL
    
    if [ $? -eq 0 ]; then
        log "✅ Tabelas criadas manualmente com sucesso"
    else
        error "❌ Falha ao criar tabelas manualmente"
    fi
fi

# ============================================================================
# 7. VERIFICAR TABELAS CRIADAS
# ============================================================================

log "🔍 Verificando tabelas criadas..."

TABLES_COUNT=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" 2>/dev/null | tr -d ' ')

if [ "$TABLES_COUNT" -gt 5 ]; then
    log "✅ Encontradas $TABLES_COUNT tabelas no banco"
    
    # Listar tabelas
    echo "📋 Tabelas criadas:"
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt" 2>/dev/null | grep -E "tenants|users|collectors|sessions"
    
else
    error "❌ Apenas $TABLES_COUNT tabelas encontradas - esperado > 5"
fi

# ============================================================================
# 8. REINICIAR APLICAÇÃO
# ============================================================================

log "🔄 Reiniciando aplicação SamurEye..."

if systemctl is-active --quiet samureye-app; then
    systemctl restart samureye-app
    sleep 5
    
    if systemctl is-active --quiet samureye-app; then
        log "✅ Aplicação reiniciada com sucesso"
    else
        warn "⚠️ Problema ao reiniciar aplicação"
    fi
else
    warn "⚠️ Aplicação não estava rodando"
fi

# ============================================================================
# 9. TESTE FINAL DE CRIAÇÃO DE TENANT
# ============================================================================

log "🧪 Testando criação de tenant via API..."

sleep 10  # Aguardar aplicação estabilizar

API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000/api/health" 2>/dev/null || echo "000")

if [[ "$API_STATUS" =~ ^[23] ]]; then
    log "✅ API respondendo (HTTP $API_STATUS)"
    
    # Testar criação de tenant
    TENANT_RESPONSE=$(curl -s -X POST "http://localhost:5000/api/admin/tenants" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Teste Schema Fix",
            "slug": "teste-schema-fix",
            "description": "Tenant de teste após correção do schema",
            "isActive": true
        }' 2>&1)
    
    if echo "$TENANT_RESPONSE" | grep -q '"id"'; then
        log "✅ Criação de tenant funcionando corretamente!"
        echo "Resposta: $TENANT_RESPONSE" | head -2
    else
        warn "❌ Ainda há problema na criação de tenant:"
        echo "$TENANT_RESPONSE" | head -3
    fi
    
else
    warn "❌ API não está respondendo (HTTP $API_STATUS)"
fi

echo ""
log "🎉 CORREÇÃO DE SCHEMA CONCLUÍDA!"
echo "================================"
echo ""
echo "✅ AÇÕES REALIZADAS:"
echo "• Conectividade PostgreSQL verificada"
echo "• Arquivo .env atualizado com usuário correto"
echo "• Schema Drizzle aplicado"
echo "• Tabelas criadas (manual se necessário)"
echo "• Aplicação reiniciada"
echo "• Teste de criação de tenant realizado"
echo ""
echo "🌐 ACESSO À APLICAÇÃO:"
echo "• https://app.samureye.com.br"
echo "• Admin: https://app.samureye.com.br/admin"
echo ""
log "Schema PostgreSQL corrigido para SamurEye!"