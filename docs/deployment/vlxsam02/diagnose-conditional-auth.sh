#!/bin/bash

# ============================================================================
# DIAGNÓSTICO PROBLEMA AUTENTICAÇÃO CONDICIONAL - vlxsam02
# ============================================================================
# Problema: Interface não pede login APENAS quando existem usuários criados
# Sintoma: Após criar tenant "gruppen-it" + usuário SOC "rodrigo@gruppen.com.br"
#          a interface para de pedir login e entra automaticamente
#
# Uso: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/diagnose-conditional-auth.sh | bash
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

echo ""
echo "🔍 DIAGNÓSTICO PROBLEMA AUTENTICAÇÃO CONDICIONAL"
echo "==============================================="
echo ""
info "Problema: Login funciona quando banco vazio, falha quando há usuários"

cd "$WORKING_DIR" || error "❌ Não foi possível acessar $WORKING_DIR"

# ============================================================================
# 1. VERIFICAÇÃO DO BANCO DE DADOS - USUÁRIOS EXISTENTES
# ============================================================================

log "🔍 Verificando usuários existentes no banco..."

# Testar se PostgreSQL está respondendo
if ! pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
    error "❌ PostgreSQL não está respondendo"
    exit 1
fi

# Verificar usuários cadastrados
log "📊 Contando usuários no banco de dados:"
echo "─────────────────────────────────────────"

# Conectar usando credenciais do .env
if [ -f ".env" ]; then
    database_url=$(grep "DATABASE_URL" .env | cut -d'=' -f2- | tr -d '"')
    
    if [ -n "$database_url" ]; then
        # Contar usuários na tabela users
        user_count=$(psql "$database_url" -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | xargs)
        if [ -n "$user_count" ] && [ "$user_count" -gt 0 ]; then
            warn "⚠️ Encontrados $user_count usuários no banco"
            
            # Listar usuários específicos
            log "📋 Usuários cadastrados:"
            psql "$database_url" -c "SELECT id, email, \"firstName\", \"lastName\", \"isSocUser\", \"isActive\" FROM users;" 2>/dev/null || error "Erro ao listar usuários"
            
            # Verificar se rodrigo@gruppen.com.br existe
            rodrigo_exists=$(psql "$database_url" -t -c "SELECT COUNT(*) FROM users WHERE email = 'rodrigo@gruppen.com.br';" 2>/dev/null | xargs)
            if [ "$rodrigo_exists" = "1" ]; then
                error "❌ CONFIRMADO: Usuário rodrigo@gruppen.com.br existe no banco"
                warn "⚠️ Este é o trigger do problema de autenticação!"
            fi
            
        else
            log "✅ Banco vazio - sem usuários cadastrados"
            info "💡 Quando banco está vazio, login funciona corretamente"
        fi
        
        # Contar tenants
        tenant_count=$(psql "$database_url" -t -c "SELECT COUNT(*) FROM tenants;" 2>/dev/null | xargs)
        if [ -n "$tenant_count" ] && [ "$tenant_count" -gt 0 ]; then
            warn "⚠️ Encontrados $tenant_count tenants no banco"
            
            log "📋 Tenants cadastrados:"
            psql "$database_url" -c "SELECT id, name, domain, \"isActive\" FROM tenants;" 2>/dev/null || error "Erro ao listar tenants"
        fi
        
    else
        error "❌ DATABASE_URL não encontrado no .env"
    fi
else
    error "❌ Arquivo .env não encontrado"
fi

echo "─────────────────────────────────────────"

# ============================================================================
# 2. ANÁLISE DO MIDDLEWARE - LÓGICA CONDICIONAL
# ============================================================================

log "🔍 Analisando middleware para lógica condicional..."

if [ -f "server/routes.ts" ]; then
    
    # Verificar se middleware tem lógica baseada em usuários existentes
    log "📋 Procurando lógica condicional no middleware:"
    echo "─────────────────────────────────────────"
    
    # Procurar referências a getUserCount, users.length, etc
    if grep -n -A5 -B5 "getUserCount\|users\.length\|COUNT.*users\|\.length.*user" server/routes.ts; then
        error "❌ ENCONTRADA lógica condicional baseada em contagem de usuários!"
    else
        log "✅ Nenhuma lógica baseada em contagem de usuários encontrada"
    fi
    
    # Verificar o middleware isLocalUserAuthenticated completo
    log "🔍 Analisando middleware isLocalUserAuthenticated:"
    if grep -q "function isLocalUserAuthenticated" server/routes.ts; then
        start_line=$(grep -n "function isLocalUserAuthenticated" server/routes.ts | cut -d: -f1)
        log "📍 Middleware encontrado na linha $start_line"
        
        # Extrair middleware completo (próximas 30 linhas)
        middleware_code=$(sed -n "${start_line},$((start_line + 30))p" server/routes.ts)
        
        echo "$middleware_code" | nl -v$start_line
        echo ""
        
        # Verificar padrões problemáticos
        if echo "$middleware_code" | grep -q "DISABLE_AUTH.*true"; then
            error "❌ Middleware tem bypass DISABLE_AUTH"
        fi
        
        if echo "$middleware_code" | grep -q "tenant@onpremise\.local\|onpremise-user"; then
            error "❌ CONFIRMADO: Middleware cria usuário fictício!"
            warn "⚠️ Provavelmente ativo quando existem usuários no banco"
        fi
        
        if echo "$middleware_code" | grep -q "storage\..*users\|getAllUsers\|userCount"; then
            error "❌ ENCONTRADA: Lógica que consulta usuários existentes!"
            warn "⚠️ Middleware pode estar decidindo autenticação baseado em usuários existentes"
        fi
        
    else
        error "❌ Middleware isLocalUserAuthenticated não encontrado"
    fi
    
    echo "─────────────────────────────────────────"
    
else
    error "❌ Arquivo server/routes.ts não encontrado"
fi

# ============================================================================
# 3. TESTE ESPECÍFICO - COMPARAÇÃO COM/SEM USUÁRIOS
# ============================================================================

log "🧪 Testando comportamento da API com usuários existentes..."

# Testar endpoint /api/user
api_response=$(curl -s -w "%{http_code}" -o /tmp/api_user_test.json http://localhost:5000/api/user)
http_code="${api_response: -3}"

if [ "$http_code" = "200" ]; then
    error "❌ PROBLEMA CONFIRMADO: /api/user retorna 200 sem autenticação!"
    
    log "📋 Resposta da API:"
    cat /tmp/api_user_test.json | jq . 2>/dev/null || cat /tmp/api_user_test.json
    echo ""
    
    # Verificar se é usuário fictício
    if grep -q "tenant@onpremise\.local\|onpremise-user" /tmp/api_user_test.json; then
        error "❌ CONFIRMADO: API retorna usuário fictício automático!"
        warn "⚠️ Middleware criando sessão falsa quando existem usuários reais"
    fi
    
elif [ "$http_code" = "401" ]; then
    log "✅ API corretamente protegida (401 Unauthorized)"
else
    warn "⚠️ API retorna código inesperado: $http_code"
fi

rm -f /tmp/api_user_test.json

# ============================================================================
# 4. ANÁLISE DO FRONTEND - LÓGICA DE ROTEAMENTO
# ============================================================================

log "🔍 Analisando lógica de roteamento no frontend..."

if [ -f "src/App.tsx" ]; then
    log "📋 Verificando lógica de autenticação em App.tsx:"
    echo "─────────────────────────────────────────"
    
    # Procurar lógica condicional de roteamento
    if grep -A10 -B5 "useAuth\|isAuthenticated\|Landing\|Home" src/App.tsx; then
        echo ""
        
        # Verificar se há lógica baseada em existência de usuários
        if grep -A15 -B5 "users.*length\|userCount\|hasUsers" src/App.tsx; then
            error "❌ Frontend tem lógica baseada em existência de usuários!"
        fi
    fi
    
    echo "─────────────────────────────────────────"
fi

if [ -f "src/hooks/useAuth.ts" ]; then
    log "📋 Verificando hook useAuth:"
    echo "─────────────────────────────────────────"
    cat src/hooks/useAuth.ts
    echo "─────────────────────────────────────────"
fi

# ============================================================================
# 5. DIAGNÓSTICO ESPECÍFICO DO PROBLEMA
# ============================================================================

log "🎯 Resumo do diagnóstico específico:"
echo ""

if [ "$user_count" -gt 0 ] && [ "$http_code" = "200" ]; then
    error "🔴 PROBLEMA CONFIRMADO:"
    echo "   • Existem $user_count usuários no banco"
    echo "   • API /api/user retorna 200 sem autenticação"
    echo "   • Sistema bypassa login quando há usuários cadastrados"
    echo ""
    
    log "🎯 CAUSA RAIZ PROVÁVEL:"
    echo "   • Middleware tem lógica: 'se existem usuários, crie sessão automática'"
    echo "   • DISABLE_AUTH pode estar ativo condicionalmente"
    echo "   • Sistema assume ambiente de desenvolvimento com usuários existentes"
    echo ""
    
    log "🔧 AÇÃO NECESSÁRIA:"
    echo "   1. Remover lógica condicional baseada em usuários existentes"
    echo "   2. Middleware deve SEMPRE exigir autenticação válida"
    echo "   3. Não criar usuários fictícios automaticamente"
    echo ""
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/fix-conditional-auth.sh | bash"
    
elif [ "$user_count" -eq 0 ] && [ "$http_code" = "401" ]; then
    log "✅ COMPORTAMENTO CORRETO:"
    echo "   • Banco vazio, API protegida"
    echo "   • Problema aparecerá quando usuários forem criados"
    
else
    warn "⚠️ ESTADO INCONSISTENTE:"
    echo "   • Usuários no banco: $user_count"
    echo "   • Código HTTP /api/user: $http_code"
    echo "   • Comportamento inesperado"
fi

echo ""
log "🔍 Diagnóstico de autenticação condicional concluído"
echo "==============================================="

exit 0