#!/bin/bash

# ============================================================================
# SAMUREYE DEBUG - APPLICATION SERVER (vlxsam02)
# ============================================================================
# Script para diagnosticar problemas na aplicação SamurEye
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
APP_DIR="/opt/samureye"
APP_NAME="SamurEye"
WORKING_DIR="$APP_DIR/$APP_NAME"
SERVICE_NAME="samureye-app"
POSTGRES_HOST="172.24.1.153"

echo "🔍 DIAGNÓSTICO DA APLICAÇÃO SAMUREYE"
echo "===================================="

log "1. Verificando status do serviço..."
systemctl status "$SERVICE_NAME" --no-pager -l || true

log "2. Verificando logs de erro da aplicação..."
if [ -f "/var/log/samureye/error.log" ]; then
    echo "=== ÚLTIMOS ERROS (error.log) ==="
    tail -30 /var/log/samureye/error.log
    echo "================================="
else
    warn "Arquivo error.log não encontrado"
fi

log "3. Verificando logs de aplicação..."
if [ -f "/var/log/samureye/app.log" ]; then
    echo "=== ÚLTIMOS LOGS (app.log) ==="
    tail -30 /var/log/samureye/app.log
    echo "=============================="
else
    warn "Arquivo app.log não encontrado"
fi

log "4. Verificando logs do systemd..."
echo "=== LOGS SYSTEMD ==="
journalctl -u "$SERVICE_NAME" --no-pager -l | tail -30
echo "==================="

log "5. Verificando conectividade PostgreSQL..."
if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="SamurEye2024!" psql -h "$POSTGRES_HOST" -U samureye -d samureye -c "SELECT version();" 2>&1 || warn "Falha na conexão PostgreSQL"
else
    warn "psql não instalado - não é possível testar PostgreSQL"
fi

log "6. Verificando arquivos da aplicação..."
echo "Diretório de trabalho: $WORKING_DIR"
if [ -d "$WORKING_DIR" ]; then
    echo "✅ Diretório existe"
    if [ -f "$WORKING_DIR/dist/index.js" ]; then
        echo "✅ Build existe (dist/index.js)"
    else
        warn "Build não encontrado (dist/index.js)"
    fi
    
    if [ -f "$WORKING_DIR/.env" ]; then
        echo "✅ Arquivo .env existe"
    else
        warn "Arquivo .env não encontrado"
    fi
    
    if [ -f "$WORKING_DIR/package.json" ]; then
        echo "✅ package.json existe"
    else
        warn "package.json não encontrado"
    fi
else
    error "Diretório de trabalho não existe: $WORKING_DIR"
fi

log "7. Verificando permissões..."
ls -la "$WORKING_DIR/" | head -10
ls -la /var/log/samureye/ || warn "Diretório de logs não encontrado"

log "8. Testando execução manual..."
cd "$WORKING_DIR" || exit 1

info "Tentando executar: NODE_ENV=production node dist/index.js"
echo "Pressione Ctrl+C após alguns segundos para parar..."

sudo -u "$APP_USER" NODE_ENV=production node dist/index.js