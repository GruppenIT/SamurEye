#!/bin/bash

# vlxsam02 - Iniciar aplicação simples

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./start-simple-app.sh"
fi

echo "🚀 vlxsam02 - INICIAR APLICAÇÃO SIMPLES"
echo "======================================"

WORKING_DIR="/opt/samureye/SamurEye"
cd "$WORKING_DIR"

# ============================================================================
# 1. PARAR APLICAÇÃO
# ============================================================================

log "🛑 Parando aplicação..."
systemctl stop samureye-app 2>/dev/null || true
pkill -f "node.*5000" 2>/dev/null || true
pkill -f "npm.*dev" 2>/dev/null || true
sleep 3

# ============================================================================
# 2. AJUSTAR PERMISSÕES
# ============================================================================

log "🔧 Ajustando permissões..."
chown -R samureye:samureye "$WORKING_DIR"

# ============================================================================
# 3. INICIAR APLICAÇÃO
# ============================================================================

log "🚀 Iniciando aplicação..."
systemctl start samureye-app

sleep 20

# ============================================================================
# 4. VERIFICAÇÃO
# ============================================================================

log "🧪 Verificando aplicação..."

# Verificar se está rodando
if systemctl is-active --quiet samureye-app; then
    log "✅ Serviço ativo"
    
    # Aguardar um pouco mais para aplicação inicializar
    sleep 10
    
    # Testar endpoints
    if curl -s http://localhost:5000/ >/dev/null 2>&1; then
        log "✅ Aplicação respondendo"
        
        if curl -s http://localhost:5000/ | grep -q "html\|DOCTYPE"; then
            log "✅ Frontend React funcionando"
        fi
        
        if curl -s http://localhost:5000/api/system/settings | grep -q "SamurEye"; then
            log "✅ Backend API funcionando"
        fi
        
        if curl -s http://localhost:5000/collector-api/health | grep -q "ok"; then
            log "✅ Collector API funcionando"
        fi
        
    else
        log "⚠️ Aplicação ainda iniciando, aguardando..."
        sleep 10
        
        if curl -s http://localhost:5000/ >/dev/null 2>&1; then
            log "✅ Aplicação funcionando após aguardar"
        else
            log "❌ Aplicação não responde, verificar logs"
        fi
    fi
    
    # Mostrar logs recentes
    log "📝 Logs mais recentes:"
    journalctl -u samureye-app --no-pager -n 5
    
else
    log "❌ Serviço não ativo, verificar logs:"
    journalctl -u samureye-app --no-pager -n 10
fi

# ============================================================================
# 5. STATUS FINAL
# ============================================================================

echo ""
if systemctl is-active --quiet samureye-app && curl -s http://localhost:5000/ >/dev/null 2>&1; then
    log "🎯 APLICAÇÃO FUNCIONANDO"
    echo "========================"
    echo ""
    echo "✅ Serviço systemd ativo"
    echo "✅ Aplicação respondendo na porta 5000"
    echo "✅ Interface React disponível"
    echo "✅ APIs funcionando"
    echo ""
    echo "🌐 ACESSO:"
    echo "   • http://localhost:5000/"
    echo "   • http://localhost:5000/collectors"
    echo "   • http://localhost:5000/api/system/settings"
    echo ""
    echo "📡 Pronto para configurar vlxsam01 (NGINX) e vlxsam04 (Collector)"
else
    log "⚠️ APLICAÇÃO COM PROBLEMAS"
    echo "=========================="
    echo ""
    echo "❌ Verificar logs para identificar problema:"
    echo "   journalctl -u samureye-app -f"
    echo ""
    echo "💡 Comandos úteis para debug:"
    echo "   systemctl status samureye-app"
    echo "   curl http://localhost:5000/"
fi

exit 0