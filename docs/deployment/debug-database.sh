#!/bin/bash

echo "🔍 DIAGNÓSTICO BANCO DE DADOS - COLLECTOR TOKEN"
echo "=============================================="

if [ $# -lt 1 ]; then
    echo "Uso: $0 <COLLECTOR_TOKEN>"
    echo "Exemplo: $0 f2ff898f-706e-4756-98ad-3517cd692b78"
    exit 1
fi

TOKEN="$1"
DB_HOST="172.24.1.153"
DB_USER="samureye"
DB_NAME="samureye"
DB_PASS="SamurEye2024!"

echo "🔍 Token a investigar: ${TOKEN:0:8}...${TOKEN: -8}"
echo "🗄️ Conectando no banco vlxsam03 ($DB_HOST)..."

# Teste 1: Verificar se tabela collectors existe
echo ""
echo "📋 Teste 1: Verificando estrutura da tabela collectors..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "\d collectors;" 2>/dev/null

# Teste 2: Listar todos os collectors
echo ""
echo "📋 Teste 2: Listando todos os collectors..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, hostname, status, 
            enrollment_token, 
            enrollment_token_expires,
            enrollment_token_expires > NOW() as token_valid,
            created_at, updated_at 
     FROM collectors 
     ORDER BY created_at DESC 
     LIMIT 5;" 2>/dev/null

# Teste 3: Buscar por token específico
echo ""
echo "📋 Teste 3: Buscando token específico..."
RESULT=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT id, name, enrollment_token, enrollment_token_expires, enrollment_token_expires > NOW() as valid
     FROM collectors 
     WHERE enrollment_token = '$TOKEN';" 2>/dev/null)

if [ -n "$RESULT" ]; then
    echo "✅ Token encontrado no banco:"
    echo "$RESULT"
else
    echo "❌ Token NÃO encontrado no banco de dados"
    
    # Teste 4: Buscar por collector_id (vlxsam04)
    echo ""
    echo "📋 Teste 4: Buscando por collector_id 'vlxsam04'..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT id, name, hostname, enrollment_token, enrollment_token_expires 
         FROM collectors 
         WHERE id = 'vlxsam04' OR name = 'vlxsam04' OR hostname = 'vlxsam04';" 2>/dev/null
fi

# Teste 5: Verificar tokens expirados recentes
echo ""
echo "📋 Teste 5: Tokens expirados nas últimas 2 horas..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, enrollment_token, enrollment_token_expires,
            EXTRACT(EPOCH FROM (NOW() - enrollment_token_expires))/60 as minutes_expired
     FROM collectors 
     WHERE enrollment_token_expires > NOW() - INTERVAL '2 hours'
     ORDER BY enrollment_token_expires DESC;" 2>/dev/null

# Teste 6: Verificar se existe campo collector_token (novo campo)
echo ""
echo "📋 Teste 6: Verificando se existe campo collector_token permanente..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT column_name, data_type 
     FROM information_schema.columns 
     WHERE table_name = 'collectors' 
     AND column_name LIKE '%token%';" 2>/dev/null

echo ""
echo "🎯 ANÁLISE DOS RESULTADOS:"
if [ -n "$RESULT" ]; then
    echo "✅ Token existe no banco - problema pode ser na validação da API"
    echo "💡 PRÓXIMO PASSO: Verificar se vlxsam02 foi atualizado corretamente"
else
    echo "❌ Token não existe no banco - problema de registro ou sincronização"
    echo "💡 PRÓXIMOS PASSOS:"
    echo "   1. Re-registrar collector"
    echo "   2. Verificar comunicação entre vlxsam04 e banco"
    echo "   3. Verificar schema da tabela collectors"
fi