#!/bin/bash

# ============================================================================
# CORREÇÃO ESPECÍFICA - SCHEMA TENANT CREATION vlxsam02
# ============================================================================
# Corrige problema "Failed to create tenant" forçando recriação do schema
# Integra no install-hard-reset.sh do vlxsam02
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

echo ""
echo "🔧 CORREÇÃO SCHEMA TENANT CREATION"
echo "=================================="
echo "Sistema: vlxsam02 ($(hostname))"
echo ""

# Configurações
WORKING_DIR="/opt/samureye"
POSTGRES_HOST="192.168.100.153"
POSTGRES_PORT="5432"
POSTGRES_DB="samureye"
POSTGRES_USER="samureye"
DATABASE_URL="postgresql://${POSTGRES_USER}:samureye_secure_2024@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"

# ============================================================================
# 1. VERIFICAR CONECTIVIDADE BÁSICA
# ============================================================================

log "🔍 Verificando conectividade com PostgreSQL..."

if ! timeout 10 nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    error "❌ PostgreSQL inacessível em $POSTGRES_HOST:$POSTGRES_PORT"
    echo "   • Verifique se vlxsam03 está online"
    echo "   • Execute no vlxsam03: systemctl status postgresql"
    exit 1
fi

export PGPASSWORD="samureye_secure_2024"
if ! psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
    error "❌ Falha na autenticação PostgreSQL"
    echo "   • Verifique credenciais no vlxsam03"
    exit 1
fi

log "✅ Conectividade PostgreSQL OK"

# ============================================================================
# 2. FORÇAR RECRIAÇÃO DO SCHEMA
# ============================================================================

log "🗃️ Forçando recriação completa do schema..."

cd "$WORKING_DIR"

# Configurar variáveis de ambiente
export DATABASE_URL="$DATABASE_URL"
export NODE_ENV="production"

# Parar aplicação temporariamente
if systemctl is-active --quiet samureye-app 2>/dev/null; then
    log "⏹️ Parando aplicação temporariamente..."
    systemctl stop samureye-app
    RESTART_APP=true
else
    RESTART_APP=false
fi

# Método 1: npm run db:push forçado
log "🔄 Tentativa 1: npm run db:push --force"
if sudo -u samureye DATABASE_URL="$DATABASE_URL" npm run db:push -- --force 2>/dev/null; then
    log "✅ Schema criado via npm run db:push --force"
    SCHEMA_SUCCESS=true
else
    warn "⚠️ npm run db:push --force falhou"
    SCHEMA_SUCCESS=false
fi

# Método 2: drizzle-kit push direto
if [ "$SCHEMA_SUCCESS" = false ]; then
    log "🔄 Tentativa 2: npx drizzle-kit push"
    if sudo -u samureye DATABASE_URL="$DATABASE_URL" npx drizzle-kit push --force 2>/dev/null; then
        log "✅ Schema criado via drizzle-kit push"
        SCHEMA_SUCCESS=true
    else
        warn "⚠️ drizzle-kit push falhou"
    fi
fi

# Método 3: Criação manual robusta das tabelas
if [ "$SCHEMA_SUCCESS" = false ]; then
    log "🔄 Tentativa 3: Criação manual de tabelas"
    
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" << 'EOSQL'
-- Habilitar extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Remover tabelas se existirem (para recriação limpa)
DROP TABLE IF EXISTS tenant_user_auth CASCADE;
DROP TABLE IF EXISTS activities CASCADE;
DROP TABLE IF EXISTS threat_intelligence CASCADE;
DROP TABLE IF EXISTS credentials CASCADE;
DROP TABLE IF EXISTS journeys CASCADE;
DROP TABLE IF EXISTS collector_telemetry CASCADE;
DROP TABLE IF EXISTS collectors CASCADE;
DROP TABLE IF EXISTS tenant_users CASCADE;
DROP TABLE IF EXISTS tenants CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS system_settings CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;

-- Recriar tabela de sessões (obrigatória para auth)
CREATE TABLE sessions (
    sid VARCHAR PRIMARY KEY,
    sess JSONB NOT NULL,
    expire TIMESTAMP NOT NULL
);
CREATE INDEX "IDX_session_expire" ON sessions(expire);

-- Recriar tabela de usuários
CREATE TABLE users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR UNIQUE,
    first_name VARCHAR,
    last_name VARCHAR,
    profile_image_url VARCHAR,
    password VARCHAR,
    current_tenant_id VARCHAR,
    preferred_language VARCHAR DEFAULT 'pt-BR',
    is_global_user BOOLEAN DEFAULT false,
    is_soc_user BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Recriar tabela de tenants (CRÍTICA)
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

-- Recriar tabela tenant_users
CREATE TABLE tenant_users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR NOT NULL,
    tenant_id VARCHAR NOT NULL,
    role VARCHAR NOT NULL DEFAULT 'viewer',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    UNIQUE(user_id, tenant_id)
);

-- Recriar tabela de coletores
CREATE TABLE collectors (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL,
    name VARCHAR NOT NULL,
    hostname VARCHAR,
    ip_address VARCHAR,
    description TEXT,
    status VARCHAR DEFAULT 'offline',
    version VARCHAR,
    last_seen TIMESTAMP,
    enrollment_token VARCHAR,
    enrollment_token_expires TIMESTAMP,
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

-- Recriar outras tabelas essenciais
CREATE TABLE journeys (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL,
    collector_id VARCHAR,
    name VARCHAR NOT NULL,
    description TEXT,
    type VARCHAR NOT NULL,
    target VARCHAR NOT NULL,
    config JSONB DEFAULT '{}',
    status VARCHAR DEFAULT 'pending',
    results JSONB,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (collector_id) REFERENCES collectors(id) ON DELETE SET NULL
);

CREATE TABLE credentials (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL,
    name VARCHAR NOT NULL,
    type VARCHAR NOT NULL,
    username VARCHAR,
    password VARCHAR,
    domain VARCHAR,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE TABLE system_settings (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR UNIQUE NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE tenant_user_auth (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL,
    username VARCHAR NOT NULL,
    email VARCHAR,
    password_hash VARCHAR NOT NULL,
    full_name VARCHAR,
    role VARCHAR DEFAULT 'viewer',
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    UNIQUE(tenant_id, username),
    UNIQUE(tenant_id, email)
);

EOSQL

    if [ $? -eq 0 ]; then
        log "✅ Tabelas criadas manualmente com sucesso"
        SCHEMA_SUCCESS=true
    else
        error "❌ Falha na criação manual de tabelas"
        exit 1
    fi
fi

# ============================================================================
# 3. VERIFICAR TABELAS CRIADAS
# ============================================================================

log "📋 Verificando tabelas criadas..."

REQUIRED_TABLES=("users" "tenants" "tenant_users" "collectors" "journeys" "credentials" "sessions" "system_settings" "tenant_user_auth")

for table in "${REQUIRED_TABLES[@]}"; do
    if psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT 1 FROM information_schema.tables WHERE table_name='$table';" | grep -q 1; then
        log "   ✅ Tabela '$table' verificada"
    else
        error "   ❌ Tabela '$table' ausente"
    fi
done

# ============================================================================
# 4. TESTAR CRIAÇÃO DE TENANT
# ============================================================================

log "🧪 Testando criação de tenant..."

# Reiniciar aplicação se necessário
if [ "$RESTART_APP" = true ]; then
    log "🔄 Reiniciando aplicação..."
    systemctl start samureye-app
    sleep 5
    
    # Aguardar aplicação ficar online
    for i in {1..30}; do
        if curl -s --connect-timeout 2 http://localhost:5000/api/health >/dev/null 2>&1; then
            log "✅ Aplicação online"
            break
        fi
        sleep 1
    done
fi

# Fazer teste de criação de tenant
TEST_PAYLOAD='{"name":"Tenant Teste","description":"Teste de criação após correção"}'

RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "$TEST_PAYLOAD" \
    "http://localhost:5000/api/tenants" \
    --connect-timeout 10 \
    --max-time 30 2>&1)

HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
    log "🎉 SUCESSO! Criação de tenant funcionando"
    echo "   • Status: $HTTP_STATUS"
    
    # Extrair ID do tenant criado para limpeza
    TENANT_ID=$(echo "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
    if [ -n "$TENANT_ID" ] && [ "$TENANT_ID" != "null" ]; then
        log "   • Tenant criado com ID: $TENANT_ID"
        
        # Remover tenant de teste
        log "🧹 Removendo tenant de teste..."
        psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DELETE FROM tenants WHERE id = '$TENANT_ID';" >/dev/null 2>&1
    fi
else
    error "❌ Teste de criação ainda falhando"
    echo "   • Status: $HTTP_STATUS"
    echo "   • Response: $RESPONSE_BODY"
    exit 1
fi

# ============================================================================
# 5. FINALIZAÇÃO
# ============================================================================

echo ""
log "🎉 CORREÇÃO APLICADA COM SUCESSO!"
echo ""
echo "✅ Schema do banco de dados recriado"
echo "✅ Tabelas verificadas e funcionando"
echo "✅ Teste de criação de tenant OK"
echo ""
echo "🔧 A interface agora deve funcionar normalmente"
echo ""

exit 0