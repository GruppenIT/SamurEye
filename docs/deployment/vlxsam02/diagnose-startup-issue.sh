#!/bin/bash

# ============================================================================
# DIAGNÓSTICO DE PROBLEMAS DE INICIALIZAÇÃO - vlxsam02
# ============================================================================
# Script para diagnosticar falhas de inicialização da aplicação SamurEye
# Identifica problemas de TDZ, dependências ausentes, conectividade DB e mais
#
# Uso: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/diagnose-startup-issue.sh | bash
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
POSTGRES_HOST="172.24.1.153"
POSTGRES_PORT="5432"

echo ""
echo "🔍 DIAGNÓSTICO DE INICIALIZAÇÃO - vlxsam02"
echo "=========================================="
echo ""

# ============================================================================
# 1. VERIFICAÇÃO BÁSICA DO AMBIENTE
# ============================================================================

log "🔍 Verificando ambiente básico..."

# Verificar Node.js e npm
node_version=$(node --version 2>/dev/null || echo "not found")
npm_version=$(npm --version 2>/dev/null || echo "not found")

if [[ "$node_version" != "not found" ]] && [[ "$npm_version" != "not found" ]]; then
    log "✅ Node.js: $node_version"
    log "✅ npm: $npm_version"
else
    error "❌ Node.js ou npm não instalados"
fi

# Verificar estrutura de diretórios
if [ -d "$WORKING_DIR" ]; then
    log "✅ Diretório da aplicação encontrado: $WORKING_DIR"
else
    error "❌ Diretório da aplicação não encontrado: $WORKING_DIR"
fi

if [ -f "$WORKING_DIR/package.json" ]; then
    log "✅ package.json encontrado"
else
    error "❌ package.json não encontrado"
fi

if [ -f "$WORKING_DIR/.env" ]; then
    log "✅ Arquivo .env encontrado"
else
    warn "⚠️ Arquivo .env não encontrado"
fi

# ============================================================================
# 2. VERIFICAÇÃO DE CONECTIVIDADE COM BANCO DE DADOS
# ============================================================================

log "🗃️ Verificando conectividade PostgreSQL..."

if nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    log "✅ PostgreSQL acessível em $POSTGRES_HOST:$POSTGRES_PORT"
    
    # Testar autenticação
    if PGPASSWORD="samureye_secure_2024" psql -h "$POSTGRES_HOST" -U "samureye_user" -d "samureye" -c "SELECT version();" >/dev/null 2>&1; then
        log "✅ Autenticação PostgreSQL funcionando"
    else
        warn "⚠️ Problema de autenticação PostgreSQL"
    fi
else
    error "❌ PostgreSQL não acessível em $POSTGRES_HOST:$POSTGRES_PORT"
fi

# ============================================================================
# 3. VERIFICAÇÃO DO BUILD DA APLICAÇÃO
# ============================================================================

log "🔨 Verificando build da aplicação..."

cd "$WORKING_DIR" 2>/dev/null || error "❌ Não foi possível acessar $WORKING_DIR"

if [ -f "dist/index.js" ]; then
    log "✅ Build encontrado: dist/index.js"
    
    # Verificar tamanho do build
    build_size=$(ls -lh dist/index.js | awk '{print $5}')
    log "ℹ️ Tamanho do build: $build_size"
    
    # PRÉ-TESTE CRÍTICO: Verificar se o módulo pode ser importado
    log "🔍 Testando importação do módulo..."
    
    test_result=$(timeout 30s node -e "
        import('./dist/index.js')
            .then(() => {
                console.log('✅ Módulo importado com sucesso');
                process.exit(0);
            })
            .catch(e => {
                console.error('❌ ERRO DE IMPORTAÇÃO:', e.message);
                if (e.stack) {
                    console.error('Stack trace:', e.stack);
                }
                process.exit(1);
            });
    " 2>&1)
    
    echo "$test_result"
    
    if echo "$test_result" | grep -q "Cannot access.*before initialization"; then
        error "❌ TEMPORAL DEAD ZONE (TDZ) DETECTADO - Problema de inicialização de variáveis"
        
        # Extrair qual símbolo está causando problema
        problematic_symbol=$(echo "$test_result" | grep -o "Cannot access '[^']*'" | head -1 | cut -d"'" -f2)
        if [ ! -z "$problematic_symbol" ]; then
            warn "🎯 Símbolo problemático: $problematic_symbol"
            
            # Procurar no arquivo onde está definido
            if grep -n "$problematic_symbol" dist/index.js >/dev/null 2>&1; then
                info "📍 Encontrado no build - verificando declaração vs uso:"
                grep -n "$problematic_symbol" dist/index.js | head -5
            fi
        fi
    elif echo "$test_result" | grep -q "✅ Módulo importado com sucesso"; then
        log "✅ Módulo pode ser importado sem problemas"
    else
        warn "⚠️ Outros erros de importação detectados"
    fi
    
else
    error "❌ Build não encontrado - execute npm run build primeiro"
fi

# ============================================================================
# 4. VERIFICAÇÃO DE DEPENDÊNCIAS yjs/y-protocols
# ============================================================================

log "📦 Verificando dependências yjs/y-protocols..."

# Verificar no package.json se são dependências declaradas
yjs_in_package=$(grep -c '"yjs":\|"y-protocols":' package.json 2>/dev/null || echo "0")
if [ "$yjs_in_package" -gt 0 ]; then
    warn "⚠️ yjs/y-protocols encontrados em package.json"
else
    log "✅ yjs/y-protocols NÃO estão em package.json (correto)"
fi

# Verificar no código se há uso desses pacotes
yjs_usage=$(find server/ client/ -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" 2>/dev/null | xargs grep -l "import.*yjs\|import.*y-protocols\|require.*yjs\|require.*y-protocols" 2>/dev/null | wc -l)
if [ "$yjs_usage" -gt 0 ]; then
    warn "⚠️ Uso de yjs/y-protocols encontrado no código"
    find server/ client/ -name "*.ts" -o -name "*.tsx" 2>/dev/null | xargs grep -l "import.*yjs\|import.*y-protocols" 2>/dev/null || true
else
    log "✅ Nenhum uso de yjs/y-protocols no código (correto)"
fi

# Verificar no node_modules
if [ -d "node_modules/yjs" ] || [ -d "node_modules/y-protocols" ]; then
    info "ℹ️ yjs/y-protocols estão instalados em node_modules"
else
    log "✅ yjs/y-protocols NÃO estão em node_modules (correto)"
fi

# ============================================================================
# 5. VERIFICAÇÃO DO SERVIÇO SYSTEMD
# ============================================================================

log "🔧 Verificando serviço systemd..."

if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    log "✅ Serviço $SERVICE_NAME encontrado"
    
    # Status do serviço
    service_status=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "unknown")
    log "ℹ️ Status do serviço: $service_status"
    
    if [ "$service_status" = "failed" ]; then
        warn "⚠️ Serviço em estado FAILED - verificando logs..."
        
        # Últimos logs de erro
        log "📋 Últimos erros do serviço:"
        journalctl -u "$SERVICE_NAME" --no-pager -n 20 | tail -10 || true
        
        # Procurar por padrões específicos de erro
        if journalctl -u "$SERVICE_NAME" --no-pager -n 50 | grep -q "Cannot access.*before initialization"; then
            error "❌ CONFIRMADO: Erro TDZ nos logs do systemd"
        fi
        
        if journalctl -u "$SERVICE_NAME" --no-pager -n 50 | grep -q "isLocalUserAuthenticated"; then
            error "❌ CONFIRMADO: Problema com middleware isLocalUserAuthenticated"
        fi
    fi
    
else
    warn "⚠️ Serviço $SERVICE_NAME não encontrado"
fi

# ============================================================================
# 6. ANÁLISE DE LOGS AVANÇADA
# ============================================================================

log "📋 Análise avançada de logs..."

# Procurar por padrões de erro específicos no journalctl
error_patterns=(
    "Cannot access.*before initialization"
    "isLocalUserAuthenticated"
    "ReferenceError"
    "TypeError.*is not a function"
    "Error.*loading.*module"
    "ECONNREFUSED"
    "ETIMEDOUT"
)

for pattern in "${error_patterns[@]}"; do
    if journalctl -u "$SERVICE_NAME" --no-pager -n 100 2>/dev/null | grep -q "$pattern"; then
        warn "⚠️ Padrão de erro encontrado: $pattern"
        # Mostrar contexto do erro
        journalctl -u "$SERVICE_NAME" --no-pager -n 100 2>/dev/null | grep -A2 -B2 "$pattern" | head -10
        echo ""
    fi
done

# ============================================================================
# 7. RECOMENDAÇÕES E AÇÕES
# ============================================================================

log "💡 Recomendações baseadas no diagnóstico:"
echo ""

# Determinar ações baseadas nos problemas encontrados
if echo "$test_result" | grep -q "Cannot access.*before initialization"; then
    error "🎯 AÇÃO NECESSÁRIA: Corrigir Temporal Dead Zone (TDZ)"
    echo "   • O problema está na inicialização de variáveis no build ESM"
    echo "   • Execute o install-hard-reset.sh atualizado com correção TDZ"
    echo "   • Comando: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
elif [ "$service_status" = "failed" ]; then
    warn "🔧 AÇÃO NECESSÁRIA: Reinicializar aplicação"
    echo "   • Execute: systemctl restart $SERVICE_NAME"
    echo "   • Monitore logs: journalctl -u $SERVICE_NAME -f"
elif [ "$yjs_usage" -gt 0 ]; then
    warn "📦 AÇÃO NECESSÁRIA: Remover dependências desnecessárias"
    echo "   • Remover imports de yjs/y-protocols do código"
    echo "   • Executar npm install para limpar node_modules"
else
    log "✅ Nenhum problema crítico detectado"
    echo "   • Aplicação deve estar funcionando normalmente"
    echo "   • Verificar logs para detalhes: journalctl -u $SERVICE_NAME -f"
fi

echo ""
log "🔍 Diagnóstico concluído"
echo "=========================================="

# Exit com código baseado na severidade dos problemas
if echo "$test_result" | grep -q "Cannot access.*before initialization"; then
    exit 2  # TDZ crítico
elif [ "$service_status" = "failed" ]; then
    exit 1  # Serviço falhando
else
    exit 0  # OK
fi