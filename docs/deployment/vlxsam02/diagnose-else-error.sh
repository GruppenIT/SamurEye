#!/bin/bash

# ============================================================================
# DIAGNÓSTICO ERRO "Unexpected else" LINHA 236 - vlxsam02  
# ============================================================================
# Script para diagnosticar o erro "Unexpected 'else'" na linha 236 do server/routes.ts
# Análise de estrutura if/else mal formada
#
# Uso: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/diagnose-else-error.sh | bash
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
echo "🔍 DIAGNÓSTICO ERRO 'Unexpected else' LINHA 236"
echo "==============================================="
echo ""

if [ ! -f "$TARGET_FILE" ]; then
    error "❌ Arquivo não encontrado: $TARGET_FILE"
    exit 1
fi

cd "$WORKING_DIR" || error "❌ Não foi possível acessar $WORKING_DIR"

# ============================================================================
# 1. ANÁLISE ESPECÍFICA DA LINHA 236
# ============================================================================

log "🔍 Analisando linha 236 especificamente..."

# Extrair contexto amplo ao redor da linha 236
log "📋 Contexto da linha 236 (±15 linhas):"
echo "=========================================="
sed -n '221,251p' "$TARGET_FILE" | nl -v221
echo "=========================================="
echo ""

# Analisar especificamente a linha 236
line_236=$(sed -n '236p' "$TARGET_FILE")
log "🎯 Conteúdo da linha 236: '$line_236'"

# ============================================================================
# 2. ANÁLISE DA ESTRUTURA IF/ELSE
# ============================================================================

log "🔍 Analisando estrutura if/else ao redor da linha 236..."

# Procurar if correspondente em linhas anteriores
log "📍 Procurando if correspondente..."
found_if=""
for i in {235..200}; do
    line_content=$(sed -n "${i}p" "$TARGET_FILE")
    if echo "$line_content" | grep -q "if\s*(" || echo "$line_content" | grep -q "if\s*\s"; then
        found_if=$i
        log "✅ If encontrado na linha $i: $(echo "$line_content" | xargs)"
        break
    fi
done

if [ -z "$found_if" ]; then
    error "❌ If correspondente não encontrado para else na linha 236"
    
    # Procurar padrões problemáticos
    log "🔍 Procurando padrões problemáticos..."
    
    # Verificar se há chaves mal balanceadas antes da linha 236
    context_before=$(sed -n '200,235p' "$TARGET_FILE")
    open_braces=$(echo "$context_before" | grep -o '{' | wc -l)
    close_braces=$(echo "$context_before" | grep -o '}' | wc -l)
    
    log "📊 Nas linhas 200-235: { = $open_braces, } = $close_braces"
    
    if [ $open_braces -ne $close_braces ]; then
        error "❌ Chaves desbalanceadas antes da linha 236!"
    fi
fi

# ============================================================================
# 3. ANÁLISE DE BLOCOS DE CÓDIGO PRÓXIMOS
# ============================================================================

log "🔍 Analisando blocos de código próximos..."

# Verificar se há função/rota mal formada
for i in {235..200}; do
    line_content=$(sed -n "${i}p" "$TARGET_FILE")
    if echo "$line_content" | grep -q "app\.\(get\|post\|put\|delete\)\|function"; then
        log "📍 Função/rota na linha $i: $(echo "$line_content" | xargs)"
        
        # Mostrar bloco completo
        log "📋 Bloco da função (linhas $i-250):"
        sed -n "${i},250p" "$TARGET_FILE" | nl -v$i | head -20
        break
    fi
done

# ============================================================================
# 4. TESTE DE BUILD PARA CAPTURAR ERRO COMPLETO
# ============================================================================

log "🔨 Testando build para capturar erro completo..."

# Capturar output detalhado
build_output=$(npm run build 2>&1 || echo "BUILD_FAILED")

# Extrair informações do erro
if echo "$build_output" | grep -q "Unexpected.*else"; then
    error "🎯 ERRO CONFIRMADO - Unexpected else"
    echo "$build_output" | grep -A5 -B5 "Unexpected.*else"
    echo ""
fi

# ============================================================================
# 5. DETECÇÃO DE PADRÕES ESPECÍFICOS
# ============================================================================

log "🔍 Procurando padrões específicos que causam 'Unexpected else'..."

# Padrões problemáticos
patterns=(
    "}.*}.*else"
    "try.*}.*else"
    "function.*}.*}.*else"
    "async.*=>.*}.*else"
)

for pattern in "${patterns[@]}"; do
    if grep -P -A3 -B3 -n "$pattern" "$TARGET_FILE" >/dev/null 2>&1; then
        warn "⚠️ Padrão suspeito encontrado: $pattern"
        grep -P -A3 -B3 -n "$pattern" "$TARGET_FILE" | head -10 || true
        echo ""
    fi
done

# ============================================================================
# 6. ANÁLISE DE MIDDLEWARE INSERIDO
# ============================================================================

log "🔍 Verificando se middleware inserido causou o problema..."

# Verificar se há middleware próximo à linha problemática
if grep -n "MIDDLEWARE\|isLocalUserAuthenticated" "$TARGET_FILE" | head -5; then
    log "📍 Middleware encontrado no arquivo"
    
    # Verificar se middleware está próximo da linha 236
    middleware_lines=$(grep -n "isLocalUserAuthenticated\|MIDDLEWARE" "$TARGET_FILE" | cut -d: -f1)
    for line_num in $middleware_lines; do
        if [ $line_num -gt 200 ] && [ $line_num -lt 250 ]; then
            warn "⚠️ Middleware próximo à linha problemática: linha $line_num"
        fi
    done
fi

# ============================================================================
# 7. RECOMENDAÇÃO DE AÇÃO
# ============================================================================

log "💡 Recomendação baseada no diagnóstico:"
echo ""

# Determinar ação
if [ -z "$found_if" ]; then
    error "🎯 PROBLEMA: Else órfão - sem if correspondente"
    echo "   • O else na linha 236 não tem if correspondente"
    echo "   • Provável causa: Correção anterior removeu if acidentalmente"
    echo ""
    echo "🔧 AÇÃO NECESSÁRIA:"
    echo "   Execute correção completa de estrutura:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
else
    warn "🔧 PROBLEMA: Estrutura if/else mal formada"
    echo "   • If encontrado mas estrutura corrompida"
    echo ""
    echo "🔧 AÇÃO NECESSÁRIA:"
    echo "   Execute correção de sintaxe:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
fi

echo ""
log "🔍 Diagnóstico do erro else concluído"
echo "==============================================="

exit 1