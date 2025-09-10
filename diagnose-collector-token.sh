#!/bin/bash

# =============================================================================
# DIAGNÓSTICO COLLECTOR TOKEN - AMBIENTE ON-PREMISE vlxsam02
# =============================================================================

echo "🔍 DIAGNÓSTICO: Token do Collector vlxsam04"
echo "=============================================="

# Verificar arquivo .env da aplicação
echo ""
echo "1️⃣ Verificando configuração do banco..."
if [ -f "/etc/samureye/.env" ]; then
    echo "📄 Arquivo .env encontrado em /etc/samureye/"
    echo "   DATABASE_URL: $(grep DATABASE_URL /etc/samureye/.env | cut -d'=' -f2 | cut -c1-30)..."
    
    # Extrair parâmetros do DATABASE_URL
    DB_HOST="172.24.1.153"
    DB_PORT="5432"
    DB_USER="samureye"
    DB_NAME="samureye"
    DB_PASS="SamurEye2024!"
    
    echo "   Conectando a: ${DB_HOST}:${DB_PORT}"
elif [ -f "/opt/samureye/.env" ]; then
    echo "📄 Arquivo .env encontrado em /opt/samureye/"
    echo "   DATABASE_URL: $(grep DATABASE_URL /opt/samureye/.env | cut -d'=' -f2 | cut -c1-30)..."
    
    DB_HOST="172.24.1.153"
    DB_PORT="5432"
    DB_USER="samureye"
    DB_NAME="samureye"
    DB_PASS="SamurEye2024!"
else
    echo "❌ Arquivo .env não encontrado"
    exit 1
fi

# Verificar conectividade com vlxsam03
echo ""
echo "2️⃣ Verificando conectividade com vlxsam03..."
if timeout 5 bash -c "</dev/tcp/${DB_HOST}/${DB_PORT}"; then
    echo "✅ Conectividade TCP com ${DB_HOST}:${DB_PORT} OK"
else
    echo "❌ Não foi possível conectar a ${DB_HOST}:${DB_PORT}"
fi

# Conectar ao banco remoto e verificar collectors
echo ""
echo "3️⃣ Verificando collectors no banco remoto..."
export PGPASSWORD="${DB_PASS}"
psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "
SELECT 
    id,
    name,
    substring(enrollment_token, 1, 8) || '...' as token_preview,
    status,
    created_at
FROM collectors 
WHERE name = 'vlxsam04' OR id LIKE '%vlxsam04%'
ORDER BY created_at DESC;
" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Consulta ao banco remoto executada"
else
    echo "❌ Erro ao consultar banco remoto"
fi

# Verificar se aplicação está rodando
echo ""
echo "4️⃣ Verificando aplicação..."
if curl -s --connect-timeout 3 http://localhost:5000/api/health >/dev/null 2>&1; then
    echo "✅ Aplicação está respondendo"
else
    echo "❌ Aplicação não está respondendo"
fi

# Obter token do banco remoto para testar
echo ""
echo "5️⃣ Obtendo token do collector do banco..."
export PGPASSWORD="${DB_PASS}"
TOKEN=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT enrollment_token FROM collectors WHERE name = 'vlxsam04' LIMIT 1;" 2>/dev/null | tr -d ' ')

if [ -n "$TOKEN" ]; then
    echo "✅ Token encontrado: ${TOKEN:0:8}..."
else
    echo "❌ Token não encontrado no banco"
fi

# Testar endpoints do collector com token real
echo ""
echo "6️⃣ Testando endpoint pending..."
COLLECTOR_ID="vlxsam04"

if [ -n "$TOKEN" ]; then
    echo "🔗 Testando: /collector-api/journeys/pending"
    echo "   Parâmetros: collector_id=${COLLECTOR_ID}, token=${TOKEN:0:8}..."
    RESPONSE=$(curl -s "http://localhost:5000/collector-api/journeys/pending?collector_id=${COLLECTOR_ID}&token=${TOKEN}")
    echo "   Resposta: ${RESPONSE:0:200}"
    echo ""
else
    echo "❌ Não foi possível testar - token não encontrado"
fi

echo ""
echo "7️⃣ Testando endpoint de dados da jornada..."
if [ -n "$TOKEN" ]; then
    # Buscar uma jornada de exemplo do banco remoto
    export PGPASSWORD="${DB_PASS}"
    JOURNEY_ID=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT id FROM journeys LIMIT 1;" 2>/dev/null | tr -d ' ')
    if [ -n "$JOURNEY_ID" ]; then
        echo "🔗 Testando: /collector-api/journeys/${JOURNEY_ID}/data"
        echo "   Parâmetros: collector_id=${COLLECTOR_ID}, token=${TOKEN:0:8}..."
        RESPONSE=$(curl -s "http://localhost:5000/collector-api/journeys/${JOURNEY_ID}/data?collector_id=${COLLECTOR_ID}&token=${TOKEN}")
        echo "   Resposta: ${RESPONSE:0:200}"
        echo ""
    else
        echo "❌ Nenhuma jornada encontrada para testar"
    fi
fi

echo ""
echo "=========================================="
echo "🏁 DIAGNÓSTICO CONCLUÍDO"
echo "Execute este script no servidor vlxsam02"