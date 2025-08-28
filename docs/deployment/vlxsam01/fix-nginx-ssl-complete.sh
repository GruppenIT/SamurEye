#!/bin/bash

# Script para corrigir completamente a configuração NGINX SSL no vlxsam01
set -e

# Função para logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🔧 Corrigindo configuração NGINX SSL completa..."

# Verificar se certificado wildcard existe
CERT_PATH="/etc/letsencrypt/live/samureye.com.br"
if [ ! -f "$CERT_PATH/fullchain.pem" ] || [ ! -f "$CERT_PATH/privkey.pem" ]; then
    echo "ERROR: Certificado wildcard não encontrado em $CERT_PATH"
    exit 1
fi

log "✅ Certificado wildcard encontrado"

# Backup da configuração atual
if [ -f /etc/nginx/sites-available/samureye ]; then
    cp /etc/nginx/sites-available/samureye /etc/nginx/sites-available/samureye.backup.$(date +%Y%m%d_%H%M%S)
    log "🔄 Backup da configuração atual criado"
fi

# Criar configuração NGINX SSL completa corrigida
cat > /etc/nginx/sites-available/samureye-ssl-fixed << 'EOF'
# SamurEye - Configuração NGINX Gateway SSL COMPLETA
# Domínio: *.samureye.com.br  
# Servidor: vlxsam01 (172.24.1.151)
# Certificado: Wildcard samureye.com.br

# Upstream para aplicação SamurEye (vlxsam02:5000)
upstream samureye_backend {
    server 172.24.1.152:5000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# Upstream para step-ca (localhost:9000)
upstream step_ca_backend {
    server 127.0.0.1:9000 max_fails=2 fail_timeout=10s;
}

# HTTP -> HTTPS redirect para todos os domínios
server {
    listen 80;
    listen [::]:80;
    server_name app.samureye.com.br api.samureye.com.br ca.samureye.com.br samureye.com.br *.samureye.com.br;
    
    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files $uri =404;
    }
    
    # Redirect everything else to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS - Aplicação SamurEye Principal
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name app.samureye.com.br api.samureye.com.br samureye.com.br *.samureye.com.br;
    
    # SSL Configuration (Certificado Wildcard)
    ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/samureye.com.br/chain.pem;
    
    # SSL Security moderna
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    
    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' ws: wss:;" always;
    
    # Logs específicos
    access_log /var/log/nginx/samureye-app.access.log main;
    error_log /var/log/nginx/samureye-app.error.log warn;
    
    # Configurações globais de proxy
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
    
    # WebSocket support global
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    
    # Buffer settings otimizados
    proxy_buffering off;
    proxy_buffer_size 128k;
    proxy_buffers 100 128k;
    proxy_busy_buffers_size 128k;
    
    # Timeouts generosos
    proxy_connect_timeout 60s;
    proxy_send_timeout 120s;
    proxy_read_timeout 120s;
    
    # API routes com rate limiting específico
    location /api/ {
        limit_req zone=api burst=100 nodelay;
        proxy_pass http://samureye_backend;
        
        # Timeouts específicos para API
        proxy_connect_timeout 30s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # WebSocket específico para real-time
    location /ws {
        proxy_pass http://samureye_backend;
        
        # Timeout maior para WebSocket
        proxy_read_timeout 300s; # 5 minutos para long polling
    }
    
    # Admin routes
    location /admin/ {
        limit_req zone=admin_login burst=10 nodelay;
        proxy_pass http://samureye_backend;
    }
    
    # Health check
    location /health {
        proxy_pass http://samureye_backend/health;
        access_log off;
    }
    
    # Main application - deve ser último para catch-all
    location / {
        limit_req zone=app burst=50 nodelay;
        limit_conn conn_limit_per_ip 50;
        
        proxy_pass http://samureye_backend;
        
        # Error handling
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 60s;
    }
}

# HTTPS - step-ca Certificate Authority (separado)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ca.samureye.com.br;
    
    # SSL Configuration (mesmo certificado wildcard)
    ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/samureye.com.br/chain.pem;
    
    # SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    
    # Logs específicos para CA
    access_log /var/log/nginx/step-ca.access.log main;
    error_log /var/log/nginx/step-ca.error.log warn;
    
    # Proxy para step-ca (localhost:9000)
    location / {
        proxy_pass http://step_ca_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        
        # Timeouts para step-ca
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Rate limiting
        limit_req zone=api burst=30 nodelay;
        
        # Buffers para certificados grandes
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
    
    # Health check específico
    location /health {
        proxy_pass http://step_ca_backend/health;
        access_log off;
    }
}
EOF

log "📝 Nova configuração SSL criada"

# Ativar nova configuração
ln -sf /etc/nginx/sites-available/samureye-ssl-fixed /etc/nginx/sites-enabled/samureye

# Remover configurações antigas
rm -f /etc/nginx/sites-enabled/samureye-temp 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Testar configuração
log "🧪 Testando configuração NGINX..."
if nginx -t; then
    log "✅ Configuração NGINX SSL válida"
    
    # Verificar se NGINX está rodando
    if systemctl is-active nginx >/dev/null 2>&1; then
        log "🔄 Recarregando NGINX..."
        systemctl reload nginx
        log "✅ NGINX recarregado com configuração SSL corrigida"
    else
        log "🚀 Iniciando NGINX..."
        systemctl start nginx
        if systemctl is-active nginx >/dev/null 2>&1; then
            log "✅ NGINX iniciado com configuração SSL"
        else
            echo "ERROR: Falha ao iniciar NGINX"
            systemctl status nginx --no-pager
            exit 1
        fi
    fi
    
    # Aguardar estabilização
    sleep 3
    
    # Verificar se step-ca está rodando
    log "🔍 Verificando step-ca..."
    if systemctl is-active step-ca >/dev/null 2>&1; then
        log "✅ step-ca está ativo"
    else
        log "⚠️ step-ca não está ativo, iniciando..."
        systemctl start step-ca
        sleep 2
    fi
    
    # Testar conectividade
    log "🌐 Testando conectividade..."
    
    # Teste HTTPS app
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost/health 2>/dev/null | grep -q "200"; then
        log "✅ HTTPS app funcionando (proxy para vlxsam02:5000)"
    else
        log "⚠️ HTTPS app pode não estar respondendo"
    fi
    
    # Teste HTTPS CA
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:443 -H "Host: ca.samureye.com.br" 2>/dev/null | grep -q "200"; then
        log "✅ HTTPS step-ca funcionando (proxy para localhost:9000)"
    else
        log "⚠️ HTTPS step-ca pode não estar respondendo"
    fi
    
    # Mostrar status
    log "📊 Status dos serviços:"
    echo "  NGINX: $(systemctl is-active nginx)"
    echo "  step-ca: $(systemctl is-active step-ca)"
    
    # Mostrar URLs disponíveis
    log "🔗 URLs configuradas:"
    echo "  Aplicação SamurEye: https://app.samureye.com.br"
    echo "                      https://api.samureye.com.br"
    echo "                      https://samureye.com.br"
    echo "  step-ca CA:         https://ca.samureye.com.br"
    echo "  Health checks:      https://app.samureye.com.br/health"
    echo "                      https://ca.samureye.com.br/health"
    
    log "✅ Configuração NGINX SSL corrigida com sucesso!"
    
else
    echo "ERROR: Configuração NGINX inválida"
    nginx -t
    exit 1
fi