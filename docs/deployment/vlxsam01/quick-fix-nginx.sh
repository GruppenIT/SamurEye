#!/bin/bash

# Quick fix para problemas comuns nginx proxy no vlxsam01
# Corrige página em branco no HTTPS

set -e

echo "=== Quick Fix NGINX Proxy vlxsam01 ==="

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_ok() { echo -e "${GREEN}✅ $1${NC}"; }
print_fail() { echo -e "${RED}❌ $1${NC}"; }

# Verificar se é root
[ "$EUID" -ne 0 ] && { print_fail "Execute como root"; exit 1; }

# Backup rápido
cp /etc/nginx/sites-enabled/* /root/ 2>/dev/null || true

# Encontrar certificado Let's Encrypt
CERT_DIR=""
for dir in /etc/letsencrypt/live/*; do
    if [ -d "$dir" ] && [ -f "$dir/cert.pem" ]; then
        CERT_DIR="$dir"
        break
    fi
done

[ -z "$CERT_DIR" ] && { print_fail "Certificado Let's Encrypt não encontrado"; exit 1; }
print_ok "Certificado encontrado: $CERT_DIR"

# Criar configuração mínima funcional
cat > /etc/nginx/sites-available/samureye-simple.conf << EOF
# Configuração simples SamurEye
upstream backend {
    server 172.24.1.152:5000;
}

# HTTP redirect
server {
    listen 80;
    server_name app.samureye.com.br api.samureye.com.br ca.samureye.com.br;
    location / { return 301 https://\$server_name\$request_uri; }
}

# HTTPS
server {
    listen 443 ssl;
    server_name app.samureye.com.br api.samureye.com.br ca.samureye.com.br;
    
    ssl_certificate $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;
    
    location / {
        proxy_pass http://backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
    }
}
EOF

# Remover configurações antigas
rm -f /etc/nginx/sites-enabled/*

# Habilitar nova configuração
ln -s /etc/nginx/sites-available/samureye-simple.conf /etc/nginx/sites-enabled/

# Testar configuração
if nginx -t; then
    print_ok "Configuração válida"
    systemctl reload nginx
    print_ok "NGINX recarregado"
    
    # Teste rápido
    sleep 2
    if curl -s -k https://127.0.0.1/ >/dev/null; then
        print_ok "HTTPS funcionando"
        echo "✅ CORREÇÃO CONCLUÍDA! Teste: https://app.samureye.com.br"
    else
        print_fail "HTTPS ainda com problemas"
    fi
else
    print_fail "Erro na configuração nginx"
    nginx -t
fi