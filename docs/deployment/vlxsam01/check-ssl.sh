#!/bin/bash

# Script para verificar certificados SSL existentes no vlxsam01
# e configurar NGINX para usar o certificado wildcard

set -e

# Função para logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >&2
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

log "🔍 Verificando certificados SSL existentes..."

# Verificar se Let's Encrypt está instalado
if ! command -v certbot >/dev/null 2>&1; then
    log "Certbot não encontrado, instalando..."
    apt-get update
    apt-get install -y certbot python3-certbot-nginx
fi

# Listar certificados existentes
log "📜 Certificados Let's Encrypt encontrados:"
if [ -d "/etc/letsencrypt/live" ]; then
    ls -la /etc/letsencrypt/live/
    
    # Verificar cada certificado
    for cert_dir in /etc/letsencrypt/live/*/; do
        if [ -d "$cert_dir" ]; then
            domain=$(basename "$cert_dir")
            log "🔑 Certificado: $domain"
            
            # Mostrar informações do certificado
            if [ -f "$cert_dir/fullchain.pem" ]; then
                log "   📅 Informações do certificado:"
                openssl x509 -in "$cert_dir/fullchain.pem" -text -noout | grep -E "(Subject:|Not Before|Not After|DNS:)"
                echo ""
            fi
        fi
    done
else
    warn "Diretório /etc/letsencrypt/live não encontrado"
fi

# Verificar status dos certificados via certbot
log "📊 Status dos certificados:"
certbot certificates 2>/dev/null || log "Nenhum certificado gerenciado pelo certbot encontrado"

# Verificar se existe certificado para samureye.com.br
CERT_PATH="/etc/letsencrypt/live/samureye.com.br"
if [ -d "$CERT_PATH" ]; then
    log "✅ Certificado wildcard para samureye.com.br encontrado!"
    
    # Verificar validade
    log "🔍 Verificando validade do certificado..."
    EXPIRY=$(openssl x509 -in "$CERT_PATH/fullchain.pem" -noout -enddate | cut -d= -f2)
    log "   Expira em: $EXPIRY"
    
    # Verificar se é wildcard
    DOMAINS=$(openssl x509 -in "$CERT_PATH/fullchain.pem" -text -noout | grep -A1 "Subject Alternative Name" | grep DNS)
    log "   Domínios cobertos: $DOMAINS"
    
    # Configurar NGINX para usar o certificado
    log "⚙️ Configurando NGINX para usar certificado SSL..."
    
    # Backup da configuração atual
    cp /etc/nginx/sites-available/samureye-temp /etc/nginx/sites-available/samureye-temp.backup 2>/dev/null || true
    
    # Criar configuração SSL completa
    cat > /etc/nginx/sites-available/samureye-ssl << 'EOF'
# HTTPS (SSL) - Configuração principal
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ca.samureye.com.br *.samureye.com.br samureye.com.br;

    # Certificados SSL
    ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;
    
    # Configurações SSL otimizadas
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    
    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Rate limiting
    limit_req zone=api burst=20 nodelay;
    limit_conn conn_limit_per_ip 50;
    
    # step-ca Certificate Authority proxy
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        
        # Timeouts para step-ca
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # WebSocket support (se necessário)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}

# HTTP - Redirect para HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ca.samureye.com.br *.samureye.com.br samureye.com.br;
    
    # Let's Encrypt validation
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Redirect para HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}
EOF

    # Ativar configuração SSL
    log "🔗 Ativando configuração SSL..."
    ln -sf /etc/nginx/sites-available/samureye-ssl /etc/nginx/sites-enabled/samureye
    
    # Remover configuração temporária sem SSL
    rm -f /etc/nginx/sites-enabled/samureye-temp 2>/dev/null || true
    
    # Testar configuração
    if nginx -t; then
        log "✅ Configuração NGINX SSL válida"
        
        # Recarregar NGINX
        if systemctl reload nginx 2>/dev/null; then
            log "✅ NGINX recarregado com certificado SSL"
        else
            log "NGINX não está rodando, iniciando..."
            systemctl start nginx
            if systemctl is-active nginx >/dev/null 2>&1; then
                log "✅ NGINX iniciado com certificado SSL"
            else
                error "❌ Falha ao iniciar NGINX"
            fi
        fi
        
        # Verificar se HTTPS está funcionando
        log "🔍 Testando conexão HTTPS..."
        if curl -k -s https://ca.samureye.com.br/health >/dev/null 2>&1; then
            log "✅ HTTPS funcionando corretamente"
        else
            warn "HTTPS pode não estar respondendo ainda"
        fi
        
    else
        error "❌ Erro na configuração NGINX SSL"
    fi
    
else
    warn "❌ Certificado para samureye.com.br não encontrado"
    log "💡 Para gerar um novo certificado wildcard, execute:"
    echo "   certbot certonly --manual --preferred-challenges=dns -d samureye.com.br -d '*.samureye.com.br'"
fi

log "✅ Verificação de certificados SSL concluída"