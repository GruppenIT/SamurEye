#!/bin/bash

# Script para configurar NGINX com certificado SSL wildcard
set -e

# Função para logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🔒 Configurando NGINX com certificado SSL wildcard..."

# Verificar se certificado existe
CERT_PATH="/etc/letsencrypt/live/samureye.com.br"
if [ ! -f "$CERT_PATH/fullchain.pem" ] || [ ! -f "$CERT_PATH/privkey.pem" ]; then
    echo "ERROR: Certificado não encontrado em $CERT_PATH"
    exit 1
fi

log "✅ Certificado SSL encontrado em $CERT_PATH"

# Verificar validade do certificado
EXPIRY=$(openssl x509 -in "$CERT_PATH/fullchain.pem" -noout -enddate | cut -d= -f2)
log "📅 Certificado expira em: $EXPIRY"

# Criar configuração NGINX SSL completa
cat > /etc/nginx/sites-available/samureye-ssl << 'EOF'
# HTTPS (SSL) - Configuração principal SamurEye Gateway
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ca.samureye.com.br *.samureye.com.br samureye.com.br;

    # Certificados SSL wildcard
    ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;
    
    # Configurações SSL modernas e seguras
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/samureye.com.br/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # HSTS (HTTP Strict Transport Security)
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    
    # Headers de segurança
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';" always;
    
    # Rate limiting para step-ca
    limit_req zone=api burst=30 nodelay;
    limit_conn conn_limit_per_ip 100;
    
    # Logs específicos
    access_log /var/log/nginx/samureye-ssl.access.log main;
    error_log /var/log/nginx/samureye-ssl.error.log warn;
    
    # step-ca Certificate Authority - Proxy principal
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Timeouts otimizados para step-ca
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_buffering off;
        
        # WebSocket support para comunicação em tempo real
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Aumentar tamanhos de buffer para certificados grandes
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
    
    # Health check endpoint específico
    location /health {
        access_log off;
        return 200 "SamurEye Gateway OK\n";
        add_header Content-Type text/plain;
    }
    
    # Endpoint para status do step-ca
    location /ca/health {
        proxy_pass http://127.0.0.1:9000/health;
        proxy_set_header Host $host;
        access_log off;
    }
    
    # Proteção adicional para paths administrativos
    location /admin {
        deny all;
        return 403;
    }
}

# HTTP - Redirect automático para HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ca.samureye.com.br *.samureye.com.br samureye.com.br;
    
    # Let's Encrypt ACME validation
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files $uri =404;
    }
    
    # Redirect permanente para HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}
EOF

log "📝 Configuração SSL criada"

# Fazer backup da configuração atual
if [ -f /etc/nginx/sites-enabled/samureye ]; then
    cp /etc/nginx/sites-enabled/samureye /etc/nginx/sites-enabled/samureye.backup.$(date +%Y%m%d_%H%M%S)
    log "🔄 Backup da configuração atual criado"
fi

# Ativar nova configuração SSL
ln -sf /etc/nginx/sites-available/samureye-ssl /etc/nginx/sites-enabled/samureye

# Remover configurações temporárias antigas
rm -f /etc/nginx/sites-enabled/samureye-temp 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Testar configuração NGINX
log "🧪 Testando configuração NGINX..."
if nginx -t; then
    log "✅ Configuração NGINX SSL válida"
    
    # Verificar se NGINX está rodando
    if systemctl is-active nginx >/dev/null 2>&1; then
        log "🔄 Recarregando NGINX..."
        systemctl reload nginx
        log "✅ NGINX recarregado com certificado SSL"
    else
        log "🚀 Iniciando NGINX..."
        systemctl start nginx
        if systemctl is-active nginx >/dev/null 2>&1; then
            log "✅ NGINX iniciado com certificado SSL"
        else
            echo "ERROR: Falha ao iniciar NGINX"
            systemctl status nginx --no-pager
            exit 1
        fi
    fi
    
    # Aguardar NGINX estabilizar
    sleep 3
    
    # Verificar se step-ca está respondendo
    log "🔍 Verificando step-ca..."
    if systemctl is-active step-ca >/dev/null 2>&1; then
        log "✅ step-ca está ativo"
    else
        log "⚠️ step-ca não está ativo, iniciando..."
        systemctl start step-ca
        sleep 2
    fi
    
    # Testar conectividade HTTPS
    log "🌐 Testando conectividade HTTPS..."
    
    # Teste local primeiro
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost/health | grep -q "200"; then
        log "✅ HTTPS local funcionando"
    else
        log "⚠️ HTTPS local pode não estar respondendo ainda"
    fi
    
    # Teste com domínio
    if curl -k -s -o /dev/null -w "%{http_code}" https://ca.samureye.com.br/health | grep -q "200"; then
        log "✅ HTTPS com domínio funcionando"
    else
        log "⚠️ HTTPS com domínio pode não estar respondendo (verifique DNS)"
    fi
    
    # Mostrar status final
    log "📊 Status dos serviços:"
    echo "  NGINX: $(systemctl is-active nginx)"
    echo "  step-ca: $(systemctl is-active step-ca)"
    
    # Mostrar URLs disponíveis
    log "🔗 SamurEye Gateway configurado com SSL:"
    echo "  https://ca.samureye.com.br"
    echo "  https://ca.samureye.com.br/health"
    echo "  https://ca.samureye.com.br/roots.pem"
    
    # Mostrar fingerprint da CA
    if [ -f /etc/step-ca/fingerprint.txt ]; then
        FINGERPRINT=$(cat /etc/step-ca/fingerprint.txt)
        log "🔑 CA Fingerprint: $FINGERPRINT"
    fi
    
    log "✅ Configuração SSL concluída com sucesso!"
    
else
    echo "ERROR: Configuração NGINX inválida"
    nginx -t
    exit 1
fi