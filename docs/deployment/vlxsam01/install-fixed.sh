#!/bin/bash

# Script de instalação corrigido para vlxsam01 (Gateway Server)
# Versão: 2.0 - 26/08/2025
# Corrige: Directory creation error + NGINX SSL order

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./install-fixed.sh"
fi

log "🚀 Iniciando instalação CORRIGIDA do SamurEye Gateway (vlxsam01)..."

# ============================================================================
# 1. CONFIGURAÇÃO SISTEMA BASE
# ============================================================================

info "📋 Configurando sistema base..."

log "Atualizando sistema Ubuntu..."
apt update -qq && apt upgrade -y -qq

log "Configurando timezone para America/Sao_Paulo..."
timedatectl set-timezone America/Sao_Paulo

log "Instalando pacotes essenciais..."
apt install -y -qq nginx certbot python3-certbot-nginx python3-certbot-dns-cloudflare \
    ufw curl wget git htop unzip jq fail2ban

# ============================================================================
# 2. CONFIGURAÇÃO FIREWALL
# ============================================================================

log "🔥 Configurando firewall UFW..."

# Configurar firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

log "Firewall configurado: SSH (22), HTTP (80), HTTPS (443)"

# ============================================================================
# 3. CONFIGURAÇÃO SSL/TLS
# ============================================================================

log "🔐 Configurando SSL/TLS com Let's Encrypt..."

# Criar diretórios para hooks
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
mkdir -p /etc/letsencrypt/renewal-hooks/pre
mkdir -p /etc/letsencrypt/renewal-hooks/post

# ============================================================================
# 4. CONFIGURAÇÃO NGINX
# ============================================================================

log "⚙️ Configurando NGINX..."

# Criar configuração principal do NGINX
mkdir -p /etc/nginx/conf.d

cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    multi_accept on;
    use epoll;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    # MIME
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                   '$status $body_bytes_sent "$http_referer" '
                   '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
    
    # Compression
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
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    
    # Include sites
    include /etc/nginx/sites-enabled/*;
}
EOF

# Configuração temporária (sem SSL) - será ativada primeiro
cat > /etc/nginx/sites-available/samureye-temp << 'EOF'
# Configuração temporária SamurEye (sem SSL)
# Ativada durante instalação até obter certificados

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    
    # Security headers básicos
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Health check interno
    location /nginx-health {
        access_log off;
        return 200 "nginx-ok";
        add_header Content-Type text/plain;
    }
    
    # Proxy para vlxsam02 (quando disponível)
    location / {
        proxy_pass http://172.24.1.152:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
        
        # Fallback se vlxsam02 não responder
        error_page 502 503 504 @fallback;
    }
    
    # Fallback quando backend não está disponível
    location @fallback {
        return 200 "SamurEye Gateway - Backend em preparação";
        add_header Content-Type text/plain;
    }
}
EOF

# Configuração final (com SSL) - será ativada após obter certificados
cat > /etc/nginx/sites-available/samureye << 'EOF'
# Configuração final SamurEye (com SSL)
# Ativada após obter certificados via /opt/request-ssl.sh

# Redirecionamento HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name samureye.com.br app.samureye.com.br api.samureye.com.br;
    
    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Forçar HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# Servidor HTTPS principal
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name app.samureye.com.br samureye.com.br;
    
    # Certificados SSL
    ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/samureye.com.br/chain.pem;
    
    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Rate limiting
    limit_req zone=general burst=20 nodelay;
    
    # Logs específicos
    access_log /var/log/nginx/samureye-access.log main;
    error_log /var/log/nginx/samureye-error.log;
    
    # Health check
    location /nginx-health {
        access_log off;
        return 200 "nginx-ssl-ok";
        add_header Content-Type text/plain;
    }
    
    # WebSocket support
    location /ws {
        proxy_pass http://172.24.1.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
    
    # API routes
    location /api/ {
        limit_req zone=api burst=10 nodelay;
        
        proxy_pass http://172.24.1.152:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeout para APIs
        proxy_connect_timeout 10s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # Frontend routes
    location / {
        proxy_pass http://172.24.1.152:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Cache para assets estáticos
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
}

# Servidor API separado (opcional)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.samureye.com.br;
    
    # Mesmos certificados SSL
    ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/samureye.com.br/chain.pem;
    
    # Configurações SSL iguais ao servidor principal
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Headers de segurança
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff always;
    
    # Rate limiting mais restritivo para API
    limit_req zone=api burst=5 nodelay;
    
    # Logs separados para API
    access_log /var/log/nginx/api-access.log main;
    error_log /var/log/nginx/api-error.log;
    
    # Todas as requests vão para a API
    location / {
        proxy_pass http://172.24.1.152:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts para API
        proxy_connect_timeout 5s;
        proxy_send_timeout 15s;
        proxy_read_timeout 15s;
    }
}
EOF

# Criar diretório para challenge
mkdir -p /var/www/html/.well-known/acme-challenge
chown -R www-data:www-data /var/www/html

# Desabilitar configuração default
rm -f /etc/nginx/sites-enabled/default

log "Ativando configuração temporária (sem SSL)..."
ln -sf /etc/nginx/sites-available/samureye-temp /etc/nginx/sites-enabled/samureye-temp

# Testar configuração
nginx -t

log "NGINX configurado temporariamente (HTTP apenas)"

# ============================================================================
# 5. CONFIGURAÇÃO DE CERTIFICADOS SSL
# ============================================================================

log "📜 Configurando certificados SSL..."

# Criar script de solicitação de certificado (HTTP-01 challenge)
cat > /opt/request-ssl.sh << 'EOF'
#!/bin/bash

# Script para solicitar certificado SSL para SamurEye
# Usa HTTP-01 challenge (mais simples)

set -e

echo "🔐 Solicitando certificado SSL com HTTP-01 challenge..."

# Solicitar certificado usando HTTP-01 (mais simples que DNS)
certbot certonly \
    --webroot \
    --webroot-path=/var/www/html \
    --email admin@samureye.com.br \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    -d samureye.com.br \
    -d app.samureye.com.br \
    -d api.samureye.com.br

echo "✅ Certificado obtido. Ativando configuração HTTPS..."

# Ativar configuração final com SSL
ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/samureye

# Testar configuração final
nginx -t

# Recarregar NGINX
systemctl reload nginx

echo "🚀 SSL configurado com sucesso!"
echo "Acesse: https://app.samureye.com.br"
EOF

chmod +x /opt/request-ssl.sh

# Criar script wildcard para DNS challenge (manual)
cat > /opt/request-ssl-wildcard.sh << 'EOF'
#!/bin/bash

# Script para solicitar certificado SSL wildcard (manual)
# Execute após configurar DNS TXT records

echo "🔐 Solicitando certificado SSL wildcard (DNS challenge)..."

# Solicitar certificado wildcard usando DNS challenge
certbot certonly \
    --manual \
    --preferred-challenges=dns \
    --email admin@samureye.com.br \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --agree-tos \
    --no-eff-email \
    -d samureye.com.br \
    -d "*.samureye.com.br"

if [ $? -eq 0 ]; then
    echo "✅ Certificado wildcard obtido!"
    
    # Ativar configuração final com SSL
    ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/samureye
    
    # Testar e recarregar
    nginx -t && systemctl reload nginx
    
    echo "🚀 SSL wildcard configurado!"
    echo "Suporta todos os subdomínios: *.samureye.com.br"
else
    echo "❌ Falha ao obter certificado wildcard"
    exit 1
fi
EOF

chmod +x /opt/request-ssl-wildcard.sh

# ============================================================================
# 6. SCRIPTS DE MONITORAMENTO
# ============================================================================

log "📊 Criando scripts de monitoramento..."

# CORREÇÃO CRÍTICA: Criar diretório ANTES de usar
mkdir -p /opt/samureye/scripts

# Script de health check
cat > /opt/samureye/scripts/health-check.sh << 'EOF'
#!/bin/bash

# Health check completo para vlxsam01

echo "=== SAMUREYE GATEWAY HEALTH CHECK ==="
echo "Data: $(date)"
echo "Servidor: vlxsam01 ($(hostname -I | awk '{print $1}'))"
echo ""

# Verificar NGINX
echo "🌐 NGINX:"
if systemctl is-active --quiet nginx; then
    echo "✅ Serviço ativo"
else
    echo "❌ Serviço inativo"
fi

# Verificar configuração
if nginx -t >/dev/null 2>&1; then
    echo "✅ Configuração válida"
else
    echo "❌ Configuração inválida"
fi

# Verificar certificados SSL
echo ""
echo "🔐 CERTIFICADOS SSL:"
cert_file="/etc/letsencrypt/live/samureye.com.br/fullchain.pem"
if [ -f "$cert_file" ]; then
    expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    expiry_epoch=$(date -d "$expiry_date" +%s)
    current_epoch=$(date +%s)
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [ $days_until_expiry -gt 30 ]; then
        echo "✅ Certificado válido ($days_until_expiry dias restantes)"
    elif [ $days_until_expiry -gt 7 ]; then
        echo "⚠️ Certificado expira em $days_until_expiry dias"
    else
        echo "❌ Certificado expira em $days_until_expiry dias - URGENTE"
    fi
else
    echo "⚠️ Certificado não encontrado (usando HTTP)"
fi

# Verificar conectividade backend
echo ""
echo "🔗 BACKEND (vlxsam02:5000):"
if nc -z 172.24.1.152 5000 2>/dev/null; then
    echo "✅ vlxsam02 acessível"
else
    echo "⚠️ vlxsam02 não acessível"
fi

# Testar health check local
echo ""
echo "🧪 TESTES:"
if curl -f -s http://localhost/nginx-health >/dev/null; then
    echo "✅ Health check HTTP"
else
    echo "❌ Health check HTTP falhou"
fi

if curl -f -s -k https://localhost/nginx-health >/dev/null; then
    echo "✅ Health check local"
else
    echo "❌ Health check local falhou"
fi

# Recursos do sistema
echo ""
echo "💻 RECURSOS:"
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
mem_usage=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')
disk_usage=$(df -h / | awk 'NR==2 {print $5}')

echo "CPU: ${cpu_usage}%"
echo "Memória: $mem_usage"
echo "Disco: $disk_usage"

# Conexões ativas
echo ""
echo "🔌 CONEXÕES:"
connections=$(netstat -an | grep :443 | grep ESTABLISHED | wc -l)
echo "HTTPS ativas: $connections"

echo ""
echo "=== FIM DO HEALTH CHECK ==="
EOF

chmod +x /opt/samureye/scripts/health-check.sh

# Script de verificação SSL
cat > /opt/samureye/scripts/check-ssl.sh << 'EOF'
#!/bin/bash

# Verificação específica de certificados SSL

echo "🔐 VERIFICAÇÃO DE CERTIFICADOS SSL"
echo "================================="

cert_file="/etc/letsencrypt/live/samureye.com.br/fullchain.pem"

if [ -f "$cert_file" ]; then
    echo "Certificado encontrado: $cert_file"
    echo ""
    
    # Informações do certificado
    echo "📋 INFORMAÇÕES DO CERTIFICADO:"
    openssl x509 -in "$cert_file" -noout -subject -issuer -dates
    echo ""
    
    # Verificar domínios
    echo "🌐 DOMÍNIOS COBERTOS:"
    openssl x509 -in "$cert_file" -noout -text | grep -A1 "Subject Alternative Name" | tail -1
    echo ""
    
    # Testar HTTPS
    echo "🧪 TESTE HTTPS:"
    for domain in "app.samureye.com.br" "api.samureye.com.br"; do
        if curl -f -s -I "https://$domain/nginx-health" >/dev/null 2>&1; then
            echo "✅ $domain"
        else
            echo "❌ $domain (verifique DNS)"
        fi
    done
    
else
    echo "❌ Certificado não encontrado"
    echo ""
    echo "💡 PARA OBTER CERTIFICADO:"
    echo "/opt/request-ssl.sh"
    echo ""
    echo "💡 PARA CERTIFICADO WILDCARD:"
    echo "/opt/request-ssl-wildcard.sh"
fi

echo ""
echo "================================="
EOF

chmod +x /opt/samureye/scripts/check-ssl.sh

# ============================================================================
# 7. CONFIGURAÇÃO DE LOGS
# ============================================================================

log "📄 Configurando rotação de logs..."

cat > /etc/logrotate.d/nginx-samureye << 'EOF'
/var/log/nginx/samureye-*.log
/var/log/nginx/api-*.log
{
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 www-data www-data
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 $(cat /var/run/nginx.pid)
        fi
    endscript
}
EOF

# ============================================================================
# 8. CONFIGURAÇÃO FAIL2BAN
# ============================================================================

log "🛡️ Configurando Fail2Ban..."

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
action = iptables-multiport[name=ReqLimit, port="http,https", protocol=tcp]
logpath = /var/log/nginx/samureye-error.log
maxretry = 10
findtime = 600
bantime = 7200
EOF

systemctl enable fail2ban
systemctl start fail2ban

# ============================================================================
# 9. CRON JOBS
# ============================================================================

log "⏰ Configurando cron jobs..."

# Cron para health check
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/samureye/scripts/health-check.sh >> /var/log/samureye/health-check.log 2>&1") | crontab -

# Cron para renovação SSL (2x por dia)
(crontab -l 2>/dev/null; echo "0 2,14 * * * certbot renew --quiet") | crontab -

# ============================================================================
# 10. FINALIZAÇÃO
# ============================================================================

# Criar diretórios de log
mkdir -p /var/log/samureye
touch /var/log/samureye/health-check.log
chown www-data:www-data /var/log/samureye/health-check.log

# Habilitar e iniciar serviços
systemctl enable nginx
systemctl start nginx

# Verificar status
if systemctl is-active --quiet nginx; then
    log "✅ NGINX iniciado com sucesso"
else
    error "❌ Falha ao iniciar NGINX"
fi

log "🎉 Instalação CORRIGIDA do vlxsam01 concluída com sucesso!"

echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "=================="
echo ""
echo "1. Solicitar certificado SSL:"
echo "   /opt/request-ssl.sh"
echo ""
echo "2. Configurar DNS para *.samureye.com.br apontando para $(hostname -I | awk '{print $1}')"
echo ""
echo "3. Testar configuração:"
echo "   /opt/samureye/scripts/health-check.sh"
echo "   /opt/samureye/scripts/check-ssl.sh"
echo ""
echo "4. Verificar logs:"
echo "   tail -f /var/log/nginx/samureye-access.log"
echo "   tail -f /var/log/nginx/samureye-error.log"
echo ""
echo "🌐 URLs configuradas:"
echo "   https://app.samureye.com.br"
echo "   https://api.samureye.com.br"
echo ""
echo "⚠️  IMPORTANTE: Configure o DNS e SSL antes de prosseguir com vlxsam02"
echo ""
echo "🔧 CORREÇÕES APLICADAS:"
echo "   ✅ Directory creation order fixed"
echo "   ✅ NGINX SSL configuration separated"
echo "   ✅ Two-stage installation process"