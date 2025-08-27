#!/bin/bash

# Script para configurar NGINX como proxy reverso para SamurEye
# Este script configura NGINX para servir o app em HTTPS na porta 443

set -e

echo "=== CONFIGURANDO NGINX PROXY REVERSO PARA SAMUREYE ==="

# Verificar se script está sendo executado como root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Este script deve ser executado como root (sudo)"
   exit 1
fi

# Instalar NGINX se não estiver instalado
if ! command -v nginx &> /dev/null; then
    echo "📦 Instalando NGINX..."
    apt update
    apt install -y nginx
fi

# Parar NGINX se estiver rodando
systemctl stop nginx 2>/dev/null || true

# Backup da configuração existente
if [ -f /etc/nginx/sites-available/default ]; then
    cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup.$(date +%Y%m%d_%H%M%S)
fi

# Criar configuração do SamurEye
cat > /etc/nginx/sites-available/samureye << 'EOF'
# Configuração NGINX para SamurEye
upstream samureye_backend {
    server 127.0.0.1:5000;
    keepalive 32;
}

# Redirecionamento HTTP -> HTTPS
server {
    listen 80;
    server_name app.samureye.com.br samureye.com.br *.samureye.com.br;
    
    # Redirecionar tudo para HTTPS
    return 301 https://$server_name$request_uri;
}

# Servidor HTTPS principal
server {
    listen 443 ssl http2;
    server_name app.samureye.com.br;
    
    # SSL Configuration (placeholder - certificados devem ser configurados)
    ssl_certificate /etc/ssl/certs/samureye.crt;
    ssl_certificate_key /etc/ssl/private/samureye.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    
    # Logs
    access_log /var/log/nginx/samureye_access.log;
    error_log /var/log/nginx/samureye_error.log;
    
    # Proxy para aplicação SamurEye
    location / {
        proxy_pass http://samureye_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://samureye_backend/api/health;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        access_log off;
    }
}

# Wildcard para outros subdomínios
server {
    listen 443 ssl http2;
    server_name *.samureye.com.br;
    
    ssl_certificate /etc/ssl/certs/samureye.crt;
    ssl_certificate_key /etc/ssl/private/samureye.key;
    
    # Redirecionar para app principal
    return 301 https://app.samureye.com.br$request_uri;
}
EOF

# Remover configuração padrão
rm -f /etc/nginx/sites-enabled/default

# Habilitar configuração do SamurEye
ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/

# Criar certificados SSL auto-assinados temporários (para teste)
echo "🔐 Criando certificados SSL temporários..."
mkdir -p /etc/ssl/private
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/samureye.key \
    -out /etc/ssl/certs/samureye.crt \
    -subj "/C=BR/ST=SP/L=SaoPaulo/O=SamurEye/CN=app.samureye.com.br"

# Definir permissões corretas
chmod 600 /etc/ssl/private/samureye.key
chmod 644 /etc/ssl/certs/samureye.crt

# Testar configuração NGINX
echo "🧪 Testando configuração NGINX..."
nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Configuração NGINX válida"
    
    # Iniciar NGINX
    systemctl enable nginx
    systemctl start nginx
    systemctl status nginx --no-pager -l
    
    echo ""
    echo "=== NGINX CONFIGURADO COM SUCESSO ==="
    echo "🌐 Aplicação disponível em: https://app.samureye.com.br"
    echo "🔐 Certificado SSL: Auto-assinado (temporário)"
    echo "📊 Health check: https://app.samureye.com.br/health"
    echo ""
    echo "⚠️  PRÓXIMOS PASSOS:"
    echo "1. Configurar certificado Let's Encrypt real"
    echo "2. Atualizar DNS para apontar para este servidor ($(hostname -I | awk '{print $1}'))"
    echo "3. Testar conectividade externa"
    
else
    echo "❌ Erro na configuração NGINX"
    exit 1
fi

echo ""
echo "=== TESTES DE CONECTIVIDADE ==="
echo "Local: curl -k https://localhost/health"
echo "Externo: curl -k https://app.samureye.com.br/health"