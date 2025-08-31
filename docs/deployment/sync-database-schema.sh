#!/bin/bash
# Script para Sincronizar Schema do Banco SamurEye
# Executa db:push no vlxsam02 para criar tabelas no vlxsam03

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ❌ ERROR: $1" >&2
    exit 1
}

echo "🗃️ Sincronização Schema SamurEye"
echo "================================"

# Verificar conectividade com vlxsam02
if ! ping -c 1 vlxsam02 >/dev/null 2>&1; then
    error "vlxsam02 não acessível"
fi

# Verificar conectividade com vlxsam03
if ! ping -c 1 vlxsam03 >/dev/null 2>&1; then
    error "vlxsam03 não acessível"
fi

log "🔄 Executando npm run db:push no vlxsam02..."

# Conectar ao vlxsam02 e executar db:push
ssh vlxsam02 << 'EOF'
set -e

cd /opt/samureye

echo "📁 Diretório atual: $(pwd)"
echo "🔍 Arquivos disponíveis:"
ls -la

# Verificar se existe o drizzle.config.ts
if [ -f "drizzle.config.ts" ]; then
    echo "✅ drizzle.config.ts encontrado"
else
    echo "❌ drizzle.config.ts não encontrado"
    exit 1
fi

# Verificar conexão com banco
echo "🔌 Testando conexão com PostgreSQL..."
export DATABASE_URL="postgresql://samureye:SamurEye2024%21@vlxsam03:5432/samureye"

if echo "SELECT version();" | psql "$DATABASE_URL" >/dev/null 2>&1; then
    echo "✅ Conexão com PostgreSQL OK"
else
    echo "❌ Falha na conexão com PostgreSQL"
    exit 1
fi

# Executar db:push
echo "🚀 Executando npm run db:push..."
npm run db:push --force

if [ $? -eq 0 ]; then
    echo "✅ Schema sincronizado com sucesso!"
    
    # Verificar tabelas criadas
    echo "📋 Tabelas criadas:"
    echo "SELECT tablename FROM pg_tables WHERE schemaname = 'public';" | psql "$DATABASE_URL" -t
else
    echo "❌ Falha no db:push"
    exit 1
fi
EOF

if [ $? -eq 0 ]; then
    log "✅ Schema sincronizado com sucesso!"
    
    # Testar se as tabelas foram criadas
    log "🔍 Verificando tabelas criadas..."
    
    PGPASSWORD='SamurEye2024!' psql -h vlxsam03 -U samureye -d samureye << 'SQL'
-- Listar todas as tabelas
SELECT 
    schemaname,
    tablename 
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;

-- Verificar estrutura da tabela collectors
\d collectors
SQL

    log "🎯 Testando script postgres-status.sh..."
    ssh vlxsam03 '/usr/local/bin/postgres-status.sh'
    
else
    error "Falha na sincronização do schema"
fi

log "✅ Sincronização completa!"
exit 0