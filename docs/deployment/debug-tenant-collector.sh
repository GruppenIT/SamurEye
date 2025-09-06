#!/bin/bash

echo "🔍 DIAGNÓSTICO TENANT-COLLECTOR ASSOCIAÇÃO"
echo "=========================================="

if [ $# -lt 1 ]; then
    echo "Uso: $0 <COLLECTOR_TOKEN>"
    echo "Exemplo: $0 b6d6c21f-69c7-4e2a-8dfc-1e3da951b22"
    exit 1
fi

TOKEN="$1"
DB_HOST="172.24.1.153"
DB_USER="samureye"
DB_NAME="samureye"
DB_PASS="SamurEye2024!"

echo "🔍 Token do collector: ${TOKEN:0:8}...${TOKEN: -8}"

# Teste 1: Verificar o collector e seu tenant
echo ""
echo "📋 Teste 1: Informações do collector..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT c.id, c.name, c.hostname, c.status, c.tenant_id, c.enrollment_token,
            t.id as tenant_id_full, t.name as tenant_name, t.slug as tenant_slug
     FROM collectors c
     LEFT JOIN tenants t ON c.tenant_id = t.id
     WHERE c.enrollment_token = '$TOKEN';" 2>/dev/null

# Teste 2: Listar todos os tenants
echo ""
echo "📋 Teste 2: Todos os tenants existentes..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, slug, created_at 
     FROM tenants 
     ORDER BY created_at;" 2>/dev/null

# Teste 3: Listar todas as jornadas e seus tenants
echo ""
echo "📋 Teste 3: Jornadas existentes e seus tenants..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT j.id, j.name, j.tenant_id, j.collector_id, j.status,
            t.name as tenant_name, t.slug as tenant_slug
     FROM journeys j
     LEFT JOIN tenants t ON j.tenant_id = t.id
     ORDER BY j.created_at DESC
     LIMIT 5;" 2>/dev/null

# Teste 4: Verificar execuções de jornadas pendentes
echo ""
echo "📋 Teste 4: Execuções pendentes (queued)..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT je.id, je.journey_id, je.collector_id, je.status,
            j.name as journey_name, j.tenant_id,
            t.name as tenant_name
     FROM journey_executions je
     LEFT JOIN journeys j ON je.journey_id = j.id
     LEFT JOIN tenants t ON j.tenant_id = t.id
     WHERE je.status = 'queued'
     ORDER BY je.created_at;" 2>/dev/null

# Teste 5: Buscar collector por ID (vlxsam04)
echo ""
echo "📋 Teste 5: Buscando collector por ID 'vlxsam04'..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT c.id, c.name, c.hostname, c.tenant_id, c.enrollment_token,
            t.name as tenant_name, t.slug as tenant_slug
     FROM collectors c
     LEFT JOIN tenants t ON c.tenant_id = t.id
     WHERE c.id = 'vlxsam04' OR c.name = 'vlxsam04' OR c.hostname = 'vlxsam04';" 2>/dev/null

# Teste 6: Verificar se há mismatch de tenant entre collector e jornadas
echo ""
echo "📋 Teste 6: Verificando compatibilidade tenant-collector-jornadas..."
COLLECTOR_TENANT=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT tenant_id FROM collectors WHERE enrollment_token = '$TOKEN';" 2>/dev/null | tr -d ' ')

if [ -n "$COLLECTOR_TENANT" ]; then
    echo "✅ Collector encontrado - Tenant: $COLLECTOR_TENANT"
    
    # Verificar jornadas deste tenant
    echo ""
    echo "📊 Jornadas do tenant '$COLLECTOR_TENANT':"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT id, name, collector_id, status, schedule_type
         FROM journeys 
         WHERE tenant_id = '$COLLECTOR_TENANT'
         ORDER BY created_at DESC;" 2>/dev/null
         
    # Verificar execuções pendentes deste tenant
    echo ""
    echo "📊 Execuções pendentes do tenant '$COLLECTOR_TENANT':"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT je.id, je.journey_id, je.collector_id, je.status
         FROM journey_executions je
         JOIN journeys j ON je.journey_id = j.id
         WHERE j.tenant_id = '$COLLECTOR_TENANT' AND je.status = 'queued';" 2>/dev/null
else
    echo "❌ Collector não encontrado com este token"
fi

echo ""
echo "🎯 ANÁLISE DOS RESULTADOS:"
echo "💡 Verifique se:"
echo "   • Collector está associado ao tenant correto"
echo "   • Jornadas existem no mesmo tenant do collector"
echo "   • Execuções estão marcadas para o collector correto"
echo "   • collector_id nas jornadas corresponde ao ID do collector"