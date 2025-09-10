#!/bin/bash

# =============================================================================
# DIAGNÓSTICO COLLECTOR TOKEN - AMBIENTE ON-PREMISE
# =============================================================================

echo "🔍 DIAGNÓSTICO: Token do Collector vlxsam04"
echo "=============================================="

# Verificar se PostgreSQL está rodando
echo ""
echo "1️⃣ Verificando PostgreSQL..."
if systemctl is-active --quiet postgresql; then
    echo "✅ PostgreSQL está rodando"
else
    echo "❌ PostgreSQL não está rodando"
    exit 1
fi

# Conectar ao banco e verificar collectors
echo ""
echo "2️⃣ Verificando collectors no banco..."
sudo -u postgres psql -d samureye_db -c "
SELECT 
    id,
    name,
    substring(enrollment_token, 1, 8) || '...' as token_preview,
    status,
    created_at
FROM collectors 
WHERE name = 'vlxsam04' OR id LIKE '%vlxsam04%';
" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Consulta ao banco executada"
else
    echo "❌ Erro ao consultar banco"
fi

# Verificar se aplicação está rodando
echo ""
echo "3️⃣ Verificando aplicação..."
if curl -s --connect-timeout 3 http://localhost:5000/api/health >/dev/null 2>&1; then
    echo "✅ Aplicação está respondendo"
else
    echo "❌ Aplicação não está respondendo"
fi

# Obter token do collector do arquivo de configuração (se existir)
echo ""
echo "4️⃣ Verificando arquivo de configuração do collector..."
if [ -f "/opt/samureye-collector/.env" ]; then
    echo "📄 Arquivo .env encontrado:"
    echo "   COLLECTOR_ID: $(grep COLLECTOR_ID /opt/samureye-collector/.env | cut -d'=' -f2)"
    echo "   TOKEN: $(grep COLLECTOR_TOKEN /opt/samureye-collector/.env | cut -d'=' -f2 | cut -c1-8)..."
elif [ -f "/etc/samureye-collector/config.conf" ]; then
    echo "📄 Arquivo config.conf encontrado:"
    grep -E "(COLLECTOR_ID|TOKEN)" /etc/samureye-collector/config.conf | head -2
else
    echo "❌ Arquivo de configuração do collector não encontrado"
fi

# Testar endpoints do collector
echo ""
echo "5️⃣ Testando endpoint pending..."
COLLECTOR_ID="vlxsam04"
TOKEN=$(sudo -u postgres psql -d samureye_db -t -c "SELECT enrollment_token FROM collectors WHERE name = 'vlxsam04' LIMIT 1;" 2>/dev/null | tr -d ' ')

if [ -n "$TOKEN" ]; then
    echo "🔗 Testando: /collector-api/journeys/pending"
    curl -s "http://localhost:5000/collector-api/journeys/pending?collector_id=${COLLECTOR_ID}&token=${TOKEN}" | head -c 200
    echo ""
else
    echo "❌ Token não encontrado no banco"
fi

echo ""
echo "6️⃣ Testando endpoint de dados da jornada..."
if [ -n "$TOKEN" ]; then
    # Buscar uma jornada de exemplo
    JOURNEY_ID=$(sudo -u postgres psql -d samureye_db -t -c "SELECT id FROM journeys LIMIT 1;" 2>/dev/null | tr -d ' ')
    if [ -n "$JOURNEY_ID" ]; then
        echo "🔗 Testando: /collector-api/journeys/${JOURNEY_ID}/data"
        curl -s "http://localhost:5000/collector-api/journeys/${JOURNEY_ID}/data?collector_id=${COLLECTOR_ID}&token=${TOKEN}" | head -c 200
        echo ""
    else
        echo "❌ Nenhuma jornada encontrada para testar"
    fi
fi

echo ""
echo "7️⃣ Verificando logs do collector..."
if [ -f "/var/log/samureye-collector.log" ]; then
    echo "📋 Últimas 5 linhas do log do collector:"
    tail -5 /var/log/samureye-collector.log
elif [ -f "/var/log/samureye-collector" ]; then
    echo "📋 Últimas 5 linhas do log do collector:"
    tail -5 /var/log/samureye-collector
else
    echo "❌ Log do collector não encontrado"
fi

echo ""
echo "=========================================="
echo "🏁 DIAGNÓSTICO CONCLUÍDO"
echo "Execute este script no servidor vlxsam02"