#!/bin/bash

echo "🕵️ INVESTIGAÇÃO - COMO O COLLECTOR FAZ A REQUISIÇÃO"
echo "=================================================="

echo "🔍 1. Verificando configuração atual do collector..."
ssh root@192.168.100.151 'cat /etc/samureye-collector/.env'

echo ""
echo "🔍 2. Verificando código Python do collector..."
echo "Arquivo: /opt/samureye-collector/collector.py"
ssh root@192.168.100.151 'grep -A 10 -B 5 "journeys/pending\|fetch_pending_journeys" /opt/samureye-collector/collector.py'

echo ""
echo "🔍 3. Verificando como a URL é construída..."
ssh root@192.168.100.151 'grep -A 5 -B 5 "api_server\|API_SERVER" /opt/samureye-collector/collector.py'

echo ""
echo "🔍 4. Verificando parâmetros enviados..."
ssh root@192.168.100.151 'grep -A 5 -B 5 "params\|collector_id\|token" /opt/samureye-collector/collector.py'

echo ""
echo "🔍 5. Verificando headers enviados..."
ssh root@192.168.100.151 'grep -A 5 -B 5 "headers\|requests\\.get" /opt/samureye-collector/collector.py'

echo ""
echo "🔍 6. Verificando tratamento de resposta..."
ssh root@192.168.100.151 'grep -A 10 -B 5 "response\\.status_code\|401\|invalid" /opt/samureye-collector/collector.py'

echo ""
echo "🧪 7. Simulando EXATAMENTE como o collector faz..."

COLLECTOR_ID=$(ssh root@192.168.100.151 'grep COLLECTOR_ID /etc/samureye-collector/.env | cut -d= -f2')
COLLECTOR_TOKEN=$(ssh root@192.168.100.151 'grep COLLECTOR_TOKEN /etc/samureye-collector/.env | cut -d= -f2')
API_SERVER=$(ssh root@192.168.100.151 'grep API_SERVER /etc/samureye-collector/.env | cut -d= -f2')

echo "COLLECTOR_ID: ${COLLECTOR_ID:0:8}...${COLLECTOR_ID: -8}"
echo "COLLECTOR_TOKEN: ${COLLECTOR_TOKEN:0:8}...${COLLECTOR_TOKEN: -8}"
echo "API_SERVER: $API_SERVER"

# Teste como o collector Python provavelmente faz
echo ""
echo "🧪 Teste 1: Como fizemos manualmente (funcionou)..."
curl -s -w "HTTPCODE:%{http_code}" \
    "https://api.samureye.com.br/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN" \
    -H "User-Agent: SamurEye-Collector" 2>/dev/null

echo ""
echo ""
echo "🧪 Teste 2: Usando API_SERVER do .env..."
curl -s -w "HTTPCODE:%{http_code}" \
    "$API_SERVER/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN" \
    -H "User-Agent: SamurEye-Collector" 2>/dev/null

echo ""
echo ""
echo "🧪 Teste 3: Com User-Agent Python..."
curl -s -w "HTTPCODE:%{http_code}" \
    "https://api.samureye.com.br/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN" \
    -H "User-Agent: python-requests/2.31.0" 2>/dev/null

echo ""
echo ""
echo "🧪 Teste 4: Método POST (caso o collector use POST)..."
curl -s -w "HTTPCODE:%{http_code}" \
    -X POST "https://api.samureye.com.br/collector-api/journeys/pending" \
    -H "Content-Type: application/json" \
    -H "User-Agent: python-requests/2.31.0" \
    -d "{\"collector_id\":\"$COLLECTOR_ID\",\"token\":\"$COLLECTOR_TOKEN\"}" 2>/dev/null

echo ""
echo ""
echo "🧪 Teste 5: Com parâmetros no body..."
curl -s -w "HTTPCODE:%{http_code}" \
    -X GET "https://api.samureye.com.br/collector-api/journeys/pending" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "User-Agent: python-requests/2.31.0" \
    -d "collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN" 2>/dev/null

echo ""
echo ""
echo "🔍 8. Verificando logs do servidor NGINX/aplicação..."
echo "Últimas requisições para /collector-api/journeys/pending:"

ssh root@172.24.1.152 'tail -20 /var/log/nginx/access.log | grep "collector-api/journeys/pending" || echo "Nenhuma requisição encontrada nos logs NGINX"'

echo ""
echo "🔍 9. Verificando se coletor está fazendo requisições..."
echo "Monitorando por 10 segundos..."
ssh root@192.168.100.151 'timeout 10 strace -e trace=network -p $(pgrep -f collector.py) 2>&1 | grep -i "api\|http\|connect" || echo "Nenhuma atividade de rede detectada"'

echo ""
echo "🎯 PRÓXIMOS PASSOS:"
echo "   🔍 Comparar como collector faz vs nosso teste manual"
echo "   🔧 Ajustar URL/parâmetros se necessário"
echo "   🧪 Testar diferentes variações até encontrar a correta"