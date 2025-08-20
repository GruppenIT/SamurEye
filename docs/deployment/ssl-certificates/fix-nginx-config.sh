#!/bin/bash

# Script para corrigir duplicação de limit_req_zone no NGINX

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; exit 1; }

log "Verificando configuração NGINX..."

# Verificar se o arquivo de configuração existe
NGINX_CONFIG="/etc/nginx/sites-enabled/samureye"
if [ ! -f "$NGINX_CONFIG" ]; then
    error "Arquivo de configuração não encontrado: $NGINX_CONFIG"
fi

log "Analisando problema de limit_req_zone duplicado..."

# Verificar se há duplicação
DUPLICATES=$(grep -c "limit_req_zone.*api" "$NGINX_CONFIG" 2>/dev/null || echo "0")
log "Encontradas $DUPLICATES diretivas limit_req_zone para 'api'"

if [ "$DUPLICATES" -gt 1 ]; then
    warn "Detectada duplicação de limit_req_zone. Corrigindo..."
    
    # Backup da configuração atual
    cp "$NGINX_CONFIG" "$NGINX_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    log "Backup criado: $NGINX_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remover duplicatas mantendo apenas a primeira ocorrência
    awk '
    /limit_req_zone.*api/ {
        if (!seen) {
            print
            seen = 1
        }
        next
    }
    { print }
    ' "$NGINX_CONFIG" > "$NGINX_CONFIG.tmp"
    
    mv "$NGINX_CONFIG.tmp" "$NGINX_CONFIG"
    log "Duplicação removida"
else
    log "Nenhuma duplicação de limit_req_zone encontrada"
fi

# Verificar se há outros problemas comuns
log "Verificando outras possíveis duplicações..."

# Verificar outras diretivas que podem estar duplicadas
COMMON_DIRECTIVES=("server_name" "listen" "ssl_certificate" "location /api" "upstream")

for directive in "${COMMON_DIRECTIVES[@]}"; do
    COUNT=$(grep -c "$directive" "$NGINX_CONFIG" 2>/dev/null || echo "0")
    if [ "$COUNT" -gt 2 ]; then  # Mais de 2 é suspeito para a maioria das diretivas
        warn "Possível duplicação de '$directive' ($COUNT ocorrências)"
    fi
done

# Testar configuração
log "Testando configuração NGINX..."
if nginx -t; then
    log "✅ Configuração NGINX válida!"
    
    # Recarregar NGINX
    log "Recarregando NGINX..."
    systemctl reload nginx
    log "✅ NGINX recarregado com sucesso!"
    
    # Verificar status
    if systemctl is-active --quiet nginx; then
        log "✅ NGINX está rodando corretamente"
    else
        error "NGINX não está rodando após reload"
    fi
    
else
    error "Configuração NGINX ainda possui erros. Verificar manualmente."
fi

# Teste rápido de conectividade
log "Testando conectividade HTTPS..."
if curl -s -I https://app.samureye.com.br >/dev/null 2>&1; then
    log "✅ HTTPS funcionando"
else
    warn "Problema na conectividade HTTPS - verificar DNS e certificados"
fi

log "✅ Correção da configuração NGINX concluída!"

echo ""
echo "📋 RESUMO:"
echo "- Duplicações removidas: $([ "$DUPLICATES" -gt 1 ] && echo "Sim" || echo "Não")"
echo "- Configuração válida: ✅"
echo "- NGINX rodando: ✅"
echo "- Backup salvo: $NGINX_CONFIG.backup.*"
echo ""
echo "💡 Se ainda houver problemas, verifique:"
echo "  - sudo nginx -t (para erros de configuração)"
echo "  - sudo systemctl status nginx (para status do serviço)"
echo "  - sudo tail -f /var/log/nginx/error.log (para logs de erro)"