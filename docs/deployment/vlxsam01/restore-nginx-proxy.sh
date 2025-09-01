#!/bin/bash

# vlxsam01 - Restaurar NGINX proxy para aplicação completa

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./restore-nginx-proxy.sh"
fi

echo "🌐 vlxsam01 - RESTAURAR NGINX PROXY"
echo "=================================="

# ============================================================================
# 1. CONFIGURAR NGINX PARA PROXY COMPLETO
# ============================================================================

log "🔧 Configurando NGINX para proxy da aplicação completa..."

cat > /etc/nginx/sites-available/samureye << 'EOF'
server {
    listen 80;
    server_name app.samureye.com.br api.samureye.com.br *.samureye.com.br;
    
    # Logs
    access_log /var/log/nginx/samureye.access.log;
    error_log /var/log/nginx/samureye.error.log;
    
    # Proxy para a aplicação completa React + Backend
    location / {
        proxy_pass http://192.168.100.152:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        # Headers para desenvolvimento
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass $http_upgrade;
    }
    
    # Proxy específico para APIs (redundante mas explícito)
    location /api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # Proxy para Collector API
    location /collector-api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
}
EOF

# Habilitar site
ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/

# Remover arquivo de interface estática se existir
rm -f /var/www/samureye/index.html 2>/dev/null || true

# ============================================================================
# 2. TESTAR E RECARREGAR NGINX
# ============================================================================

log "🧪 Testando configuração NGINX..."

if nginx -t; then
    log "✅ Configuração NGINX válida"
    systemctl reload nginx
    log "✅ NGINX recarregado"
else
    error "❌ Configuração NGINX inválida"
fi

# ============================================================================
# 3. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Verificando proxy..."

sleep 5

if curl -s http://localhost/ | grep -q "html"; then
    log "✅ Proxy funcionando - servindo interface React"
else
    warn "⚠️ Proxy pode ter problemas"
fi

if curl -s http://localhost/api/system/settings >/dev/null; then
    log "✅ Proxy API funcionando"
else
    warn "⚠️ Proxy API pode ter problemas"
fi

echo ""
log "🎯 NGINX PROXY RESTAURADO"
echo "========================="
echo ""
echo "✅ PROXY CONFIGURADO PARA:"
echo "   • Interface React completa"
echo "   • Backend APIs"
echo "   • Collector APIs"
echo ""
echo "🌐 ACESSO:"
echo "   • http://app.samureye.com.br (Interface completa)"
echo "   • http://api.samureye.com.br (APIs)"
echo ""
echo "📡 Proxy pronto para aplicação completa!"

exit 0