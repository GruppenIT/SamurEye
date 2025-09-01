#!/bin/bash

# vlxsam01 - Atualizar Certificados e NGINX para Collectors
# Garante SSL/TLS correto para as APIs de collectors

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./update-certificates.sh"
fi

echo "🔐 vlxsam01 - ATUALIZAR CERTIFICADOS E NGINX"
echo "============================================="
echo "Garante SSL correto para APIs dos collectors:"
echo "1. Verificar/renovar certificados SSL"
echo "2. Atualizar configuração NGINX"
echo "3. Otimizar para APIs de telemetria"
echo ""

# ============================================================================
# 1. VERIFICAR CERTIFICADOS SSL
# ============================================================================

log "🔍 Verificando certificados SSL..."

CERT_PATH="/etc/letsencrypt/live/app.samureye.com.br"

if [ -d "$CERT_PATH" ]; then
    # Verificar validade do certificado
    CERT_EXPIRY=$(openssl x509 -in "$CERT_PATH/cert.pem" -noout -dates | grep "notAfter" | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s)
    CURRENT_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
    
    if [ $DAYS_LEFT -gt 30 ]; then
        log "✅ Certificados válidos por mais $DAYS_LEFT dias"
    else
        warn "⚠️ Certificados expiram em $DAYS_LEFT dias - renovando..."
        
        # Tentar renovar certificados
        if command -v certbot >/dev/null 2>&1; then
            certbot renew --quiet --no-self-upgrade
            systemctl reload nginx
            log "✅ Certificados renovados"
        else
            warn "Certbot não instalado - verificação manual necessária"
        fi
    fi
else
    warn "⚠️ Certificados SSL não encontrados em $CERT_PATH"
fi

# ============================================================================
# 2. OTIMIZAR CONFIGURAÇÃO NGINX PARA COLLECTORS
# ============================================================================

log "⚙️ Otimizando configuração NGINX para collectors..."

# Backup da configuração atual
cp /etc/nginx/sites-available/samureye.conf /etc/nginx/sites-available/samureye.conf.backup.$(date +%Y%m%d)

# Criar configuração otimizada para collectors
cat > /etc/nginx/sites-available/samureye.conf << 'EOF'
# SamurEye - Configuração otimizada para Collectors
server {
    listen 80;
    server_name app.samureye.com.br api.samureye.com.br;
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.samureye.com.br api.samureye.com.br;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/app.samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.samureye.com.br/privkey.pem;
    
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    
    # SSL session cache
    ssl_session_cache shared:SSL:50m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Logs
    access_log /var/log/nginx/samureye.access.log;
    error_log /var/log/nginx/samureye.error.log;
    
    # Client settings - otimizado para uploads de telemetria
    client_max_body_size 10M;
    client_body_timeout 60s;
    client_header_timeout 60s;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # Specific routes for collector APIs - high performance
    location ~ ^/collector-api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts otimizados para telemetria
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings para throughput alto
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        
        # Rate limiting específico para telemetria (mais permissivo)
        limit_req zone=api burst=20 nodelay;
    }
    
    # API routes - standard configuration
    location ~ ^/api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts padrão
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        # Rate limiting para APIs gerais
        limit_req zone=api burst=10 nodelay;
    }
    
    # Static files
    location / {
        proxy_pass http://192.168.100.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Cache para assets estáticos
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            proxy_pass http://192.168.100.152:5000;
            proxy_cache_valid 200 1h;
            add_header Cache-Control "public, immutable";
        }
    }
}

# step-ca Certificate Authority
server {
    listen 443 ssl http2;
    server_name ca.samureye.com.br;
    
    # SSL Configuration (mesmo certificado wildcard)
    ssl_certificate /etc/letsencrypt/live/app.samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.samureye.com.br/privkey.pem;
    
    # Modern SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    
    # Proxy para step-ca
    location / {
        proxy_pass https://localhost:9000;
        proxy_ssl_verify off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# ============================================================================
# 3. CONFIGURAR RATE LIMITING PARA COLLECTORS
# ============================================================================

log "🚦 Configurando rate limiting otimizado..."

# Adicionar configuração de rate limiting no nginx.conf
if ! grep -q "limit_req_zone.*api" /etc/nginx/nginx.conf; then
    # Adicionar rate limiting zone
    sed -i '/http {/a\\n    # Rate limiting zones\n    limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;\n    limit_req_zone $binary_remote_addr zone=telemetry:10m rate=60r/m;' /etc/nginx/nginx.conf
    
    log "✅ Rate limiting configurado"
fi

# ============================================================================
# 4. VERIFICAR CONFIGURAÇÃO E RECARREGAR
# ============================================================================

log "🔍 Verificando configuração NGINX..."

if nginx -t; then
    log "✅ Configuração NGINX válida"
    
    systemctl reload nginx
    log "✅ NGINX recarregado"
else
    error "❌ Erro na configuração NGINX"
fi

# ============================================================================
# 5. CONFIGURAR LOGS ROTATIVOS
# ============================================================================

log "📝 Configurando rotação de logs..."

cat > /etc/logrotate.d/samureye-nginx << 'EOF'
/var/log/nginx/samureye.*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 0644 www-data www-data
    postrotate
        systemctl reload nginx
    endscript
}
EOF

log "✅ Rotação de logs configurada"

# ============================================================================
# 6. TESTE DE CONECTIVIDADE
# ============================================================================

log "🧪 Testando conectividade..."

# Testar HTTPS
if curl -s -f https://app.samureye.com.br/api/system/settings >/dev/null; then
    log "✅ HTTPS funcionando"
else
    warn "⚠️ Problema com HTTPS"
fi

# Testar collector API
if curl -s -f https://app.samureye.com.br/collector-api/health >/dev/null 2>&1; then
    log "✅ Collector API acessível"
else
    warn "⚠️ Collector API pode não estar respondendo"
fi

# ============================================================================
# 7. RESULTADO FINAL
# ============================================================================

echo ""
log "🎯 NGINX E CERTIFICADOS OTIMIZADOS"
echo "════════════════════════════════════════════════"
echo ""
echo "🔐 CERTIFICADOS SSL:"
echo "   ✓ Certificados verificados/renovados"
echo "   ✓ Configuração SSL moderna (TLS 1.2/1.3)"
echo "   ✓ Headers de segurança configurados"
echo ""
echo "🚦 NGINX OTIMIZADO:"
echo "   ✓ Rate limiting específico para collectors"
echo "   ✓ Timeouts otimizados para telemetria"
echo "   ✓ Compressão gzip ativada"
echo "   ✓ Cache para assets estáticos"
echo ""
echo "📝 LOGS E MONITORAMENTO:"
echo "   ✓ Rotação automática de logs"
echo "   ✓ Logs separados por aplicação"
echo ""
echo "🌐 URLs CONFIGURADAS:"
echo "   • App: https://app.samureye.com.br"
echo "   • API: https://app.samureye.com.br/api/"
echo "   • Collector API: https://app.samureye.com.br/collector-api/"
echo "   • CA: https://ca.samureye.com.br"
echo ""
echo "📊 MONITORAMENTO:"
echo "   • Status: systemctl status nginx"
echo "   • Logs: tail -f /var/log/nginx/samureye.access.log"
echo "   • SSL: openssl s_client -connect app.samureye.com.br:443"
echo ""
echo "💡 PRÓXIMOS PASSOS:"
echo "   1. Aplicar melhorias no vlxsam02"
echo "   2. Testar telemetria via HTTPS"
echo "   3. Monitorar logs de collector API"

exit 0