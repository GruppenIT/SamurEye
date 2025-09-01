#!/bin/bash

# vlxsam02 - Verificar logs e corrigir

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

echo "🔍 vlxsam02 - VERIFICAR LOGS E CORRIGIR"
echo "====================================="

WORKING_DIR="/opt/samureye/SamurEye"
cd "$WORKING_DIR"

# ============================================================================
# 1. VERIFICAR LOGS DE ERRO
# ============================================================================

log "📝 Verificando logs de erro..."

echo "🔴 Logs mais recentes do systemd:"
journalctl -u samureye-app --no-pager -n 20

echo ""
echo "🔴 Status do serviço:"
systemctl status samureye-app --no-pager || true

# ============================================================================
# 2. VERIFICAR SE PORTA ESTÁ EM USO
# ============================================================================

log "🔍 Verificando porta 5000..."

if netstat -tlnp | grep :5000; then
    warn "Porta 5000 já está em uso"
    echo "Processos na porta 5000:"
    lsof -i :5000 || true
    
    log "Matando processos na porta 5000..."
    pkill -f "node.*5000" || true
    pkill -f "npm.*dev" || true
    sleep 5
fi

# ============================================================================
# 3. VERIFICAR ESTRUTURA DE ARQUIVOS
# ============================================================================

log "🔍 Verificando arquivos essenciais..."

if [ ! -f "server/index.ts" ]; then
    error "server/index.ts não encontrado"
fi

if [ ! -f "server/routes.ts" ]; then
    error "server/routes.ts não encontrado"
fi

if [ ! -f "package.json" ]; then
    error "package.json não encontrado"
fi

log "✅ Arquivos essenciais encontrados"

# ============================================================================
# 4. VERIFICAR NODE_MODULES
# ============================================================================

log "🔍 Verificando node_modules..."

if [ ! -d "node_modules" ]; then
    warn "node_modules não encontrado, instalando..."
    npm install
fi

# ============================================================================
# 5. TESTAR EXECUÇÃO DIRETA
# ============================================================================

log "🧪 Testando execução direta..."

# Tentar rodar diretamente
cd "$WORKING_DIR"
sudo -u samureye timeout 10s npm run dev &
TEST_PID=$!

sleep 8

if ps -p $TEST_PID > /dev/null; then
    log "✅ Aplicação executa diretamente"
    kill $TEST_PID 2>/dev/null || true
else
    warn "❌ Aplicação não executa diretamente"
    echo "Tentando descobrir o erro..."
    sudo -u samureye npm run dev 2>&1 | head -10
fi

# ============================================================================
# 6. CORRIGIR PERMISSÕES E TENTAR NOVAMENTE
# ============================================================================

log "🔧 Corrigindo permissões completas..."

chown -R samureye:samureye "$WORKING_DIR"
chmod -R 755 "$WORKING_DIR"

# Garantir que usuário samureye existe
if ! id samureye &>/dev/null; then
    log "🔧 Criando usuário samureye..."
    useradd -r -s /bin/bash -d /opt/samureye samureye
fi

# ============================================================================
# 7. TENTAR INICIAR NOVAMENTE
# ============================================================================

log "🚀 Tentando iniciar novamente..."

systemctl daemon-reload
systemctl start samureye-app

sleep 10

if systemctl is-active --quiet samureye-app; then
    log "✅ Aplicação iniciou com sucesso"
    
    # Testar endpoints
    if curl -s http://localhost:5000/ >/dev/null; then
        log "✅ Endpoint raiz respondendo"
    fi
    
    if curl -s http://localhost:5000/api/system/settings >/dev/null; then
        log "✅ API respondendo"
    fi
    
else
    error "❌ Aplicação ainda não iniciou - logs detalhados acima"
fi

echo ""
log "🎯 DIAGNÓSTICO COMPLETO"
echo "======================="
echo ""
echo "Se aplicação estiver rodando:"
echo "✅ Aplicação funcionando normalmente"
echo ""
echo "Se aplicação NÃO estiver rodando:"
echo "❌ Verificar logs acima para identificar problema"
echo ""
echo "💡 Para logs contínuos: journalctl -u samureye-app -f"

exit 0