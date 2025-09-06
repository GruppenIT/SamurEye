#!/bin/bash

echo "🔍 DIAGNÓSTICO TABELAS SAMUREYE"
echo "=============================="

DB_HOST="172.24.1.153"
DB_USER="samureye"
DB_NAME="samureye"
DB_PASS="SamurEye2024!"

echo "🗄️ Conectando no banco..."

# Teste 1: Listar todas as tabelas
echo ""
echo "📋 Teste 1: Todas as tabelas existentes..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT schemaname, tablename 
     FROM pg_tables 
     WHERE schemaname = 'public' 
     ORDER BY tablename;" 2>/dev/null

# Teste 2: Verificar tabelas específicas SamurEye
echo ""
echo "📋 Teste 2: Verificando tabelas essenciais SamurEye..."
for table in "users" "tenants" "collectors" "journeys" "journey_executions" "sessions"; do
    EXISTS=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table');" 2>/dev/null | tr -d ' ')
    
    if [ "$EXISTS" = "t" ]; then
        echo "✅ $table - existe"
        
        # Contar registros se existe
        COUNT=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
            "SELECT COUNT(*) FROM $table;" 2>/dev/null | tr -d ' ')
        echo "   📊 Registros: $COUNT"
    else
        echo "❌ $table - NÃO EXISTE"
    fi
done

# Teste 3: Se tabela collectors existe, mostrar estrutura
COLLECTORS_EXISTS=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'collectors');" 2>/dev/null | tr -d ' ')

if [ "$COLLECTORS_EXISTS" = "t" ]; then
    echo ""
    echo "📋 Teste 3: Estrutura da tabela collectors..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "\d collectors;" 2>/dev/null
else
    echo ""
    echo "❌ Teste 3: Tabela collectors não existe - schema não aplicado!"
fi

# Teste 4: Verificar se há migrações Drizzle
echo ""
echo "📋 Teste 4: Verificando migrações Drizzle..."
MIGRATIONS_EXISTS=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '__drizzle_migrations');" 2>/dev/null | tr -d ' ')

if [ "$MIGRATIONS_EXISTS" = "t" ]; then
    echo "✅ Tabela de migrações Drizzle existe"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT id, hash, created_at FROM __drizzle_migrations ORDER BY created_at;" 2>/dev/null
else
    echo "❌ Tabela de migrações Drizzle NÃO EXISTE"
fi

echo ""
echo "🎯 DIAGNÓSTICO:"
if [ "$COLLECTORS_EXISTS" != "t" ]; then
    echo "❌ PROBLEMA CRÍTICO: Schema SamurEye não foi aplicado!"
    echo ""
    echo "🔧 SOLUÇÃO IMEDIATA:"
    echo "   ssh root@172.24.1.152  # vlxsam02"
    echo "   cd /opt/samureye/SamurEye"
    echo "   npm run db:push --force"
    echo ""
    echo "💡 EXPLICAÇÃO:"
    echo "   • PostgreSQL funciona (conexão OK)"
    echo "   • Mas tabelas SamurEye não foram criadas"
    echo "   • Por isso todas as consultas retornam vazio"
    echo "   • Heartbeat funciona porque não depende de tabelas específicas"
elif [ "$COLLECTORS_EXISTS" = "t" ]; then
    echo "✅ Schema aplicado mas tabelas vazias"
    echo "💡 Possível causa: Problema de registro ou limpeza de dados"
fi