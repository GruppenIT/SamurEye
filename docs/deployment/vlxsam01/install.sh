#!/bin/bash

# SamurEye vlxsam01 - Gateway Server Installation
# Servidor: vlxsam01 (172.24.1.151)
# Função: NGINX Gateway com SSL/TLS, Rate Limiting e Proxy Reverso

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de logging
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./install.sh"
fi

log "🚀 Iniciando instalação do SamurEye Gateway (vlxsam01)..."

# ============================================================================
# 1. PREPARAÇÃO DO SISTEMA
# ============================================================================

info "📋 Configurando sistema base..."

# Atualizar sistema
log "Atualizando sistema Ubuntu..."
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y

# Configurar timezone
log "Configurando timezone para America/Sao_Paulo..."
timedatectl set-timezone America/Sao_Paulo

# Instalar pacotes essenciais
log "Instalando pacotes essenciais..."
apt-get install -y \
    nginx \
    certbot \
    python3-certbot-nginx \
    python3-certbot-dns-cloudflare \
    ufw \
    curl \
    wget \
    git \
    htop \
    unzip \
    jq \
    fail2ban

# ============================================================================
# 2. CONFIGURAÇÃO DE FIREWALL
# ============================================================================

log "🔥 Configurando firewall UFW..."

# Configurar UFW
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH, HTTP e HTTPS
ufw allow ssh
ufw allow 80/tcp comment "HTTP (redirect to HTTPS)"
ufw allow 443/tcp comment "HTTPS"

# Ativar firewall
ufw --force enable

log "Firewall configurado: SSH (22), HTTP (80), HTTPS (443)"

# ============================================================================
# 3. CONFIGURAÇÃO SSL/TLS
# ============================================================================

log "🔐 Configurando SSL/TLS com Let's Encrypt..."

# Criar diretórios para certificados
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
mkdir -p /etc/letsencrypt/renewal-hooks/pre
mkdir -p /etc/letsencrypt/renewal-hooks/post

# Script de configuração DNS para certificados
cat > /etc/letsencrypt/renewal-hooks/deploy/dns-config.sh << 'EOF'
#!/bin/bash

# Configuração DNS para renovação de certificados
# Edite conforme seu provedor DNS

log_file="/var/log/letsencrypt/deploy-hook.log"

echo "$(date): Deploy hook executado para domínio $RENEWED_DOMAINS" >> "$log_file"

# Recarregar NGINX após renovação
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
    echo "$(date): NGINX recarregado com sucesso" >> "$log_file"
else
    echo "$(date): ERRO: NGINX não está rodando" >> "$log_file"
fi
EOF

chmod +x /etc/letsencrypt/renewal-hooks/deploy/dns-config.sh

# ============================================================================
# 4. CONFIGURAÇÃO DO NGINX
# ============================================================================

log "⚙️ Configurando NGINX..."

# Backup da configuração padrão
if [ -f /etc/nginx/nginx.conf ]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
fi

# Configuração principal do NGINX
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
    # Configurações básicas
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 100;
    types_hash_max_size 2048;
    server_tokens off;

    # MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Rate limiting zones
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;
    limit_req_zone $binary_remote_addr zone=auth:10m rate=20r/m;
    limit_req_zone $binary_remote_addr zone=upload:10m rate=10r/m;
    limit_req_zone $binary_remote_addr zone=general:10m rate=1000r/m;

    # Connection limiting
    limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;

    # Configurações de log
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

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
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Include configurações
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

# Criar diretório para configurações específicas
mkdir -p /etc/nginx/conf.d

# Configuração upstream para vlxsam02
cat > /etc/nginx/conf.d/upstream.conf << 'EOF'
# Upstream para aplicação SamurEye em vlxsam02
upstream samureye_app {
    server 172.24.1.152:3000 max_fails=3 fail_timeout=30s;
    # Adicionar mais servidores aqui para load balancing
    # server 172.24.1.152:3001 backup;
    
    keepalive 16;
}

# Upstream para WebSocket
upstream samureye_ws {
    server 172.24.1.152:3000;
    keepalive 16;
}
EOF

# Remover configuração padrão
rm -f /etc/nginx/sites-enabled/default

# Configuração do site SamurEye
cat > /etc/nginx/sites-available/samureye << 'EOF'
# SamurEye - Configuração NGINX Gateway
# Domínio: *.samureye.com.br
# Servidor: vlxsam01 (172.24.1.151)

# Redirecionamento HTTP para HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name samureye.com.br *.samureye.com.br;
    
    # Redirecionamento permanente para HTTPS
    return 301 https://$server_name$request_uri;
}

# Configuração HTTPS principal
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name app.samureye.com.br;

    # Certificados SSL
    ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;
    
    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Logs específicos
    access_log /var/log/nginx/samureye-access.log main;
    error_log /var/log/nginx/samureye-error.log;

    # Rate limiting
    limit_req zone=general burst=20 nodelay;
    limit_conn conn_limit_per_ip 20;

    # WebSocket upgrade
    location /ws {
        proxy_pass http://samureye_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }

    # API endpoints com rate limiting específico
    location /api/ {
        limit_req zone=api burst=50 nodelay;
        
        proxy_pass http://samureye_app;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Endpoints de autenticação com rate limiting restritivo
    location ~ ^/(auth|login|register) {
        limit_req zone=auth burst=10 nodelay;
        
        proxy_pass http://samureye_app;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Upload endpoints
    location ~ ^/api/(upload|files) {
        limit_req zone=upload burst=5 nodelay;
        client_max_body_size 50M;
        
        proxy_pass http://samureye_app;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts maiores para uploads
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    # Frontend (SPA)
    location / {
        proxy_pass http://samureye_app;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Cache para recursos estáticos
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            proxy_pass http://samureye_app;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            expires 1M;
            add_header Cache-Control "public, immutable";
        }
    }

    # Health check
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

# API subdomain
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.samureye.com.br;

    # Certificados SSL (mesmo wildcard)
    ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;
    
    # SSL Configuration (mesma do app)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Logs específicos da API
    access_log /var/log/nginx/api-access.log main;
    error_log /var/log/nginx/api-error.log;

    # Rate limiting para API
    limit_req zone=api burst=100 nodelay;
    limit_conn conn_limit_per_ip 50;

    # Redirecionar tudo para /api/
    location / {
        proxy_pass http://samureye_app/api$request_uri;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Ativar configuração
ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/

# Testar configuração
nginx -t

# ============================================================================
# 5. CONFIGURAÇÃO DE CERTIFICADOS SSL
# ============================================================================

log "📜 Configurando certificados SSL..."

# Criar script de solicitação de certificado
cat > /opt/request-ssl.sh << 'EOF'
#!/bin/bash

# Script para solicitar certificado SSL wildcard
# Execute após configurar DNS

echo "🔐 Solicitando certificado SSL wildcard..."

# Solicitar certificado wildcard usando DNS challenge
certbot certonly \
    --manual \
    --preferred-challenges=dns \
    --email admin@samureye.com.br \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --agree-tos \
    -d samureye.com.br \
    -d "*.samureye.com.br"

echo "✅ Certificado solicitado. Configure o NGINX e reinicie:"
echo "systemctl reload nginx"
EOF

chmod +x /opt/request-ssl.sh

# ============================================================================
# 6. SCRIPTS DE MONITORAMENTO
# ============================================================================

log "📊 Criando scripts de monitoramento..."

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
    elif [ $days_until_expiry -gt 0 ]; then
        echo "⚠️ Certificado expira em $days_until_expiry dias"
    else
        echo "❌ Certificado expirado"
    fi
else
    echo "❌ Certificado não encontrado"
fi

# Verificar conectividade com vlxsam02
echo ""
echo "🔗 CONECTIVIDADE:"
if nc -z 172.24.1.152 3000 2>/dev/null; then
    echo "✅ vlxsam02:3000 acessível"
else
    echo "❌ vlxsam02:3000 inacessível"
fi

# Testar endpoints
echo ""
echo "🧪 ENDPOINTS:"
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

mkdir -p /opt/samureye/scripts
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
            echo "❌ $domain"
        fi
    done
    
else
    echo "❌ Certificado não encontrado!"
    echo ""
    echo "💡 Para solicitar certificado:"
    echo "/opt/request-ssl.sh"
fi
EOF

chmod +x /opt/samureye/scripts/check-ssl.sh

# ============================================================================
# 7. LOGROTATE E MAINTENANCE
# ============================================================================

log "📝 Configurando logrotate..."

cat > /etc/logrotate.d/samureye-nginx << 'EOF'
/var/log/nginx/samureye-*.log {
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

/var/log/nginx/api-*.log {
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

log "🎉 Instalação do vlxsam01 concluída com sucesso!"

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