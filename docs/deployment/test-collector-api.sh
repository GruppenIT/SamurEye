#!/bin/bash

echo "🧪 TESTE DIRETO DA API COLLECTOR - SamurEye"  
echo "==========================================="

# Função para log
log() { echo "[$(date +'%H:%M:%S')] $1"; }
error() { echo "[$(date +'%H:%M:%S')] ❌ $1"; }
success() { echo "[$(date +'%H:%M:%S')] ✅ $1"; }

if [ $# -lt 3 ]; then
    echo "Uso: $0 <API_BASE> <COLLECTOR_ID> <TOKEN>"
    echo "Exemplo: $0 https://api.samureye.com.br vlxsam04 e8e6d611...0b53190b"
    exit 1
fi

API_BASE="$1"
COLLECTOR_ID="$2"
TOKEN="$3"

log "🎯 Testando endpoint collector-api/journeys/pending"
log "   • API: $API_BASE"
log "   • Collector ID: $COLLECTOR_ID"  
log "   • Token: ${TOKEN:0:8}...${TOKEN: -8}"

# Teste 1: Endpoint básico de saúde
log "🔍 Teste 1: Verificando API básica..."
if curl -s --max-time 10 "$API_BASE/api/health" > /dev/null 2>&1; then
    success "API respondendo"
else
    error "API não acessível"
    exit 1
fi

# Teste 2: Endpoint collector-api/journeys/pending
log "🔍 Teste 2: Testando endpoint de jornadas pendentes..."
RESPONSE=$(curl -s -w "HTTPCODE:%{http_code}" \
    "$API_BASE/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$TOKEN" 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | sed -n 's/.*HTTPCODE:\([0-9]*\).*/\1/p')
BODY=$(echo "$RESPONSE" | sed 's/HTTPCODE:[0-9]*$//')

log "   • HTTP Code: $HTTP_CODE"
log "   • Response Body: $BODY"

case "$HTTP_CODE" in
    200)
        success "✅ ENDPOINT FUNCIONANDO!"
        echo "   • Jornadas encontradas: $BODY"
        ;;
    401)
        error "❌ TOKEN REJEITADO (401 Unauthorized)"
        echo "   • Error: $BODY"
        
        # Diagnóstico adicional para 401
        log "🔍 Diagnosticando problema de token..."
        
        # Testar se é problema de parâmetros
        log "   Testando sem parâmetros..."
        NO_PARAMS=$(curl -s -w "HTTPCODE:%{http_code}" \
            "$API_BASE/collector-api/journeys/pending" 2>/dev/null)
        NO_PARAMS_CODE=$(echo "$NO_PARAMS" | sed -n 's/.*HTTPCODE:\([0-9]*\).*/\1/p')
        NO_PARAMS_BODY=$(echo "$NO_PARAMS" | sed 's/HTTPCODE:[0-9]*$//')
        log "   • Sem parâmetros: $NO_PARAMS_CODE - $NO_PARAMS_BODY"
        
        # Testar com parâmetros válidos mas token inválido
        log "   Testando com token obviamente inválido..."
        INVALID_TOKEN=$(curl -s -w "HTTPCODE:%{http_code}" \
            "$API_BASE/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=invalid123" 2>/dev/null)
        INVALID_CODE=$(echo "$INVALID_TOKEN" | sed -n 's/.*HTTPCODE:\([0-9]*\).*/\1/p')  
        INVALID_BODY=$(echo "$INVALID_TOKEN" | sed 's/HTTPCODE:[0-9]*$//')
        log "   • Token inválido: $INVALID_CODE - $INVALID_BODY"
        ;;
    404)
        error "❌ ENDPOINT NÃO ENCONTRADO (404)"
        echo "   • Verifique se o servidor vlxsam02 foi atualizado"
        ;;
    500)
        error "❌ ERRO INTERNO DO SERVIDOR (500)"
        echo "   • Error: $BODY"
        echo "   • Verifique logs do servidor vlxsam02"
        ;;
    *)
        error "❌ ERRO INESPERADO ($HTTP_CODE)"
        echo "   • Response: $BODY"
        ;;
esac

# Teste 3: Verificar se é problema de database/token expiry
if [ "$HTTP_CODE" = "401" ]; then
    log "🔍 Teste 3: Consultando banco de dados diretamente..."
    
    # Conectar no banco para ver status do token
    PGPASSWORD="SamurEye2024!" psql -h 192.168.100.153 -U samureye -d samureye -c \
        "SELECT id, name, status, 
                enrollment_token, 
                enrollment_token_expires,
                enrollment_token_expires > NOW() as token_valid,
                created_at, updated_at 
         FROM collectors 
         WHERE enrollment_token = '$TOKEN' OR id = '$COLLECTOR_ID';" 2>/dev/null
         
    if [ $? -eq 0 ]; then
        success "Consulta ao banco realizada - verifique dados acima"
    else
        error "Falha ao consultar banco de dados"
    fi
fi

echo ""
echo "📋 RESUMO DO TESTE:"
if [ "$HTTP_CODE" = "200" ]; then
    success "✅ ENDPOINT FUNCIONANDO CORRETAMENTE"
elif [ "$HTTP_CODE" = "401" ]; then
    error "❌ PROBLEMA DE AUTENTICAÇÃO"
    echo "   💡 Possíveis causas:"
    echo "      • Token expirado no banco de dados"
    echo "      • Correções não aplicadas no servidor vlxsam02"
    echo "      • Problema na verificação de token"
else
    error "❌ PROBLEMA NO SERVIDOR OU ENDPOINT"  
fi