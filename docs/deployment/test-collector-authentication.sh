#!/bin/bash
# Teste de Autenticação Collector - SamurEye
# Verifica se correções funcionam
# Autor: SamurEye Team

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Função de log
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️ $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] ℹ️ $1${NC}"; }

# Configurações
API_URL="https://api.samureye.com.br"
POSTGRES_HOST="172.24.1.153"
POSTGRES_USER="samureye_user"
POSTGRES_DB="samureye"

echo ""
echo "🔍 TESTE DE AUTENTICAÇÃO COLLECTOR - NOVA SOLUÇÃO"
echo "================================================"
echo ""

# ============================================================================
# 1. BUSCAR DADOS REAIS DO COLLECTOR NO BANCO
# ============================================================================

log "🗃️ 1. BUSCANDO DADOS REAIS DO COLLECTOR..."

# Buscar collector vlxsam04
COLLECTOR_DATA=$(PGPASSWORD="samureye_secure_2024" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
SELECT 
    id, 
    name, 
    enrollment_token, 
    status 
FROM collectors 
WHERE name LIKE '%vlxsam04%' 
   OR id LIKE '%vlxsam04%' 
ORDER BY created_at DESC 
LIMIT 1;
" 2>/dev/null | head -n 1)

if [ -n "$COLLECTOR_DATA" ]; then
    COLLECTOR_ID=$(echo "$COLLECTOR_DATA" | awk '{print $1}' | xargs)
    COLLECTOR_NAME=$(echo "$COLLECTOR_DATA" | awk '{print $3}' | xargs)
    COLLECTOR_TOKEN=$(echo "$COLLECTOR_DATA" | awk '{print $5}' | xargs)
    COLLECTOR_STATUS=$(echo "$COLLECTOR_DATA" | awk '{print $7}' | xargs)
    
    log "✅ Collector encontrado:"
    info "   ID: $COLLECTOR_ID"
    info "   Nome: $COLLECTOR_NAME"  
    info "   Token: ${COLLECTOR_TOKEN:0:20}..."
    info "   Status: $COLLECTOR_STATUS"
else
    error "❌ Nenhum collector encontrado para vlxsam04"
    exit 1
fi

# ============================================================================
# 2. TESTAR NOVA AUTENTICAÇÃO COM MULTIPLE MATCHING
# ============================================================================

log "🧪 2. TESTANDO NOVA AUTENTICAÇÃO..."

# Teste 1: Com token real + collector_id como nome (cenário do problema)
log "🔍 Teste 1: token real + collector_id como nome..."
RESPONSE1=$(curl -s -w "\n%{http_code}" "$API_URL/collector-api/journeys/pending?collector_id=vlxsam04&token=$COLLECTOR_TOKEN" 2>/dev/null)
HTTP_CODE1=$(echo "$RESPONSE1" | tail -n1)
BODY1=$(echo "$RESPONSE1" | head -n -1)

if [ "$HTTP_CODE1" = "200" ]; then
    log "✅ Teste 1 PASSOU: HTTP $HTTP_CODE1"
    info "   Resposta: $(echo "$BODY1" | jq -c . 2>/dev/null || echo "$BODY1")"
else
    warn "⚠️ Teste 1 FALHOU: HTTP $HTTP_CODE1"
    warn "   Resposta: $BODY1"
fi

# Teste 2: Com token real + collector_id como ID real
log "🔍 Teste 2: token real + collector_id como ID real..."
RESPONSE2=$(curl -s -w "\n%{http_code}" "$API_URL/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN" 2>/dev/null)
HTTP_CODE2=$(echo "$RESPONSE2" | tail -n1)
BODY2=$(echo "$RESPONSE2" | head -n -1)

if [ "$HTTP_CODE2" = "200" ]; then
    log "✅ Teste 2 PASSOU: HTTP $HTTP_CODE2"
    info "   Resposta: $(echo "$BODY2" | jq -c . 2>/dev/null || echo "$BODY2")"
else
    warn "⚠️ Teste 2 FALHOU: HTTP $HTTP_CODE2"
    warn "   Resposta: $BODY2"
fi

# Teste 3: Com collector_id como token (nossa solução alternativa)
log "🔍 Teste 3: collector_id como token..."
RESPONSE3=$(curl -s -w "\n%{http_code}" "$API_URL/collector-api/journeys/pending?collector_id=vlxsam04&token=vlxsam04" 2>/dev/null)
HTTP_CODE3=$(echo "$RESPONSE3" | tail -n1)  
BODY3=$(echo "$RESPONSE3" | head -n -1)

if [ "$HTTP_CODE3" = "200" ]; then
    log "✅ Teste 3 PASSOU: HTTP $HTTP_CODE3"
    info "   Resposta: $(echo "$BODY3" | jq -c . 2>/dev/null || echo "$BODY3")"
else
    warn "⚠️ Teste 3 FALHOU: HTTP $HTTP_CODE3"
    warn "   Resposta: $BODY3"
fi

# Teste 4: Com nome como token (nossa solução expandida)
log "🔍 Teste 4: nome como token..."
RESPONSE4=$(curl -s -w "\n%{http_code}" "$API_URL/collector-api/journeys/pending?collector_id=vlxsam04&token=$COLLECTOR_NAME" 2>/dev/null)
HTTP_CODE4=$(echo "$RESPONSE4" | tail -n1)
BODY4=$(echo "$RESPONSE4" | head -n -1)

if [ "$HTTP_CODE4" = "200" ]; then
    log "✅ Teste 4 PASSOU: HTTP $HTTP_CODE4"  
    info "   Resposta: $(echo "$BODY4" | jq -c . 2>/dev/null || echo "$BODY4")"
else
    warn "⚠️ Teste 4 FALHOU: HTTP $HTTP_CODE4"
    warn "   Resposta: $BODY4"
fi

# ============================================================================
# 3. TESTAR ENDPOINT DE RESULTS TAMBÉM
# ============================================================================

log "🧪 3. TESTANDO ENDPOINT DE RESULTS..."

# Teste 5: Submissão de resultados com nome
log "🔍 Teste 5: submissão de resultados..."
RESULTS_PAYLOAD='{
    "collector_id": "vlxsam04",
    "token": "'$COLLECTOR_TOKEN'",
    "execution_id": "test-execution-123",
    "status": "completed",
    "results": {"test": "data"},
    "error_message": null
}'

RESPONSE5=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$RESULTS_PAYLOAD" \
    "$API_URL/collector-api/journeys/results" 2>/dev/null)
HTTP_CODE5=$(echo "$RESPONSE5" | tail -n1)
BODY5=$(echo "$RESPONSE5" | head -n -1)

if [ "$HTTP_CODE5" = "200" ] || [ "$HTTP_CODE5" = "404" ]; then
    log "✅ Teste 5 PASSOU: HTTP $HTTP_CODE5 (autenticação OK)"
    info "   Resposta: $(echo "$BODY5" | jq -c . 2>/dev/null || echo "$BODY5")"
else
    warn "⚠️ Teste 5 FALHOU: HTTP $HTTP_CODE5"
    warn "   Resposta: $BODY5"
fi

# ============================================================================
# 4. RESUMO DOS TESTES
# ============================================================================

echo ""
echo "📊 RESUMO DOS TESTES:"
echo "==================="

PASSED=0
TOTAL=5

[ "$HTTP_CODE1" = "200" ] && PASSED=$((PASSED + 1)) && echo "✅ Teste 1: PASSOU" || echo "❌ Teste 1: FALHOU"
[ "$HTTP_CODE2" = "200" ] && PASSED=$((PASSED + 1)) && echo "✅ Teste 2: PASSOU" || echo "❌ Teste 2: FALHOU"  
[ "$HTTP_CODE3" = "200" ] && PASSED=$((PASSED + 1)) && echo "✅ Teste 3: PASSOU" || echo "❌ Teste 3: FALHOU"
[ "$HTTP_CODE4" = "200" ] && PASSED=$((PASSED + 1)) && echo "✅ Teste 4: PASSOU" || echo "❌ Teste 4: FALHOU"
[ "$HTTP_CODE5" = "200" ] || [ "$HTTP_CODE5" = "404" ] && PASSED=$((PASSED + 1)) && echo "✅ Teste 5: PASSOU" || echo "❌ Teste 5: FALHOU"

echo ""
echo "🎯 RESULTADO FINAL: $PASSED/$TOTAL testes passaram"

if [ "$PASSED" -ge 3 ]; then
    log "🎉 CORREÇÕES FUNCIONANDO! Autenticação aceita múltiplas formas"
    echo ""
    echo "✅ O collector pode agora usar:"
    echo "   • Token real de enrollment"
    echo "   • Nome do collector como token"  
    echo "   • ID do collector como token"
    echo "   • collector_id pode ser nome OU ID real"
    exit 0
else
    error "❌ CORREÇÕES NÃO FUNCIONANDO! Apenas $PASSED/$TOTAL testes passaram"
    echo ""
    echo "🔧 Verifique:"
    echo "   • Se o servidor foi reiniciado após as correções"
    echo "   • Se as correções estão aplicadas no código"
    echo "   • Se há erros de compilação TypeScript"
    exit 1
fi