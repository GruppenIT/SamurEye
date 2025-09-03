#!/bin/bash

# ============================================================================
# DIAGNÓSTICO ESPECÍFICO LINHA 656 - vlxsam02
# ============================================================================
# Script para diagnosticar o erro "Unexpected }" na linha 656 do server/routes.ts
# Análise precisa da estrutura de código ao redor da linha problemática
#
# Uso: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/diagnose-line-656-error.sh | bash
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

# Configurações
APP_DIR="/opt/samureye"
WORKING_DIR="$APP_DIR/SamurEye"
TARGET_FILE="$WORKING_DIR/server/routes.ts"

echo ""
echo "🔍 DIAGNÓSTICO ESPECÍFICO LINHA 656 - vlxsam02"
echo "=============================================="
echo ""

if [ ! -f "$TARGET_FILE" ]; then
    error "❌ Arquivo não encontrado: $TARGET_FILE"
fi

cd "$WORKING_DIR" || error "❌ Não foi possível acessar $WORKING_DIR"

# ============================================================================
# 1. ANÁLISE ESPECÍFICA DA LINHA 656
# ============================================================================

log "🔍 Analisando linha 656 especificamente..."

# Extrair contexto amplo ao redor da linha 656
log "📋 Contexto da linha 656 (±20 linhas):"
echo "=========================================="
sed -n '636,676p' "$TARGET_FILE" | nl -v636
echo "=========================================="
echo ""

# Analisar especificamente a linha 656
line_656=$(sed -n '656p' "$TARGET_FILE")
log "🎯 Conteúdo da linha 656: '$line_656'"

if echo "$line_656" | grep -q "} catch (error) {"; then
    warn "⚠️ Linha 656 contém estrutura try/catch"
    
    # Encontrar o try correspondente
    log "🔍 Procurando try correspondente..."
    
    # Análise reversa para encontrar o try
    try_line=""
    for i in {655..600}; do
        line_content=$(sed -n "${i}p" "$TARGET_FILE")
        if echo "$line_content" | grep -q "try {"; then
            try_line=$i
            break
        fi
    done
    
    if [ ! -z "$try_line" ]; then
        log "✅ Try encontrado na linha $try_line"
        log "📋 Bloco try/catch (linhas $try_line-660):"
        sed -n "${try_line},660p" "$TARGET_FILE" | nl -v$try_line
        
        # Contar chaves dentro do bloco try/catch
        try_catch_block=$(sed -n "${try_line},660p" "$TARGET_FILE")
        open_braces_block=$(echo "$try_catch_block" | grep -o '{' | wc -l)
        close_braces_block=$(echo "$try_catch_block" | grep -o '}' | wc -l)
        
        log "📊 No bloco try/catch: { = $open_braces_block, } = $close_braces_block"
        
        if [ $open_braces_block -ne $close_braces_block ]; then
            error "❌ BLOCO TRY/CATCH DESBALANCEADO!"
        fi
        
    else
        error "❌ Try correspondente não encontrado para o catch na linha 656"
    fi
    
elif echo "$line_656" | grep -q "}"; then
    warn "⚠️ Linha 656 contém apenas chave de fechamento"
    
    # Analisar o que deveria fechar
    log "🔍 Analisando estrutura que deveria ser fechada..."
    
    # Procurar função/bloco que está sendo fechado
    for i in {655..600}; do
        line_content=$(sed -n "${i}p" "$TARGET_FILE")
        if echo "$line_content" | grep -q "app\.get\|app\.post\|function\|if\|try"; then
            log "📍 Possível início do bloco na linha $i: $(echo "$line_content" | xargs)"
            break
        fi
    done
fi

# ============================================================================
# 2. ANÁLISE DE ESTRUTURA DE FUNÇÃO/ROTA
# ============================================================================

log "🔍 Analisando estrutura de rotas ao redor da linha 656..."

# Encontrar início da rota atual
current_route_start=""
for i in {655..600}; do
    line_content=$(sed -n "${i}p" "$TARGET_FILE")
    if echo "$line_content" | grep -q "app\.\(get\|post\|put\|delete\)"; then
        current_route_start=$i
        route_definition=$(echo "$line_content" | xargs)
        log "📍 Rota atual inicia na linha $i: $route_definition"
        break
    fi
done

if [ ! -z "$current_route_start" ]; then
    # Analisar toda a rota
    log "📋 Rota completa (linhas $current_route_start-665):"
    sed -n "${current_route_start},665p" "$TARGET_FILE" | nl -v$current_route_start
    
    # Verificar se é rota async
    route_block=$(sed -n "${current_route_start},665p" "$TARGET_FILE")
    if echo "$route_block" | grep -q "async.*=>"; then
        log "✅ Rota async detectada"
        
        # Contar async function braces
        async_open=$(echo "$route_block" | grep -o '{' | wc -l)
        async_close=$(echo "$route_block" | grep -o '}' | wc -l)
        
        log "📊 Na rota async: { = $async_open, } = $async_close"
        
        if [ $async_open -ne $async_close ]; then
            error "❌ ROTA ASYNC DESBALANCEADA!"
        fi
    fi
fi

# ============================================================================
# 3. DETECÇÃO DE PADRÕES ESPECÍFICOS PROBLEMÁTICOS
# ============================================================================

log "🔍 Procurando padrões específicos que causam 'Unexpected }'..."

# Padrões problemáticos específicos
problematic_patterns=(
    "async.*=>.*{.*}.*}.*catch"
    "try.*{.*}.*}.*}.*catch.*{"
    "app\.get.*async.*=>.*{.*try.*{.*}.*}.*}.*catch"
    "}.*}.*}.*catch.*{"
)

for pattern in "${problematic_patterns[@]}"; do
    if grep -P -A5 -B5 -n "$pattern" "$TARGET_FILE" >/dev/null 2>&1; then
        error "🎯 PADRÃO PROBLEMÁTICO DETECTADO: $pattern"
        grep -P -A5 -B5 -n "$pattern" "$TARGET_FILE" | head -15
        echo ""
    fi
done

# ============================================================================
# 4. ANÁLISE ESPECÍFICA DO MIDDLEWARE isLocalUserAuthenticated
# ============================================================================

log "🔍 Verificando se middleware isLocalUserAuthenticated está causando o problema..."

# Verificar se middleware existe e está bem formado
if grep -q "function isLocalUserAuthenticated" "$TARGET_FILE"; then
    log "✅ Middleware isLocalUserAuthenticated encontrado"
    
    # Localizar e analisar middleware
    middleware_start=$(grep -n "function isLocalUserAuthenticated" "$TARGET_FILE" | cut -d: -f1)
    
    log "📍 Middleware inicia na linha $middleware_start"
    
    # Mostrar middleware completo
    log "📋 Middleware completo:"
    sed -n "${middleware_start},$((middleware_start + 25))p" "$TARGET_FILE" | nl -v$middleware_start
    
    # Verificar se middleware está interferindo com outras estruturas
    if [ $middleware_start -gt 600 ] && [ $middleware_start -lt 700 ]; then
        warn "⚠️ Middleware declarado próximo à linha problemática - possível interferência"
    fi
    
else
    error "❌ Middleware isLocalUserAuthenticated não encontrado"
fi

# ============================================================================
# 5. TESTE ESPECÍFICO DE BUILD PARA CAPTURAR ERRO EXATO
# ============================================================================

log "🔨 Executando teste específico de build para capturar erro..."

# Build com output detalhado
build_output=$(npm run build 2>&1 || echo "BUILD_FAILED")

# Extrair erro específico da linha 656
line_656_error=$(echo "$build_output" | grep -A3 -B3 "656" | head -10)

if [ ! -z "$line_656_error" ]; then
    error "🎯 ERRO ESPECÍFICO NA LINHA 656:"
    echo "$line_656_error"
    echo ""
fi

# ============================================================================
# 6. SOLUÇÃO RECOMENDADA
# ============================================================================

log "💡 Análise de solução baseada no diagnóstico:"
echo ""

# Determinar solução específica
if echo "$line_656" | grep -q "} catch (error) {"; then
    error "🎯 PROBLEMA: Estrutura try/catch mal formada"
    echo "   • O catch na linha 656 não tem try correspondente balanceado"
    echo "   • Provável causa: Middleware patch introduziu chaves extras"
    echo ""
    echo "🔧 AÇÃO NECESSÁRIA:"
    echo "   Execute correção específica para try/catch:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
    echo ""
    
elif grep -P "}.*}.*}.*catch" "$TARGET_FILE" >/dev/null 2>&1; then
    error "🎯 PROBLEMA: Chaves extras antes do catch"
    echo "   • Múltiplas chaves de fechamento antes do catch"
    echo "   • Estrutura de função/rota mal fechada"
    echo ""
    echo "🔧 AÇÃO NECESSÁRIA:"
    echo "   Execute correção de estrutura:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
    echo ""
    
else
    warn "⚠️ PROBLEMA: Estrutura de código complexa"
    echo "   • Erro de sintaxe não identificado por padrões comuns"
    echo "   • Necessária correção manual ou rebuild completo"
    echo ""
    echo "🔧 AÇÃO NECESSÁRIA:"
    echo "   Execute rebuild completo:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
fi

echo ""
log "🔍 Diagnóstico da linha 656 concluído"
echo "=============================================="

# Exit code baseado na severidade
if echo "$build_output" | grep -q "BUILD_FAILED.*ERROR"; then
    exit 2  # Erro crítico
else
    exit 1  # Problema detectado
fi