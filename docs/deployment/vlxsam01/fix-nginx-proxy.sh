#!/bin/bash

# Script para diagnosticar e corrigir configuração nginx no vlxsam01
# Resolve problema de página em branco no HTTPS

set -e

echo "=== Diagnóstico e Correção NGINX Proxy (vlxsam01) ==="

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK") echo -e "${GREEN}✅ $message${NC}" ;;
        "FAIL") echo -e "${RED}❌ $message${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "INFO") echo -e "${BLUE}ℹ️  $message${NC}" ;;
    esac
}

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    print_status "FAIL" "Este script deve ser executado como root"
    exit 1
fi

# Verificar se nginx está instalado
if ! command -v nginx >/dev/null 2>&1; then
    print_status "FAIL" "NGINX não está instalado"
    exit 1
fi

# Verificar status do nginx
if systemctl is-active --quiet nginx; then
    print_status "OK" "NGINX está rodando"
else
    print_status "WARN" "NGINX não está rodando, iniciando..."
    systemctl start nginx
    if systemctl is-active --quiet nginx; then
        print_status "OK" "NGINX iniciado com sucesso"
    else
        print_status "FAIL" "Falha ao iniciar NGINX"
        exit 1
    fi
fi

# Verificar conectividade com vlxsam02
BACKEND_HOST="172.24.1.152"
BACKEND_PORT="5000"

print_status "INFO" "Testando conectividade com backend $BACKEND_HOST:$BACKEND_PORT..."
if curl -s --connect-timeout 5 "http://$BACKEND_HOST:$BACKEND_PORT/api/system/settings" >/dev/null; then
    print_status "OK" "Backend vlxsam02:5000 está respondendo"
else
    print_status "FAIL" "Backend vlxsam02:5000 não está respondendo"
    print_status "INFO" "Verificar se serviço samureye-app está rodando no vlxsam02"
    exit 1
fi

# Backup da configuração atual
NGINX_CONF_DIR="/etc/nginx"
BACKUP_DIR="/root/nginx-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r "$NGINX_CONF_DIR"/* "$BACKUP_DIR"/ 2>/dev/null || true
print_status "OK" "Backup criado em $BACKUP_DIR"

# Verificar certificados Let's Encrypt
CERT_PATH="/etc/letsencrypt/live"
if [ -d "$CERT_PATH" ]; then
    # Encontrar certificado para app.samureye.com.br
    cert_dir=""
    for dir in "$CERT_PATH"/*; do
        if [ -d "$dir" ] && (echo "$dir" | grep -q "samureye" || [ -f "$dir/cert.pem" ]); then
            cert_dir="$dir"
            break
        fi
    done
    
    if [ -n "$cert_dir" ]; then
        print_status "OK" "Certificados encontrados em $cert_dir"
        
        # Verificar se certificados são válidos
        if openssl x509 -in "$cert_dir/cert.pem" -noout -dates >/dev/null 2>&1; then
            print_status "OK" "Certificados são válidos"
            expiry=$(openssl x509 -in "$cert_dir/cert.pem" -noout -enddate | cut -d= -f2)
            print_status "INFO" "Certificado expira em: $expiry"
        else
            print_status "WARN" "Certificados podem estar corrompidos"
        fi
    else
        print_status "FAIL" "Certificados Let's Encrypt não encontrados"
        exit 1
    fi
else
    print_status "FAIL" "Diretório Let's Encrypt não existe"
    exit 1
fi

# Criar configuração nginx otimizada
print_status "INFO" "Criando configuração nginx otimizada..."

cat > "$NGINX_CONF_DIR/sites-available/samureye.conf" << 'EOF'
# Configuração NGINX para SamurEye - Proxy Reverso
# vlxsam01 -> vlxsam02:5000

# Rate limiting
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=app:10m rate=30r/s;

# Upstream backend
upstream samureye_backend {
    server 172.24.1.152:5000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# HTTP -> HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name app.samureye.com.br api.samureye.com.br ca.samureye.com.br;
    
    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Redirect everything else to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS - Aplicação Principal
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name app.samureye.com.br;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/app.samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.samureye.com.br/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/app.samureye.com.br/chain.pem;
    
    # SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    
    # Buffer sizes
    proxy_buffering on;
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;
    
    # Rate limiting
    limit_req zone=app burst=50 nodelay;
    
    # Proxy headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    
    # Main application
    location / {
        proxy_pass http://samureye_backend;
        
        # Error handling
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 60s;
    }
    
    # API routes
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://samureye_backend;
    }
    
    # WebSocket
    location /ws {
        proxy_pass http://samureye_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Static assets caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://samureye_backend;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Health check
    location /health {
        access_log off;
        proxy_pass http://samureye_backend;
    }
}

# HTTPS - API
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.samureye.com.br;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/app.samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.samureye.com.br/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/app.samureye.com.br/chain.pem;
    
    # SSL Security (same as app)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # Headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    
    # Rate limiting for API
    limit_req zone=api burst=10 nodelay;
    
    # API only
    location / {
        proxy_pass http://samureye_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTPS - Certificate Authority
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ca.samureye.com.br;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/app.samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.samureye.com.br/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/app.samureye.com.br/chain.pem;
    
    # SSL Security (same as app)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # Headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # CA endpoints (step-ca ou similar)
    location / {
        proxy_pass http://samureye_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Desabilitar configuração padrão se existir
if [ -L "$NGINX_CONF_DIR/sites-enabled/default" ]; then
    unlink "$NGINX_CONF_DIR/sites-enabled/default"
    print_status "OK" "Configuração padrão desabilitada"
fi

# Habilitar nova configuração
if [ ! -L "$NGINX_CONF_DIR/sites-enabled/samureye.conf" ]; then
    ln -s "$NGINX_CONF_DIR/sites-available/samureye.conf" "$NGINX_CONF_DIR/sites-enabled/"
    print_status "OK" "Nova configuração habilitada"
fi

# Testar configuração nginx
print_status "INFO" "Testando configuração nginx..."
if nginx -t; then
    print_status "OK" "Configuração nginx válida"
else
    print_status "FAIL" "Erro na configuração nginx"
    print_status "INFO" "Restaurando backup..."
    cp -r "$BACKUP_DIR"/* "$NGINX_CONF_DIR"/ 2>/dev/null || true
    nginx -t
    exit 1
fi

# Recarregar nginx
print_status "INFO" "Recarregando nginx..."
systemctl reload nginx

if systemctl is-active --quiet nginx; then
    print_status "OK" "NGINX recarregado com sucesso"
else
    print_status "FAIL" "Erro ao recarregar nginx"
    exit 1
fi

# Testes de conectividade
print_status "INFO" "Testando conectividade HTTPS..."

# Teste interno
sleep 2
response=$(curl -s -o /dev/null -w "%{http_code}" -k https://127.0.0.1/api/system/settings 2>/dev/null || echo "000")
case "$response" in
    "200") print_status "OK" "Teste interno HTTPS funcionando (200)" ;;
    "401") print_status "OK" "Teste interno HTTPS funcionando (401 - normal)" ;;
    "000") print_status "FAIL" "Teste interno HTTPS falhou - sem resposta" ;;
    *) print_status "WARN" "Teste interno HTTPS retorna código $response" ;;
esac

# Verificar logs nginx
print_status "INFO" "Verificando logs nginx recentes..."
tail -n 5 /var/log/nginx/error.log 2>/dev/null | while IFS= read -r line; do
    if [ -n "$line" ]; then
        print_status "INFO" "Log: $line"
    fi
done

# Verificar portas
print_status "INFO" "Verificando portas abertas..."
ss -tlnp | grep ":443" >/dev/null && print_status "OK" "Porta 443 (HTTPS) aberta" || print_status "FAIL" "Porta 443 não está aberta"
ss -tlnp | grep ":80" >/dev/null && print_status "OK" "Porta 80 (HTTP) aberta" || print_status "FAIL" "Porta 80 não está aberta"

echo ""
print_status "OK" "CONFIGURAÇÃO NGINX CONCLUÍDA!"
echo ""
print_status "INFO" "Teste agora:"
echo "   1. Acesse https://app.samureye.com.br"
echo "   2. Verifique se página não está mais em branco"
echo "   3. Teste login e funcionalidades"
echo ""
print_status "INFO" "Diagnóstico adicional:"
echo "   - Logs nginx: tail -f /var/log/nginx/error.log"
echo "   - Status nginx: systemctl status nginx"
echo "   - Teste conectividade: curl -I https://app.samureye.com.br"
echo ""