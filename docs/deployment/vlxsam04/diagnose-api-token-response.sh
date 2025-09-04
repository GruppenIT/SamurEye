#!/bin/bash

# Script de diagnóstico para problema de token não retornado pela API
# vlxsam04 - SamurEye Collector

echo "🔍 DIAGNÓSTICO: Token API Response"
echo "=================================="

HOSTNAME=$(hostname)
CONFIG_FILE="/etc/samureye-collector/.env"
API_SERVER="https://api.samureye.com.br"

echo "📋 Sistema: $HOSTNAME"
echo ""

# Verificar se temos parâmetros de teste
TENANT_SLUG="${1:-gruppen-it}"
ENROLLMENT_TOKEN="${2:-TESTE_SEM_TOKEN}"

echo "🔍 1. TESTANDO RESPOSTA DA API DE REGISTRO:"
echo "==========================================="

if [ "$ENROLLMENT_TOKEN" = "TESTE_SEM_TOKEN" ]; then
    echo "❌ Token de enrollment não fornecido"
    echo "   Uso: $0 <tenant-slug> <enrollment-token>"
    echo ""
    echo "💡 Para testar com token real:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/diagnose-api-token-response.sh | bash -s -- gruppen-it <TOKEN>"
    echo ""
else
    # Preparar payload de teste
    PAYLOAD=$(cat <<EOF
{
    "tenantSlug": "$TENANT_SLUG",
    "enrollmentToken": "$ENROLLMENT_TOKEN",
    "hostname": "$HOSTNAME",
    "ipAddress": "$(hostname -I | awk '{print $1}')"
}
EOF
)

    echo "📤 Enviando requisição de teste para API..."
    echo "   Endpoint: $API_SERVER/collector-api/register"
    echo "   Payload:"
    echo "$PAYLOAD" | jq . 2>/dev/null || echo "$PAYLOAD"
    echo ""

    # Fazer requisição com debug completo
    echo "🔍 Fazendo requisição de registro..."
    RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Content-Type: application/json" \
        -X POST \
        --data "$PAYLOAD" \
        "$API_SERVER/collector-api/register" \
        --connect-timeout 30 \
        --max-time 60)

    # Separar response body e HTTP status
    HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

    echo "📋 RESULTADO DA REQUISIÇÃO:"
    echo "   Status HTTP: $HTTP_STATUS"
    echo "   Response Body:"
    echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
    echo ""

    # Analisar resposta
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ STATUS 200 - Registro reportado como sucesso"
        echo ""
        
        echo "🔍 ANÁLISE DA ESTRUTURA DA RESPOSTA:"
        echo "==================================="
        
        # Tentar extrair token de múltiplas formas
        echo "🔑 Tentativas de extração de token:"
        
        TOKEN1=$(echo "$RESPONSE_BODY" | jq -r '.collector.token // ""' 2>/dev/null)
        echo "   1. .collector.token: ${TOKEN1:-'VAZIO'}"
        
        TOKEN2=$(echo "$RESPONSE_BODY" | jq -r '.token // ""' 2>/dev/null)
        echo "   2. .token: ${TOKEN2:-'VAZIO'}"
        
        TOKEN3=$(echo "$RESPONSE_BODY" | jq -r '.authToken // ""' 2>/dev/null)
        echo "   3. .authToken: ${TOKEN3:-'VAZIO'}"
        
        TOKEN4=$(echo "$RESPONSE_BODY" | jq -r '.collectorToken // ""' 2>/dev/null)
        echo "   4. .collectorToken: ${TOKEN4:-'VAZIO'}"
        
        TOKEN5=$(echo "$RESPONSE_BODY" | grep -o '"token":"[^"]*"' | cut -d'"' -f4 2>/dev/null)
        echo "   5. Extração via grep: ${TOKEN5:-'VAZIO'}"
        
        # Mostrar todas as chaves disponíveis
        echo ""
        echo "🗝️ CHAVES DISPONÍVEIS NA RESPOSTA:"
        if command -v jq >/dev/null; then
            echo "$RESPONSE_BODY" | jq -r 'paths(scalars) as $p | "\($p | join(".")): \(getpath($p))"' 2>/dev/null || echo "Não foi possível analisar estrutura JSON"
        else
            echo "jq não disponível - resposta raw:"
            echo "$RESPONSE_BODY"
        fi
        
        echo ""
        if [ -n "$TOKEN1" ] || [ -n "$TOKEN2" ] || [ -n "$TOKEN3" ] || [ -n "$TOKEN4" ] || [ -n "$TOKEN5" ]; then
            echo "✅ TOKEN ENCONTRADO em pelo menos um campo"
            FOUND_TOKEN="${TOKEN1:-${TOKEN2:-${TOKEN3:-${TOKEN4:-$TOKEN5}}}}"
            echo "   Token encontrado: ${FOUND_TOKEN:0:8}...${FOUND_TOKEN: -8}"
        else
            echo "❌ NENHUM TOKEN ENCONTRADO NA RESPOSTA"
            echo "   Este é o problema raiz!"
        fi
        
    else
        echo "❌ STATUS $HTTP_STATUS - Erro na requisição"
        echo "   Resposta: $RESPONSE_BODY"
    fi
fi

echo ""
echo "🔍 2. VERIFICANDO CONFIGURAÇÃO ATUAL:"
echo "===================================="

if [ -f "$CONFIG_FILE" ]; then
    echo "✅ Arquivo de configuração existe: $CONFIG_FILE"
    echo ""
    echo "📄 Conteúdo atual:"
    cat "$CONFIG_FILE"
    echo ""
    
    # Verificar tokens configurados
    CURRENT_TOKEN=$(grep "^COLLECTOR_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2)
    if [ -n "$CURRENT_TOKEN" ]; then
        echo "🔑 Token atual: ${CURRENT_TOKEN:0:8}...${CURRENT_TOKEN: -8}"
    else
        echo "❌ Nenhum token configurado"
    fi
else
    echo "❌ Arquivo de configuração não existe"
fi

echo ""
echo "🔍 3. VERIFICANDO STATUS DO SERVIÇO:"
echo "==================================="

echo "🤖 Status systemd:"
systemctl status samureye-collector --no-pager -l | head -5

echo ""
echo "📝 Últimos logs do serviço:"
if [ -f "/var/log/samureye-collector/heartbeat.log" ]; then
    tail -10 /var/log/samureye-collector/heartbeat.log
else
    journalctl -u samureye-collector --no-pager -n 5
fi

echo ""
echo "🔍 4. ANÁLISE DO PROBLEMA:"
echo "========================="

echo ""
echo "❌ PROBLEMAS IDENTIFICADOS:"

if [ "$ENROLLMENT_TOKEN" != "TESTE_SEM_TOKEN" ]; then
    if [ -z "$TOKEN1" ] && [ -z "$TOKEN2" ] && [ -z "$TOKEN3" ] && [ -z "$TOKEN4" ] && [ -z "$TOKEN5" ]; then
        echo "   🔴 CRÍTICO: API não retorna token na resposta de registro"
        echo "      Registro é reportado como sucesso mas token está ausente"
        echo "      Isso impede o collector de se autenticar"
    fi
fi

if [ -f "$CONFIG_FILE" ]; then
    CURRENT_TOKEN=$(grep "^COLLECTOR_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2)
    if [ -z "$CURRENT_TOKEN" ]; then
        echo "   🔴 CRÍTICO: Arquivo .env não contém token de autenticação"
        echo "      Heartbeat não consegue autenticar na API"
    fi
else
    echo "   🔴 CRÍTICO: Arquivo de configuração ausente"
fi

# Verificar se serviço está com erro 401
if journalctl -u samureye-collector --no-pager -n 10 | grep -q "401.*Unauthorized"; then
    echo "   🔴 CRÍTICO: Serviço recebendo erro 401 Unauthorized"
    echo "      Confirmação de problema de autenticação"
fi

echo ""
echo "🛠️ SOLUÇÕES RECOMENDADAS:"
echo "   1. Verificar se API está retornando token corretamente"
echo "   2. Atualizar script register-collector.sh para extrair token"
echo "   3. Implementar mecanismo alternativo de obtenção de token"
echo "   4. Executar script de correção específico"

echo ""
echo "🔧 COMANDOS DE CORREÇÃO:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/fix-api-token-extraction.sh | bash"