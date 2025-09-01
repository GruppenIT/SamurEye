#!/bin/bash

# ============================================================================
# SAMUREYE FIX ENV - CORREÇÃO RÁPIDA DA VARIÁVEL REPLIT_DOMAINS
# ============================================================================
# Script para corrigir o erro "REPLIT_DOMAINS not provided"
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; }

# Configurações
APP_USER="samureye"
WORKING_DIR="/opt/samureye/SamurEye"
SERVICE_NAME="samureye-app"

log "🔧 CORREÇÃO RÁPIDA - Adicionando REPLIT_DOMAINS"

# Parar o serviço
log "⏸️ Parando aplicação..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# Verificar se o .env existe
if [ ! -f "$WORKING_DIR/.env" ]; then
    error "❌ Arquivo .env não encontrado em $WORKING_DIR"
    exit 1
fi

log "📝 Adicionando variáveis Replit ao .env..."

# Fazer backup do .env atual
cp "$WORKING_DIR/.env" "$WORKING_DIR/.env.backup"

# Adicionar variáveis Replit ao final do arquivo
cat >> "$WORKING_DIR/.env" << EOF

# Replit Environment Variables (Required for on-premise)
REPLIT_DOMAINS=app.samureye.com.br,api.samureye.com.br,ca.samureye.com.br
REPL_ID=samureye-onpremise
REPL_SLUG=samureye
REPL_OWNER=onpremise
EOF

# Corrigir permissões
chown "$APP_USER:$APP_USER" "$WORKING_DIR/.env"
chmod 600 "$WORKING_DIR/.env"

log "✅ Variáveis adicionadas com sucesso"

log "🔍 Conteúdo do .env atualizado:"
echo "================================"
tail -5 "$WORKING_DIR/.env"
echo "================================"

log "🚀 Reiniciando aplicação..."
systemctl start "$SERVICE_NAME"

# Aguardar inicialização
sleep 10

# Verificar status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Aplicação iniciada com sucesso!"
    log "🌐 Testando endpoint de saúde..."
    
    if curl -s -f http://localhost:5000/api/health >/dev/null 2>&1; then
        log "✅ Aplicação respondendo corretamente!"
    else
        warn "⚠️ Aplicação iniciada mas endpoint de saúde não responde"
    fi
else
    warn "❌ Aplicação ainda não iniciou - verificando logs..."
    journalctl -u "$SERVICE_NAME" --no-pager -l | tail -10
fi

log "🔧 Correção concluída!"