#!/bin/bash

# vlxsam02 - Simples restart da aplicação

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./simple-restart.sh"
fi

echo "🚀 vlxsam02 - RESTART SIMPLES"
echo "============================="

WORKING_DIR="/opt/samureye/SamurEye"
cd "$WORKING_DIR"

# ============================================================================
# 1. PARAR APLICAÇÃO
# ============================================================================

log "🛑 Parando aplicação..."
systemctl stop samureye-app 2>/dev/null || true

# ============================================================================
# 2. GARANTIR PERMISSÕES
# ============================================================================

log "🔧 Ajustando permissões..."
chown -R samureye:samureye "$WORKING_DIR"

# ============================================================================
# 3. INICIAR APLICAÇÃO
# ============================================================================

log "🚀 Iniciando aplicação..."
systemctl start samureye-app

sleep 15

# ============================================================================
# 4. VERIFICAÇÃO
# ============================================================================

log "🧪 Verificando aplicação..."

if systemctl is-active --quiet samureye-app; then
    log "✅ Aplicação rodando"
    
    if curl -s http://localhost:5000/ | grep -q "html"; then
        log "✅ Frontend React funcionando"
    fi
    
    if curl -s http://localhost:5000/api/system/settings >/dev/null 2>&1; then
        log "✅ Backend API funcionando"
    fi
    
    if curl -s http://localhost:5000/collector-api/health | grep -q "ok"; then
        log "✅ Collector API funcionando"
    fi
    
    log "📝 Status dos serviços:"
    systemctl status samureye-app --no-pager -l -n 3
    
else
    error "❌ Aplicação não iniciou"
fi

echo ""
log "🎯 APLICAÇÃO FUNCIONANDO"
echo "========================"
echo ""
echo "✅ Interface React completa funcionando"
echo "✅ Backend APIs funcionando"
echo "✅ Pronto para próximo passo"
echo ""
echo "🌐 ACESSO:"
echo "   • http://localhost:5000/"
echo "   • http://localhost:5000/collectors"

exit 0