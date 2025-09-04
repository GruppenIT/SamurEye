#!/bin/bash

# Diagnóstico FINAL - Analisa exatamente o que a API retorna
# vlxsam04 - Para sair dos círculos e resolver definitivamente

echo "🎯 DIAGNÓSTICO FINAL - API RESPONSE"
echo "=================================="

TENANT_SLUG="${1:-gruppen-it}"
ENROLLMENT_TOKEN="${2:-}"

if [ -z "$ENROLLMENT_TOKEN" ]; then
    echo "❌ ERRO: Token de enrollment obrigatório"
    echo "Uso: $0 <tenant-slug> <enrollment-token>"
    exit 1
fi

HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
API_SERVER="https://api.samureye.com.br"

echo "📋 Testando registro: $HOSTNAME ($IP_ADDRESS)"
echo ""

# Payload exato
PAYLOAD=$(cat <<EOF
{
    "tenantSlug": "$TENANT_SLUG",
    "enrollmentToken": "$ENROLLMENT_TOKEN",
    "hostname": "$HOSTNAME",
    "ipAddress": "$IP_ADDRESS"
}
EOF
)

echo "📤 ENVIANDO PARA API..."
echo "Endpoint: $API_SERVER/collector-api/register"
echo ""

# Requisição com debug completo
RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "$PAYLOAD" \
    "$API_SERVER/collector-api/register" \
    --connect-timeout 30 \
    --max-time 60)

# Separar response
HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

echo "📋 RESULTADO COMPLETO:"
echo "===================="
echo "Status HTTP: $HTTP_STATUS"
echo ""
echo "Response Body (RAW):"
echo "-------------------"
echo "$RESPONSE_BODY"
echo ""

if command -v jq >/dev/null 2>&1; then
    echo "Response Body (JSON Formatado):"
    echo "------------------------------"
    echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "Não é JSON válido"
    echo ""
fi

echo "🔍 ANÁLISE CRÍTICA:"
echo "==================="

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ Status 200 - API aceita o registro"
    
    # Buscar por qualquer campo que possa ser token
    echo ""
    echo "🔑 BUSCA POR TOKENS NA RESPOSTA:"
    echo ""
    
    # Listar todos os campos da resposta
    if command -v jq >/dev/null 2>&1; then
        echo "📝 TODOS OS CAMPOS RETORNADOS:"
        echo "$RESPONSE_BODY" | jq -r 'paths(scalars) as $p | "\($p | join(".")): \(getpath($p))"' 2>/dev/null || echo "Erro ao analisar JSON"
    fi
    
    echo ""
    echo "🔍 TENTATIVAS DE EXTRAÇÃO:"
    
    # Método 1: campos óbvios
    TOKEN1=$(echo "$RESPONSE_BODY" | jq -r '.token // empty' 2>/dev/null)
    echo "1. .token: '${TOKEN1:-VAZIO}'"
    
    TOKEN2=$(echo "$RESPONSE_BODY" | jq -r '.collector.token // empty' 2>/dev/null)
    echo "2. .collector.token: '${TOKEN2:-VAZIO}'"
    
    TOKEN3=$(echo "$RESPONSE_BODY" | jq -r '.authToken // empty' 2>/dev/null)
    echo "3. .authToken: '${TOKEN3:-VAZIO}'"
    
    # Método 2: busca por UUID pattern
    UUID_PATTERN='[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'
    TOKEN4=$(echo "$RESPONSE_BODY" | grep -oE "$UUID_PATTERN" | head -1)
    echo "4. UUID Pattern: '${TOKEN4:-VAZIO}'"
    
    # Método 3: qualquer string longa que pode ser token
    TOKEN5=$(echo "$RESPONSE_BODY" | grep -oE '"[a-zA-Z0-9_-]{20,}"' | head -1 | tr -d '"')
    echo "5. Long String: '${TOKEN5:-VAZIO}'"
    
    echo ""
    if [ -n "$TOKEN1" ] || [ -n "$TOKEN2" ] || [ -n "$TOKEN3" ] || [ -n "$TOKEN4" ] || [ -n "$TOKEN5" ]; then
        echo "✅ PELO MENOS UM TOKEN ENCONTRADO"
        FOUND_TOKEN="${TOKEN1:-${TOKEN2:-${TOKEN3:-${TOKEN4:-$TOKEN5}}}}"
        echo "   Token: ${FOUND_TOKEN:0:8}...${FOUND_TOKEN: -8}"
        echo ""
        echo "🎯 RESULTADO: Problema de EXTRAÇÃO no script register-collector.sh"
    else
        echo "❌ NENHUM TOKEN ENCONTRADO"
        echo ""
        echo "🎯 RESULTADO: API NÃO RETORNA TOKEN - Problema no backend"
        echo ""
        echo "💡 SOLUÇÕES POSSÍVEIS:"
        echo "1. Backend precisa ser corrigido para retornar token"
        echo "2. Implementar mecanismo alternativo de obtenção de token"
        echo "3. Usar token fixo/gerado localmente (temporário)"
    fi
    
else
    echo "❌ Status $HTTP_STATUS - Registro falhou"
    echo "Erro: $RESPONSE_BODY"
fi

echo ""
echo "🎯 CONCLUSÃO DEFINITIVA:"
echo "======================="

if [ "$HTTP_STATUS" = "200" ]; then
    if [ -n "$TOKEN1" ] || [ -n "$TOKEN2" ] || [ -n "$TOKEN3" ] || [ -n "$TOKEN4" ] || [ -n "$TOKEN5" ]; then
        echo "🔧 PROBLEMA: Script de registro não está extraindo token corretamente"
        echo "🚀 SOLUÇÃO: Atualizar script register-collector.sh"
    else
        echo "🔧 PROBLEMA: API não retorna token na resposta de registro"
        echo "🚀 SOLUÇÃO: Implementar workaround ou corrigir backend"
    fi
else
    echo "🔧 PROBLEMA: Registro falhando na API"
    echo "🚀 SOLUÇÃO: Verificar token de enrollment e configuração"
fi