#!/bin/bash
# Script LOCAL para vlxsam03 - Corrigir PostgreSQL e Collectors
# Execute diretamente no vlxsam03 como root

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ❌ ERROR: $1" >&2
    exit 1
}

echo "🗃️ Correção LOCAL vlxsam03 - PostgreSQL"
echo "===================================="

# Verificar se é executado como root
if [[ $EUID -ne 0 ]]; then
    error "Execute como root: sudo ./fix-vlxsam03-local.sh"
fi

# Verificar se estamos no vlxsam03
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" != "vlxsam03" ]]; then
    log "⚠️ Este script é para vlxsam03, mas estamos em: $HOSTNAME"
    read -p "Continuar mesmo assim? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ============================================================================
# 1. VERIFICAR E CORRIGIR POSTGRESQL
# ============================================================================

log "🔍 Verificando PostgreSQL..."

# Verificar se PostgreSQL está rodando
if ! systemctl is-active postgresql >/dev/null 2>&1; then
    log "⚠️ PostgreSQL não está rodando - iniciando..."
    systemctl start postgresql
    sleep 3
fi

if systemctl is-active postgresql >/dev/null 2>&1; then
    log "✅ PostgreSQL está rodando"
else
    error "Falha ao iniciar PostgreSQL"
fi

# ============================================================================
# 2. VERIFICAR E CORRIGIR BANCO SAMUREYE
# ============================================================================

log "🗃️ Verificando banco SamurEye..."

# Testar conexão como postgres
if sudo -u postgres psql -d samureye -c "SELECT version();" >/dev/null 2>&1; then
    log "✅ Banco samureye acessível"
else
    log "⚠️ Banco samureye com problemas - tentando recriar..."
    
    # Recriar banco se necessário
    sudo -u postgres psql << 'EOF'
-- Criar usuário e banco se não existirem
CREATE USER samureye WITH ENCRYPTED PASSWORD 'SamurEye2024!' IF NOT EXISTS;
CREATE DATABASE samureye OWNER samureye IF NOT EXISTS;
GRANT ALL PRIVILEGES ON DATABASE samureye TO samureye;
ALTER USER samureye CREATEDB;
EOF
fi

# Testar com usuário samureye
export PGPASSWORD='SamurEye2024!'
if psql -h localhost -U samureye -d samureye -c "SELECT 1;" >/dev/null 2>&1; then
    log "✅ Autenticação usuário samureye funcionando"
else
    error "Falha na autenticação do usuário samureye"
fi

# ============================================================================
# 3. CRIAR/CORRIGIR TABELAS ESSENCIAIS
# ============================================================================

log "📝 Criando/corrigindo tabelas essenciais..."

PGPASSWORD='SamurEye2024!' psql -h localhost -U samureye -d samureye << 'SQL'
-- Criar extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Criar tabela tenants
CREATE TABLE IF NOT EXISTS tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    slug VARCHAR UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Criar tabela users
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR UNIQUE NOT NULL,
    password_hash VARCHAR,
    name VARCHAR,
    role VARCHAR DEFAULT 'viewer',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Criar tabela user_tenants
CREATE TABLE IF NOT EXISTS user_tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR NOT NULL,
    tenant_id VARCHAR NOT NULL,
    role VARCHAR DEFAULT 'viewer',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, tenant_id)
);

-- Criar tabela collectors
CREATE TABLE IF NOT EXISTS collectors (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    tenant_id VARCHAR NOT NULL,
    status VARCHAR DEFAULT 'enrolling',
    last_seen TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    telemetry JSONB,
    config JSONB,
    metadata JSONB
);

-- Criar outras tabelas necessárias
CREATE TABLE IF NOT EXISTS security_journeys (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL,
    name VARCHAR NOT NULL,
    config JSONB,
    status VARCHAR DEFAULT 'draft',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS credentials (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL,
    name VARCHAR NOT NULL,
    type VARCHAR NOT NULL,
    encrypted_data JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Inserir dados iniciais se não existirem
INSERT INTO tenants (id, name, slug) 
VALUES ('default-tenant-id', 'GruppenIT', 'gruppenIT')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO users (id, email, name, role)
VALUES ('admin-user-id', 'admin@samureye.com.br', 'Administrator', 'admin')
ON CONFLICT (email) DO NOTHING;

INSERT INTO user_tenants (user_id, tenant_id, role)
VALUES ('admin-user-id', 'default-tenant-id', 'admin')
ON CONFLICT (user_id, tenant_id) DO NOTHING;

-- Inserir collector vlxsam04 se não existir
INSERT INTO collectors (id, name, tenant_id, status, last_seen, created_at, updated_at) 
VALUES (
    'vlxsam04-collector-id', 
    'vlxsam04', 
    'default-tenant-id', 
    'online', 
    NOW(), 
    NOW(), 
    NOW()
)
ON CONFLICT (id) DO UPDATE SET 
    status = 'online', 
    last_seen = NOW(),
    updated_at = NOW();

-- Mostrar tabelas criadas
SELECT 
    schemaname,
    tablename 
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;
SQL

log "✅ Tabelas essenciais criadas/verificadas"

# ============================================================================
# 4. CORRIGIR COLLECTORS EM STATUS ENROLLING
# ============================================================================

log "🤖 Corrigindo collectors em status ENROLLING..."

PGPASSWORD='SamurEye2024!' psql -h localhost -U samureye -d samureye << 'SQL'
-- Atualizar collectors antigos ENROLLING para ONLINE
UPDATE collectors 
SET 
    status = 'online', 
    last_seen = NOW(),
    updated_at = NOW()
WHERE status = 'enrolling' 
   AND created_at < NOW() - INTERVAL '5 minutes';

-- Mostrar status atual dos collectors
SELECT 
    name, 
    status, 
    last_seen,
    EXTRACT(EPOCH FROM (NOW() - last_seen))::INT as seconds_since_last_seen
FROM collectors 
ORDER BY last_seen DESC;
SQL

# ============================================================================
# 5. CONFIGURAR SCRIPT DE LIMPEZA AUTOMÁTICA
# ============================================================================

log "⏰ Configurando limpeza automática..."

# Atualizar script de correção se existir
if [ -f "/usr/local/bin/fix-enrolling-collectors.sh" ]; then
    log "🔄 Atualizando script de correção..."
else
    log "📝 Criando script de correção..."
fi

cat > /usr/local/bin/fix-enrolling-collectors.sh << 'EOF'
#!/bin/bash
# Script para corrigir collectors presos em status ENROLLING

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Atualizar collectors antigos para online
UPDATED_COUNT=$(PGPASSWORD='SamurEye2024!' psql -h localhost -U samureye -d samureye -t -c "
UPDATE collectors 
SET status = 'online', last_seen = NOW(), updated_at = NOW()
WHERE status = 'enrolling' 
  AND created_at < NOW() - INTERVAL '5 minutes'
RETURNING id;
" 2>/dev/null | wc -l | tr -d ' ')

if [[ $UPDATED_COUNT -gt 0 ]]; then
    log "✅ $UPDATED_COUNT collectors atualizados de ENROLLING para ONLINE"
fi

# Mostrar status atual
ONLINE_COUNT=$(PGPASSWORD='SamurEye2024!' psql -h localhost -U samureye -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE status = 'online';" 2>/dev/null | tr -d ' ')
ENROLLING_COUNT=$(PGPASSWORD='SamurEye2024!' psql -h localhost -U samureye -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE status = 'enrolling';" 2>/dev/null | tr -d ' ')

log "📊 Status: $ONLINE_COUNT online, $ENROLLING_COUNT enrolling"
EOF

chmod +x /usr/local/bin/fix-enrolling-collectors.sh

# Executar correção inicial
log "🎯 Executando correção inicial..."
/usr/local/bin/fix-enrolling-collectors.sh

# ============================================================================
# 6. ATUALIZAR SCRIPT DE STATUS
# ============================================================================

log "📊 Atualizando script de status..."

cat > /usr/local/bin/postgres-status.sh << 'EOF'
#!/bin/bash
echo "🗃️ Status PostgreSQL SamurEye"
echo "============================="
echo ""

echo "🖥️ Serviço PostgreSQL:"
systemctl status postgresql --no-pager -l | head -8
echo ""

echo "🔌 Conexões ativas:"
PGPASSWORD='SamurEye2024!' psql -h localhost -U samureye -d samureye -c "SELECT count(*) as conexoes_ativas FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null
echo ""

echo "📋 Tabelas existentes:"
PGPASSWORD='SamurEye2024!' psql -h localhost -U samureye -d samureye -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;" 2>/dev/null
echo ""

echo "🤖 Status dos collectors:"
PGPASSWORD='SamurEye2024!' psql -h localhost -U samureye -d samureye -c "SELECT status, COUNT(*) FROM collectors GROUP BY status ORDER BY status;" 2>/dev/null
echo ""

echo "📅 Últimos collectors registrados:"
PGPASSWORD='SamurEye2024!' psql -h localhost -U samureye -d samureye -c "SELECT name, status, created_at, last_seen FROM collectors ORDER BY created_at DESC LIMIT 5;" 2>/dev/null
EOF

chmod +x /usr/local/bin/postgres-status.sh

# ============================================================================
# 7. VERIFICAÇÃO FINAL
# ============================================================================

log "🔍 Executando verificação final..."

echo ""
echo "📊 STATUS FINAL vlxsam03:"
echo "========================"

# Executar script de status
/usr/local/bin/postgres-status.sh

echo ""
log "✅ Correção vlxsam03 finalizada!"
echo ""
echo "🔗 Comandos úteis:"
echo "   /usr/local/bin/postgres-status.sh      # Status completo"
echo "   /usr/local/bin/fix-enrolling-collectors.sh  # Corrigir ENROLLING"
echo ""
echo "🌐 Teste a interface:"
echo "   https://app.samureye.com.br/admin/collectors"

exit 0