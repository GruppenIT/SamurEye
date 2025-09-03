#!/bin/bash

# ============================================================================
# DIAGNÓSTICO DE ERROS DE SINTAXE - vlxsam02
# ============================================================================
# Script para diagnosticar e identificar problemas de sintaxe JavaScript/TypeScript
# no código da aplicação SamurEye após aplicação de patches
#
# Uso: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/diagnose-syntax-error.sh | bash
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
SERVICE_NAME="samureye-app"

echo ""
echo "🔍 DIAGNÓSTICO DE ERROS DE SINTAXE - vlxsam02"
echo "============================================="
echo ""

# ============================================================================
# 1. VERIFICAÇÃO BÁSICA DO AMBIENTE
# ============================================================================

log "🔍 Verificando ambiente e estrutura..."

if [ ! -d "$WORKING_DIR" ]; then
    error "❌ Diretório da aplicação não encontrado: $WORKING_DIR"
fi

cd "$WORKING_DIR" || error "❌ Não foi possível acessar $WORKING_DIR"

# ============================================================================
# 2. TESTE DE BUILD DIRETO PARA CAPTURAR ERROS
# ============================================================================

log "🔨 Testando build para capturar erros de sintaxe..."

# Capturar output do build
build_output=$(npm run build 2>&1 || echo "BUILD_FAILED")

# Verificar se houve erro
if echo "$build_output" | grep -q "BUILD_FAILED\|ERROR\|error"; then
    warn "⚠️ Build falhou - analisando erros..."
    
    # Extrair erros específicos
    echo "$build_output" | grep -A5 -B5 "ERROR\|error\|Unexpected" || true
    echo ""
    
    # Verificar se é erro de sintaxe específico
    if echo "$build_output" | grep -q "Unexpected"; then
        error "🎯 ERRO DE SINTAXE DETECTADO"
        
        # Extrair linha problemática
        syntax_error=$(echo "$build_output" | grep -A2 -B1 "Unexpected" | head -5)
        echo "$syntax_error"
        echo ""
        
        # Extrair arquivo e linha
        if echo "$syntax_error" | grep -q "server/routes.ts"; then
            error_line=$(echo "$syntax_error" | grep -o ":[0-9]*:" | head -1 | tr -d ':')
            if [ ! -z "$error_line" ]; then
                log "📍 Analisando linha $error_line em server/routes.ts:"
                
                # Mostrar contexto da linha problemática
                if [ -f "server/routes.ts" ]; then
                    log "🔍 Contexto ao redor da linha $error_line:"
                    
                    # Mostrar 10 linhas antes e depois do erro
                    start_line=$((error_line - 10))
                    end_line=$((error_line + 10))
                    
                    if [ $start_line -lt 1 ]; then start_line=1; fi
                    
                    sed -n "${start_line},${end_line}p" server/routes.ts | nl -v$start_line
                    echo ""
                    
                    # Contar chaves para detectar desbalanceamento
                    log "🔍 Analisando balanceamento de chaves..."
                    
                    # Contar { e } no arquivo
                    open_braces=$(grep -o '{' server/routes.ts | wc -l)
                    close_braces=$(grep -o '}' server/routes.ts | wc -l)
                    
                    log "📊 Chaves abertas: $open_braces"
                    log "📊 Chaves fechadas: $close_braces"
                    
                    if [ $open_braces -ne $close_braces ]; then
                        error "❌ DESBALANCEAMENTO DE CHAVES DETECTADO!"
                        diff_braces=$((open_braces - close_braces))
                        if [ $diff_braces -gt 0 ]; then
                            warn "⚠️ Faltam $diff_braces chaves de fechamento '}'"
                        else
                            diff_braces=$((diff_braces * -1))
                            warn "⚠️ Excesso de $diff_braces chaves de fechamento '}'"
                        fi
                    else
                        log "✅ Balanceamento de chaves OK"
                    fi
                fi
            fi
        fi
        
    fi
else
    log "✅ Build executou sem erros de sintaxe"
fi

# ============================================================================
# 3. VALIDAÇÃO TYPESCRIPT ESPECÍFICA
# ============================================================================

log "📋 Executando validação TypeScript..."

# Tentar compilar apenas o TypeScript
ts_check=$(npx tsc --noEmit --skipLibCheck 2>&1 || echo "TS_ERROR")

if echo "$ts_check" | grep -q "TS_ERROR\|error"; then
    warn "⚠️ Erros TypeScript detectados:"
    echo "$ts_check" | grep -v "TS_ERROR" | head -10
    echo ""
else
    log "✅ Validação TypeScript OK"
fi

# ============================================================================
# 4. VERIFICAÇÃO DE PADRÕES PROBLEMÁTICOS ESPECÍFICOS
# ============================================================================

log "🔍 Procurando padrões problemáticos específicos..."

# Verificar padrões que podem causar problemas
problematic_patterns=(
    "function.*isLocalUserAuthenticated.*{.*}.*app\.get"
    "isLocalUserAuthenticated.*function"
    "async.*isLocalUserAuthenticated.*=>"
    "}\s*}\s*}\s*}.*catch"
    "try.*{.*}.*}.*}.*catch"
)

for pattern in "${problematic_patterns[@]}"; do
    if grep -P "$pattern" server/routes.ts >/dev/null 2>&1; then
        warn "⚠️ Padrão problemático encontrado: $pattern"
        grep -P -n -A3 -B3 "$pattern" server/routes.ts 2>/dev/null | head -10 || true
        echo ""
    fi
done

# Procurar por blocos try/catch desbalanceados
log "🔍 Verificando blocos try/catch..."

try_count=$(grep -c "try {" server/routes.ts 2>/dev/null || echo "0")
catch_count=$(grep -c "} catch" server/routes.ts 2>/dev/null || echo "0")

log "📊 Blocos try: $try_count"
log "📊 Blocos catch: $catch_count"

if [ "$try_count" -ne "$catch_count" ]; then
    error "❌ Desbalanceamento try/catch detectado!"
else
    log "✅ Blocos try/catch balanceados"
fi

# ============================================================================
# 5. ANÁLISE DA ESTRUTURA MIDDLEWARE
# ============================================================================

log "🔍 Analisando declaração do middleware isLocalUserAuthenticated..."

if grep -q "function isLocalUserAuthenticated" server/routes.ts; then
    log "✅ Middleware isLocalUserAuthenticated encontrado"
    
    # Verificar se está bem formado
    middleware_structure=$(grep -A20 "function isLocalUserAuthenticated" server/routes.ts)
    
    # Contar chaves no middleware
    middleware_open=$(echo "$middleware_structure" | grep -o '{' | wc -l)
    middleware_close=$(echo "$middleware_structure" | grep -o '}' | wc -l)
    
    log "📊 Chaves no middleware - abertas: $middleware_open, fechadas: $middleware_close"
    
    if [ $middleware_open -ne $middleware_close ]; then
        error "❌ Middleware mal formado - chaves desbalanceadas"
        echo "$middleware_structure"
    fi
    
elif grep -q "isLocalUserAuthenticated" server/routes.ts; then
    warn "⚠️ Referência a isLocalUserAuthenticated encontrada, mas sem declaração function"
    
    # Mostrar onde está sendo usado
    log "📍 Usos do middleware:"
    grep -n "isLocalUserAuthenticated" server/routes.ts | head -5
    
else
    warn "⚠️ Middleware isLocalUserAuthenticated não encontrado"
fi

# ============================================================================
# 6. RECOMENDAÇÕES DE AÇÃO
# ============================================================================

log "💡 Recomendações baseadas no diagnóstico:"
echo ""

# Determinar ações baseadas nos problemas encontrados
if echo "$build_output" | grep -q "Unexpected.*}"; then
    error "🎯 AÇÃO NECESSÁRIA: Corrigir chaves desbalanceadas"
    echo "   • Problema: Chave '}' inesperada detectada"
    echo "   • Causa provável: Patch do middleware criou sintaxe inválida"
    echo "   • Solução: Execute script de correção de sintaxe:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
elif echo "$build_output" | grep -q "Unexpected"; then
    warn "🔧 AÇÃO NECESSÁRIA: Corrigir erro de sintaxe"
    echo "   • Execute script de correção específica"
elif [ "$try_count" -ne "$catch_count" ]; then
    warn "🔧 AÇÃO NECESSÁRIA: Corrigir blocos try/catch"
    echo "   • Desbalanceamento detectado nos blocos try/catch"
elif ! grep -q "function isLocalUserAuthenticated" server/routes.ts; then
    warn "🔧 AÇÃO NECESSÁRIA: Corrigir declaração de middleware"
    echo "   • Middleware isLocalUserAuthenticated não declarado corretamente"
else
    log "✅ Nenhum problema crítico de sintaxe detectado"
    echo "   • Aplicação deve compilar normalmente"
fi

echo ""
log "🔍 Diagnóstico de sintaxe concluído"
echo "============================================="

# Exit com código baseado na severidade
if echo "$build_output" | grep -q "BUILD_FAILED.*ERROR"; then
    exit 2  # Erro crítico de build
elif echo "$ts_check" | grep -q "TS_ERROR"; then
    exit 1  # Erro TypeScript
else
    exit 0  # OK
fi