#!/bin/bash

echo "🧪 TESTE RÁPIDO API COLLECTOR"
echo "=============================="

# Carregar configurações do collector
if [ -f "/etc/samureye-collector/.env" ]; then
    source /etc/samureye-collector/.env
    echo "✅ Configurações carregadas:"
    echo "   • COLLECTOR_ID: $COLLECTOR_ID"
    echo "   • COLLECTOR_TOKEN: ${COLLECTOR_TOKEN:0:8}...${COLLECTOR_TOKEN: -8}"
else
    echo "❌ Arquivo .env não encontrado em /etc/samureye-collector/.env"
    exit 1
fi

API_BASE="https://api.samureye.com.br"

echo ""
echo "🔍 Testando heartbeat..."
HEARTBEAT_RESULT=$(curl -s -w "HTTP:%{http_code}" \
    -X POST "$API_BASE/collector-api/heartbeat" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $COLLECTOR_TOKEN" \
    -H "X-Collector-Token: $COLLECTOR_TOKEN" \
    -d '{
        "collector_id": "'"$COLLECTOR_ID"'",
        "token": "'"$COLLECTOR_TOKEN"'",
        "telemetry": {"cpu_usage": 10.5, "memory_usage": 45.2},
        "status": "online"
    }' 2>/dev/null)

HEARTBEAT_CODE="${HEARTBEAT_RESULT##*HTTP:}"
HEARTBEAT_BODY="${HEARTBEAT_RESULT%HTTP:*}"
echo "   • Heartbeat: $HEARTBEAT_CODE - $HEARTBEAT_BODY"

echo ""
echo "🎯 Testando journeys/pending..."
PENDING_RESULT=$(curl -s -w "HTTP:%{http_code}" \
    "$API_BASE/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN" \
    2>/dev/null)

PENDING_CODE="${PENDING_RESULT##*HTTP:}"
PENDING_BODY="${PENDING_RESULT%HTTP:*}"
echo "   • Pending: $PENDING_CODE - $PENDING_BODY"

echo ""
echo "🔍 Testando se endpoint existe..."
ENDPOINT_TEST=$(curl -s -w "HTTP:%{http_code}" \
    "$API_BASE/collector-api/journeys/pending" \
    2>/dev/null)

ENDPOINT_CODE="${ENDPOINT_TEST##*HTTP:}"
ENDPOINT_BODY="${ENDPOINT_TEST%HTTP:*}"
echo "   • Endpoint sem params: $ENDPOINT_CODE - $ENDPOINT_BODY"

echo ""
echo "📊 Verificando banco de dados..."
PGPASSWORD="SamurEye2024!" psql -h 172.24.1.153 -U samureye -d samureye -t -c \
    "SELECT 'ID:', id, 'Name:', name, 'Status:', status, 'Token_Valid:', (enrollment_token_expires > NOW()) FROM collectors WHERE enrollment_token = '$COLLECTOR_TOKEN' OR id = '$COLLECTOR_ID';" 2>/dev/null

if [ "$PENDING_CODE" = "401" ]; then
    echo ""
    echo "❌ PROBLEMA CONFIRMADO: Token rejeitado (401)"
    echo "💡 CAUSA PROVÁVEL: vlxsam02 não foi atualizado com as correções"
    echo ""
    echo "🔧 SOLUÇÃO:"
    echo "   ssh root@172.24.1.152"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
elif [ "$PENDING_CODE" = "200" ]; then
    echo ""
    echo "✅ SUCESSO: Token aceito!"
    echo "📋 Jornadas encontradas: $PENDING_BODY"
else
    echo ""
    echo "⚠️ ERRO INESPERADO: $PENDING_CODE"
    echo "📋 Response: $PENDING_BODY"
fi