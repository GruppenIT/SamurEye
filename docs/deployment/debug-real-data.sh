#!/bin/bash

echo "🔍 DIAGNÓSTICO DADOS REAIS - SamurEye"
echo "===================================="

if [ $# -lt 1 ]; then
    echo "Uso: $0 <COLLECTOR_TOKEN>"
    echo "Exemplo: $0 b6d6c21f-69c7-4e2a-8dfc-1e3da951b22"
    exit 1
fi

TOKEN="$1"
DB_HOST="172.24.1.153"
DB_USER="samureye_user"
DB_NAME="samureye"
DB_PASS="samureye_secure_2024"

echo "🔍 Token do collector: ${TOKEN:0:8}...${TOKEN: -8}"

# Teste 1: Verificar collector específico por token
echo ""
echo "📋 Teste 1: Buscando collector por enrollment_token..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, hostname, tenant_id, status, enrollment_token, enrollment_token_expires,
            enrollment_token_expires > NOW() as token_valid
     FROM collectors 
     WHERE enrollment_token = '$TOKEN';" 2>/dev/null

# Teste 2: Listar TODOS os collectors
echo ""
echo "📋 Teste 2: Todos os collectors registrados..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, hostname, tenant_id, status, 
            LEFT(enrollment_token, 8) || '...' as token_preview,
            enrollment_token_expires,
            enrollment_token_expires > NOW() as token_valid
     FROM collectors 
     ORDER BY created_at;" 2>/dev/null

# Teste 3: Listar todos os tenants
echo ""
echo "📋 Teste 3: Todos os tenants..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, slug, created_at 
     FROM tenants 
     ORDER BY created_at;" 2>/dev/null

# Teste 4: Listar jornadas
echo ""
echo "📋 Teste 4: Jornadas existentes..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT j.id, j.name, j.tenant_id, j.collector_id, j.status, j.schedule_type,
            t.name as tenant_name, t.slug as tenant_slug
     FROM journeys j
     LEFT JOIN tenants t ON j.tenant_id = t.id
     ORDER BY j.created_at DESC 
     LIMIT 5;" 2>/dev/null

# Teste 5: Execuções pendentes
echo ""
echo "📋 Teste 5: Execuções pendentes (status = 'queued')..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT je.id, je.journey_id, je.collector_id, je.status, je.created_at,
            j.name as journey_name, j.tenant_id
     FROM journey_executions je
     LEFT JOIN journeys j ON je.journey_id = j.id
     WHERE je.status = 'queued'
     ORDER BY je.created_at;" 2>/dev/null

# Teste 6: Verificar se collector tem tenant correto
COLLECTOR_INFO=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT id, tenant_id FROM collectors WHERE enrollment_token = '$TOKEN';" 2>/dev/null)

if [ -n "$COLLECTOR_INFO" ]; then
    COLLECTOR_ID=$(echo "$COLLECTOR_INFO" | awk '{print $1}' | tr -d ' ')
    TENANT_ID=$(echo "$COLLECTOR_INFO" | awk '{print $3}' | tr -d ' ')
    
    echo ""
    echo "📋 Teste 6: Análise específica do collector..."
    echo "   • Collector ID: $COLLECTOR_ID"
    echo "   • Tenant ID: $TENANT_ID"
    
    if [ -n "$TENANT_ID" ] && [ "$TENANT_ID" != "" ]; then
        echo ""
        echo "📊 Jornadas do tenant '$TENANT_ID' (mesmo tenant do collector):"
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
            "SELECT id, name, collector_id, status, schedule_type
             FROM journeys 
             WHERE tenant_id = '$TENANT_ID';" 2>/dev/null
             
        echo ""
        echo "📊 Execuções pendentes do mesmo tenant:"
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
            "SELECT je.id, je.journey_id, je.collector_id, je.status
             FROM journey_executions je
             JOIN journeys j ON je.journey_id = j.id
             WHERE j.tenant_id = '$TENANT_ID' AND je.status = 'queued';" 2>/dev/null
             
        echo ""
        echo "📊 Execuções direcionadas para este collector:"
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
            "SELECT je.id, je.journey_id, je.collector_id, je.status
             FROM journey_executions je
             WHERE je.collector_id = '$COLLECTOR_ID' AND je.status = 'queued';" 2>/dev/null
    else
        echo "❌ Collector não tem tenant_id definido!"
    fi
else
    echo ""
    echo "❌ Collector não encontrado com o token fornecido"
    echo ""
    echo "🔍 Tokens disponíveis no banco (primeiros 8 caracteres):"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT LEFT(enrollment_token, 8) as token_start, name, status
         FROM collectors;" 2>/dev/null
fi

echo ""
echo "🎯 RESUMO PARA ANÁLISE:"
echo "💡 Verifique se:"
echo "   • Collector existe com o token correto"
echo "   • Collector tem tenant_id definido"
echo "   • Existem jornadas no mesmo tenant"
echo "   • Há execuções pendentes direcionadas ao collector"