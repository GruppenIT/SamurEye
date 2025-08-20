#!/bin/bash
# SamurEye Gateway Installation Script (vlxsam01)
# Execute como root: sudo bash install.sh

set -e

echo "🚀 Iniciando instalação do SamurEye Gateway (vlxsam01)..."

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Este script deve ser executado como root (sudo)"
fi

# Verificar conectividade
log "Verificando conectividade com a internet..."
if ! ping -c 1 google.com &> /dev/null; then
    error "Sem conectividade com a internet"
fi

# Atualizar sistema
log "Atualizando sistema..."
apt update && apt upgrade -y

# Instalar pacotes essenciais
log "Instalando pacotes essenciais..."
apt install -y nginx certbot python3-certbot-nginx ufw fail2ban htop curl wget git unzip software-properties-common

# Instalar plugins DNS para Let's Encrypt
log "Instalando plugins DNS para certificados..."
apt install -y python3-certbot-dns-cloudflare python3-certbot-dns-route53 python3-certbot-dns-google

# Configurar timezone
log "Configurando timezone para America/Sao_Paulo..."
timedatectl set-timezone America/Sao_Paulo

# Configurar firewall UFW
log "Configurando firewall UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Configurar fail2ban
log "Configurando fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-noscript]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 6

[nginx-badbots]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2

[nginx-noproxy]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2

[samureye-api]
enabled = true
port = http,https
logpath = /var/log/nginx/samureye-api.access.log
filter = nginx-req-limit
maxretry = 10
findtime = 600
bantime = 7200
EOF

# Criar filtro personalizado para API
cat > /etc/fail2ban/filter.d/nginx-req-limit.conf << 'EOF'
[Definition]
failregex = limiting requests, excess: .* by zone .*, client: <HOST>
ignoreregex =
EOF

# Reiniciar fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

# Configurar NGINX
log "Configurando NGINX..."

# Criar configuração otimizada do NGINX
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/atom+xml
        application/rss+xml
        application/xhtml+xml
        application/xml
        image/svg+xml;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;

    # Include configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

# Testar configuração do NGINX
if ! nginx -t; then
    error "Erro na configuração do NGINX"
fi

# Criar diretório para logs customizados
mkdir -p /var/log/nginx/samureye

# Remover site default
rm -f /etc/nginx/sites-enabled/default

# Criar página temporária para certificados
mkdir -p /var/www/html
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>SamurEye Gateway</title>
</head>
<body>
    <h1>SamurEye Gateway Ativo</h1>
    <p>Servidor configurado e aguardando certificados SSL.</p>
</body>
</html>
EOF

# Configuração temporária para obter certificados
cat > /etc/nginx/sites-available/temp-cert << 'EOF'
server {
    listen 80;
    server_name app.samureye.com.br api.samureye.com.br scanner.samureye.com.br;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/temp-cert /etc/nginx/sites-enabled/

# Reiniciar NGINX
systemctl enable nginx
systemctl restart nginx

# Verificar se NGINX está rodando
if ! systemctl is-active --quiet nginx; then
    error "NGINX não está rodando"
fi

log "Configuração inicial concluída!"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "1. Configurar DNS para apontar os domínios para este servidor"
echo "2. Configurar certificados SSL usando DNS Challenge (RECOMENDADO):"
echo "   sudo wget https://raw.githubusercontent.com/samureye/setup-certificates/main/setup-certificates.sh"
echo "   sudo chmod +x setup-certificates.sh"
echo "   sudo ./setup-certificates.sh"
echo ""
echo "   OU usar método HTTP tradicional:"
echo "   sudo certbot --nginx -d app.samureye.com.br -d api.samureye.com.br -d scanner.samureye.com.br"
echo ""
echo "3. Copiar a configuração do NGINX (nginx-samureye.conf) para /etc/nginx/sites-available/samureye"
echo "4. Ativar: sudo ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/"
echo "5. Remover configuração temporária: sudo rm /etc/nginx/sites-enabled/temp-cert"
echo "6. Testar e reiniciar: sudo nginx -t && sudo systemctl reload nginx"
echo ""
echo "🔒 VANTAGENS DO DNS CHALLENGE:"
echo "- Certificados wildcard (*.samureye.com.br)"
echo "- Maior segurança"
echo "- Não requer parar o servidor"
echo "- Renovação automática mais confiável"
echo ""
echo "✅ Instalação do Gateway concluída com sucesso!"