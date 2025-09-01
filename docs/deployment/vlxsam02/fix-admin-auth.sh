#!/bin/bash

# ============================================================================
# SAMUREYE FIX ADMIN AUTH - CORREÇÃO DA AUTENTICAÇÃO ADMIN ON-PREMISE
# ============================================================================
# Script para corrigir autenticação admin no ambiente on-premise
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
APP_USER="samureye"
WORKING_DIR="/opt/samureye/SamurEye"
SERVICE_NAME="samureye-app"

log "🔧 CORREÇÃO DA AUTENTICAÇÃO ADMIN ON-PREMISE"

# Verificar se a aplicação está rodando
if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    error "❌ Aplicação não está rodando. Execute primeiro o fix-env.sh"
    exit 1
fi

log "🔍 Testando acesso admin atual..."
ADMIN_STATUS=$(curl -s -w "%{http_code}" -o /dev/null "http://localhost:5000/api/admin/me" || echo "000")

if [ "$ADMIN_STATUS" = "200" ]; then
    log "✅ Endpoint /api/admin/me está respondendo"
else
    error "❌ Endpoint admin não está acessível (HTTP $ADMIN_STATUS)"
fi

log "🔐 Realizando login admin programático..."

# Fazer login admin via API
LOGIN_RESPONSE=$(curl -s -X POST "http://localhost:5000/api/admin/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@samureye.com.br","password":"SamurEye2024!"}' \
    -c /tmp/admin_cookies.txt \
    -w "%{http_code}")

if echo "$LOGIN_RESPONSE" | grep -q "200"; then
    log "✅ Login admin realizado com sucesso"
else
    warn "⚠️ Login automático falhou, verificando configuração..."
fi

log "🧪 Testando acesso a recursos admin..."

# Testar acesso aos tenants
TENANTS_TEST=$(curl -s -w "%{http_code}" -o /dev/null \
    -b /tmp/admin_cookies.txt \
    "http://localhost:5000/api/admin/tenants" || echo "000")

if [ "$TENANTS_TEST" = "200" ]; then
    log "✅ Acesso aos tenants funcionando"
else
    warn "❌ Ainda sem acesso aos tenants (HTTP $TENANTS_TEST)"
    
    log "🔧 Aplicando correção no código da aplicação..."
    
    # Fazer backup do routes.ts
    cp "$WORKING_DIR/server/routes.ts" "$WORKING_DIR/server/routes.ts.backup"
    
    log "📝 Verificando se a correção já foi aplicada..."
    if grep -q "ONPREMISE_ADMIN_BYPASS" "$WORKING_DIR/server/routes.ts"; then
        log "✅ Correção já aplicada no código"
    else
        log "📝 Aplicando bypass admin para on-premise..."
        
        # Não vamos modificar o código em produção
        warn "⚠️ Correção requer atualização do código fonte"
        log "💡 SOLUÇÃO TEMPORÁRIA:"
        echo "================================"
        echo "1. Acesse http://172.24.1.152:5000/admin"
        echo "2. Abra o console do navegador (F12)"
        echo "3. Execute o comando JavaScript:"
        echo ""
        echo "fetch('/api/admin/login', {"
        echo "  method: 'POST',"
        echo "  headers: {'Content-Type': 'application/json'},"
        echo "  body: JSON.stringify({email:'admin@samureye.com.br', password:'SamurEye2024!'})"
        echo "}).then(() => location.reload())"
        echo ""
        echo "4. Recarregue a página"
        echo "================================"
    fi
fi

# Testar criação de tenant
log "🏢 Testando criação de tenant de exemplo..."
TENANT_CREATION=$(curl -s -X POST "http://localhost:5000/api/admin/tenants" \
    -H "Content-Type: application/json" \
    -b /tmp/admin_cookies.txt \
    -d '{
        "name": "Tenant Teste",
        "slug": "tenant-teste", 
        "description": "Tenant de teste on-premise",
        "isActive": true
    }' \
    -w "%{http_code}" || echo "000")

if echo "$TENANT_CREATION" | grep -q "200\|201"; then
    log "✅ Criação de tenant funcionando!"
else
    warn "❌ Criação de tenant ainda bloqueada"
fi

# Limpeza
rm -f /tmp/admin_cookies.txt

log "📊 RESUMO DA CONFIGURAÇÃO:"
echo "================================"
echo "🌐 URL Admin: http://172.24.1.152:5000/admin"
echo "👤 Email: admin@samureye.com.br"
echo "🔑 Senha: SamurEye2024!"
echo "🛠️ Status: $(systemctl is-active $SERVICE_NAME)"
echo "================================"

log "🔧 Correção de autenticação admin concluída!"