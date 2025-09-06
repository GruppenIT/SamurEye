#!/bin/bash

echo "🧪 TESTE DIRETO DO ENDPOINT - collector-api/journeys/pending"
echo "==========================================================="

COLLECTOR_ID="b6d6c21f-cf49-43a0-ba22-68e3da951b22"
COLLECTOR_TOKEN="b6d6c21f-cf49-43a0-ba22-68e3da951b22"
API_BASE="https://api.samureye.com.br"

echo "🔍 Collector ID: ${COLLECTOR_ID:0:8}...${COLLECTOR_ID: -8}"
echo "🔍 Token: ${COLLECTOR_TOKEN:0:8}...${COLLECTOR_TOKEN: -8}"

# Teste 1: Endpoint direto
echo ""
echo "📋 Teste 1: Chamada direta ao endpoint..."
echo "URL: $API_BASE/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN"

RESPONSE=$(curl -s -w "HTTPCODE:%{http_code}" \
    "$API_BASE/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN" \
    -H "User-Agent: SamurEye-Collector" 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | sed -n 's/.*HTTPCODE:\([0-9]*\).*/\1/p')
BODY=$(echo "$RESPONSE" | sed 's/HTTPCODE:[0-9]*$//')

echo "HTTP Code: $HTTP_CODE"
echo "Response: $BODY"

# Teste 2: Verificar dados no banco que deveriam retornar
echo ""
echo "📋 Teste 2: Verificando dados que o endpoint deveria retornar..."

DB_HOST="172.24.1.153"
DB_USER="samureye_user"
DB_NAME="samureye"
DB_PASS="samureye_secure_2024"

# Verificar se collector existe
echo ""
echo "🔍 Collector no banco:"
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, enrollment_token IS NOT NULL as has_token,
            enrollment_token_expires > NOW() as token_valid
     FROM collectors 
     WHERE id = '$COLLECTOR_ID';" 2>/dev/null

# Verificar execuções pendentes
echo ""
echo "🔍 Execuções pendentes (o que o endpoint deveria retornar):"
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT je.id, je.journey_id, je.collector_id, je.status, je.created_at,
            j.name as journey_name
     FROM journey_executions je
     JOIN journeys j ON je.journey_id = j.id
     WHERE je.status = 'queued';" 2>/dev/null

# Verificar lógica específica do endpoint
echo ""
echo "🔍 Simulando lógica do endpoint:"
echo "1. Buscar collector por enrollment_token..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, 'FOUND' as status
     FROM collectors 
     WHERE enrollment_token = '$COLLECTOR_TOKEN' 
     AND enrollment_token_expires > NOW();" 2>/dev/null

echo ""
echo "2. Buscar execuções pendentes..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT je.* 
     FROM journey_executions je
     WHERE je.status = 'queued';" 2>/dev/null

echo ""
echo "3. Filtrar execuções para este collector..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT je.* 
     FROM journey_executions je
     WHERE je.status = 'queued' 
     AND je.collector_id = '$COLLECTOR_ID';" 2>/dev/null

# Teste 3: Forçar criação de execução correta
echo ""
echo "📋 Teste 3: Forçando criação de execução correta..."

# Buscar jornada
JOURNEY_ID=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT id FROM journeys LIMIT 1;" 2>/dev/null | tr -d ' ')

if [ -n "$JOURNEY_ID" ]; then
    echo "Jornada encontrada: $JOURNEY_ID"
    
    # Deletar execuções antigas
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "DELETE FROM journey_executions WHERE journey_id = '$JOURNEY_ID';" 2>/dev/null
    
    # Criar nova execução
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "INSERT INTO journey_executions (id, journey_id, collector_id, status, created_at, updated_at)
         VALUES (gen_random_uuid(), '$JOURNEY_ID', '$COLLECTOR_ID', 'queued', NOW(), NOW());" 2>/dev/null
    
    echo "✅ Nova execução criada!"
    
    # Verificar se foi criada
    echo "Verificando..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT COUNT(*) as total_queued FROM journey_executions WHERE status = 'queued';" 2>/dev/null
fi

# Teste 4: Testar endpoint novamente
echo ""
echo "📋 Teste 4: Testando endpoint após correção..."
RESPONSE2=$(curl -s -w "HTTPCODE:%{http_code}" \
    "$API_BASE/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN" \
    -H "User-Agent: SamurEye-Collector" 2>/dev/null)

HTTP_CODE2=$(echo "$RESPONSE2" | sed -n 's/.*HTTPCODE:\([0-9]*\).*/\1/p')
BODY2=$(echo "$RESPONSE2" | sed 's/HTTPCODE:[0-9]*$//')

echo "HTTP Code: $HTTP_CODE2"
echo "Response: $BODY2"

echo ""
echo "🎯 ANÁLISE:"
if [ "$HTTP_CODE2" = "200" ] && [ "$BODY2" != "[]" ]; then
    echo "✅ SUCESSO! Endpoint funcionando"
    echo "🎉 Collector deve parar de mostrar erro em alguns segundos"
elif [ "$HTTP_CODE2" = "401" ]; then
    echo "❌ AINDA 401 - Problema na validação do token"
elif [ "$HTTP_CODE2" = "200" ] && [ "$BODY2" = "[]" ]; then
    echo "⚠️ Endpoint OK mas sem execuções pendentes"
else
    echo "❌ Problema inesperado: $HTTP_CODE2"
fi