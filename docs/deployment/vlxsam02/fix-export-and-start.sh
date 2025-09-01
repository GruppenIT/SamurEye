#!/bin/bash

# vlxsam02 - Corrigir export e iniciar

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-export-and-start.sh"
fi

echo "🔧 vlxsam02 - CORRIGIR EXPORT E INICIAR"
echo "======================================"

WORKING_DIR="/opt/samureye/SamurEye"
cd "$WORKING_DIR"

# ============================================================================
# 1. PARAR APLICAÇÃO
# ============================================================================

log "🛑 Parando aplicação..."
systemctl stop samureye-app 2>/dev/null || true

# Matar qualquer processo na porta 5000
pkill -f "node.*5000" 2>/dev/null || true
pkill -f "npm.*dev" 2>/dev/null || true
sleep 3

# ============================================================================
# 2. VERIFICAR SE EXPORT FOI CORRIGIDO
# ============================================================================

log "🔍 Verificando export no routes.ts..."

if grep -q "export { registerRoutes }" server/routes.ts; then
    log "✅ Export corrigido"
else
    log "🔧 Corrigindo export..."
    
    # Remover export da function
    sed -i 's/export async function registerRoutes/async function registerRoutes/' server/routes.ts
    
    # Adicionar export no final se não existir
    if ! grep -q "export { registerRoutes }" server/routes.ts; then
        echo "" >> server/routes.ts
        echo "export { registerRoutes };" >> server/routes.ts
    fi
    
    log "✅ Export corrigido manualmente"
fi

# ============================================================================
# 3. TESTAR SINTAXE
# ============================================================================

log "🧪 Testando sintaxe..."

if node --check server/index.ts 2>/dev/null; then
    log "✅ Sintaxe OK"
else
    error "❌ Problema de sintaxe ainda existe"
fi

# ============================================================================
# 4. AJUSTAR PERMISSÕES
# ============================================================================

log "🔧 Ajustando permissões..."
chown -R samureye:samureye "$WORKING_DIR"

# ============================================================================
# 5. INICIAR APLICAÇÃO
# ============================================================================

log "🚀 Iniciando aplicação..."
systemctl start samureye-app

sleep 15

# ============================================================================
# 6. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Verificando aplicação..."

if systemctl is-active --quiet samureye-app; then
    log "✅ Aplicação rodando"
    
    # Verificar se está servindo conteúdo
    if curl -s http://localhost:5000/ | grep -q "html\|SamurEye\|DOCTYPE"; then
        log "✅ Frontend funcionando"
    fi
    
    if curl -s http://localhost:5000/api/system/settings >/dev/null 2>&1; then
        log "✅ Backend API funcionando"
    fi
    
    log "📝 Logs recentes:"
    journalctl -u samureye-app --no-pager -n 3
    
else
    log "❌ Aplicação ainda com problemas"
    journalctl -u samureye-app --no-pager -n 10
fi

echo ""
log "🎯 CORREÇÃO DE EXPORT APLICADA"
echo "=============================="
echo ""
echo "✅ Export { registerRoutes } corrigido"
echo "✅ Aplicação deve estar funcionando"
echo ""
echo "🌐 TESTE:"
echo "   curl http://localhost:5000/"

exit 0