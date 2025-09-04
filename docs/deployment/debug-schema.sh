#!/bin/bash

echo "🔍 DIAGNÓSTICO SCHEMA POSTGRESQL - SamurEye"
echo "==========================================="

DB_HOST="172.24.1.153"
DB_USER="samureye"
DB_NAME="samureye"
DB_PASS="SamurEye2024!"

echo "🗄️ Conectando no banco vlxsam03 ($DB_HOST)..."

# Teste 1: Conectividade básica
echo ""
echo "📋 Teste 1: Conectividade básica..."
if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" 2>/dev/null | grep -q "PostgreSQL"; then
    echo "✅ Conectividade OK"
else
    echo "❌ Falha na conectividade com PostgreSQL"
    exit 1
fi

# Teste 2: Listar todas as tabelas
echo ""
echo "📋 Teste 2: Listando todas as tabelas..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;" 2>/dev/null

# Teste 3: Verificar se tabela collectors existe
echo ""
echo "📋 Teste 3: Verificando tabela collectors..."
COLLECTORS_EXISTS=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'collectors');" 2>/dev/null | tr -d ' ')

if [ "$COLLECTORS_EXISTS" = "t" ]; then
    echo "✅ Tabela collectors existe"
    
    # Mostrar estrutura da tabela
    echo ""
    echo "📋 Estrutura da tabela collectors:"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "\d collectors;" 2>/dev/null
        
    # Contar registros
    echo ""
    echo "📊 Contagem de registros:"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT COUNT(*) as total_collectors FROM collectors;" 2>/dev/null
else
    echo "❌ Tabela collectors NÃO EXISTE!"
fi

# Teste 4: Verificar tabelas essenciais SamurEye
echo ""
echo "📋 Teste 4: Verificando tabelas essenciais SamurEye..."
for table in "users" "tenants" "collectors" "journeys" "journey_executions" "sessions"; do
    EXISTS=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table');" 2>/dev/null | tr -d ' ')
    
    if [ "$EXISTS" = "t" ]; then
        echo "✅ $table"
    else
        echo "❌ $table - NÃO EXISTE"
    fi
done

# Teste 5: Verificar se há dados de teste
echo ""
echo "📋 Teste 5: Verificando dados existentes..."
if [ "$COLLECTORS_EXISTS" = "t" ]; then
    echo "Collectors:"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT id, name, hostname, status, created_at FROM collectors ORDER BY created_at DESC LIMIT 3;" 2>/dev/null
fi

# Verificar tenants
TENANTS_EXISTS=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tenants');" 2>/dev/null | tr -d ' ')

if [ "$TENANTS_EXISTS" = "t" ]; then
    echo ""
    echo "Tenants:"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT id, name, slug, created_at FROM tenants ORDER BY created_at DESC LIMIT 3;" 2>/dev/null
fi

echo ""
echo "🎯 ANÁLISE DOS RESULTADOS:"
if [ "$COLLECTORS_EXISTS" != "t" ]; then
    echo "❌ PROBLEMA CRÍTICO: Tabela collectors não existe!"
    echo "💡 CAUSA: Schema do banco não foi aplicado corretamente"
    echo "🔧 SOLUÇÃO: Executar migração do schema"
    echo ""
    echo "   COMANDOS PARA CORRIGIR:"
    echo "   ssh root@172.24.1.152  # vlxsam02"
    echo "   cd /opt/samureye/SamurEye"
    echo "   npm run db:push --force"
elif [ "$COLLECTORS_EXISTS" = "t" ]; then
    echo "✅ Tabela collectors existe - problema pode ser outro"
    echo "💡 INVESTIGAR: Por que o token não está sendo salvo no registro"
fi