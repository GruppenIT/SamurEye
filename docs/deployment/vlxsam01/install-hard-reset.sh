#!/bin/bash

# ============================================================================
# SAMUREYE ON-PREMISE - HARD RESET GATEWAY (vlxsam01)
# ============================================================================
# Sistema completo de reset e reinstalação do Gateway SamurEye
# Inclui: NGINX + SSL + step-ca + Firewall + Monitoramento
# 
# Servidor: vlxsam01 (192.168.100.151)
# Função: Gateway/Proxy SSL para aplicação
# Dependências: vlxsam02 (App), vlxsam03 (DB), vlxsam04 (Collector)
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

# Verificar se está sendo executado como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo $0"
fi

# Configurações do ambiente
DOMAIN="samureye.com.br"
APP_DOMAIN="app.$DOMAIN"
API_DOMAIN="api.$DOMAIN"
CA_DOMAIN="ca.$DOMAIN"
BACKEND_SERVER="192.168.100.152:5000"  # vlxsam02
STEP_CA_DIR="/etc/step-ca"
CERTS_BACKUP_DIR="/etc/nginx/ssl-backup-$(date +%Y%m%d-%H%M%S)"
NGINX_CONFIG_DIR="/etc/nginx"

echo ""
echo "🔥 SAMUREYE HARD RESET - GATEWAY vlxsam01"
echo "========================================"
echo "⚠️  ATENÇÃO: Este script irá:"
echo "   • Remover COMPLETAMENTE todos os serviços"
echo "   • Fazer backup dos certificados SSL atuais"
echo "   • Reinstalar NGINX, step-ca e dependências"
echo "   • Reconfigurar firewall e SSL"
echo "   • Restaurar certificados válidos"
echo ""

# ============================================================================
# 1. CONFIRMAÇÃO E BACKUP DE CERTIFICADOS
# ============================================================================

read -p "🚨 CONTINUAR COM HARD RESET? (digite 'CONFIRMO' para continuar): " confirm
if [ "$confirm" != "CONFIRMO" ]; then
    error "Reset cancelado pelo usuário"
fi

log "💾 Criando backup de certificados SSL..."
mkdir -p "$CERTS_BACKUP_DIR"

# Backup certificados Let's Encrypt
if [ -d "/etc/letsencrypt" ]; then
    cp -r /etc/letsencrypt "$CERTS_BACKUP_DIR/"
    log "✅ Backup Let's Encrypt criado"
fi

# Backup certificados NGINX
if [ -d "/etc/nginx/ssl" ]; then
    cp -r /etc/nginx/ssl "$CERTS_BACKUP_DIR/"
    log "✅ Backup SSL NGINX criado"
fi

# Backup step-ca
if [ -d "$STEP_CA_DIR" ]; then
    cp -r "$STEP_CA_DIR" "$CERTS_BACKUP_DIR/"
    log "✅ Backup step-ca criado"
fi

# Backup configurações NGINX
if [ -d "/etc/nginx/sites-available" ]; then
    cp -r /etc/nginx/sites-available "$CERTS_BACKUP_DIR/"
    log "✅ Backup configurações NGINX criado"
fi

log "📂 Backup completo salvo em: $CERTS_BACKUP_DIR"

# ============================================================================
# 2. REMOÇÃO COMPLETA (HARD RESET)
# ============================================================================

log "🗑️ Removendo instalação anterior..."

# Parar todos os serviços
services_to_stop=("nginx" "step-ca" "fail2ban" "ufw")
for service in "${services_to_stop[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log "Parando $service..."
        systemctl stop "$service" || true
    fi
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        systemctl disable "$service" || true
    fi
done

# Remover pacotes completamente
log "Removendo pacotes antigos..."
apt-get purge -y nginx nginx-common nginx-core certbot python3-certbot-nginx \
    python3-certbot-dns-cloudflare step-cli step-certificates fail2ban 2>/dev/null || true

# Limpar configurações residuais
apt-get autoremove -y
apt-get autoclean

# Remover diretórios de configuração (exceto backups)
directories_to_clean=(
    "/etc/nginx"
    "/var/www"
    "/var/log/nginx"
    "/etc/fail2ban"
    "/etc/letsencrypt"
    "/usr/local/bin/step"
    "/usr/local/bin/step-ca"
)

for dir in "${directories_to_clean[@]}"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        log "✅ Removido: $dir"
    fi
done

# Limpar usuários de sistema
users_to_remove=("step" "nginx")
for user in "${users_to_remove[@]}"; do
    if id "$user" &>/dev/null; then
        userdel -r "$user" 2>/dev/null || true
        log "✅ Usuário $user removido"
    fi
done

log "✅ Limpeza completa finalizada"

# ============================================================================
# 3. ATUALIZAÇÃO DO SISTEMA
# ============================================================================

log "🔄 Atualizando sistema..."
apt-get update && apt-get upgrade -y

# Configurar timezone
timedatectl set-timezone America/Sao_Paulo

# ============================================================================
# 4. INSTALAÇÃO DE DEPENDÊNCIAS
# ============================================================================

log "📦 Instalando dependências..."
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
    fail2ban \
    openssl \
    net-tools \
    systemd-resolved \
    dnsutils \
    ca-certificates

# ============================================================================
# 5. INSTALAÇÃO E CONFIGURAÇÃO STEP-CA
# ============================================================================

log "🔐 Instalando step-ca Certificate Authority..."

# Instalar step CLI e step-ca
cd /tmp
wget -q https://dl.step.sm/gh-release/cli/docs-cli-install/v0.26.1/step-cli_0.26.1_amd64.deb
wget -q https://dl.step.sm/gh-release/certificates/docs-ca-install/v0.26.1/step-certificates_0.26.1_amd64.deb

dpkg -i step-cli_0.26.1_amd64.deb step-certificates_0.26.1_amd64.deb
apt-get install -f -y

# Criar usuário step
useradd -r -s /bin/false -d "$STEP_CA_DIR" step

# Configurar step-ca
mkdir -p "$STEP_CA_DIR"
chown step:step "$STEP_CA_DIR"

# Restaurar step-ca do backup se existir
if [ -d "$CERTS_BACKUP_DIR/step-ca" ]; then
    log "🔄 Restaurando configuração step-ca do backup..."
    cp -r "$CERTS_BACKUP_DIR/step-ca/"* "$STEP_CA_DIR/"
    chown -R step:step "$STEP_CA_DIR"
    log "✅ Step-ca restaurado do backup"
else
    # Inicializar novo step-ca
    log "🆕 Inicializando novo step-ca..."
    sudo -u step step ca init --name="SamurEye CA" \
        --dns="$CA_DOMAIN" \
        --address=":443" \
        --provisioner="admin" \
        --password-file=<(echo "samureye-ca-2024")
fi

# Criar serviço systemd para step-ca
cat > /etc/systemd/system/step-ca.service << 'EOF'
[Unit]
Description=Step-ca Certificate Authority
After=network.target

[Service]
Type=simple
User=step
Group=step
Environment=STEPPATH=/etc/step-ca
WorkingDirectory=/etc/step-ca
ExecStart=/usr/bin/step-ca config/ca.json --password-file config/password.txt
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Criar arquivo de password para step-ca
echo "samureye-ca-2024" > "$STEP_CA_DIR/config/password.txt"
chown step:step "$STEP_CA_DIR/config/password.txt"
chmod 600 "$STEP_CA_DIR/config/password.txt"

systemctl daemon-reload
systemctl enable step-ca
systemctl start step-ca

# ============================================================================
# 6. CONFIGURAÇÃO NGINX
# ============================================================================

log "🌐 Configurando NGINX..."

# Detectar certificados válidos
SSL_CERT_PATH=""
SSL_KEY_PATH=""
USE_LETSENCRYPT=false

# Verificar Let's Encrypt restaurado
if [ -f "$CERTS_BACKUP_DIR/letsencrypt/live/$DOMAIN/fullchain.pem" ] && \
   [ -f "$CERTS_BACKUP_DIR/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    log "🔍 Certificados Let's Encrypt encontrados no backup"
    
    # Restaurar Let's Encrypt
    cp -r "$CERTS_BACKUP_DIR/letsencrypt" /etc/
    
    # Verificar se certificados ainda são válidos
    if openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -checkend 86400 -noout; then
        log "✅ Certificados Let's Encrypt válidos - usando"
        SSL_CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        SSL_KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
        USE_LETSENCRYPT=true
    else
        warn "⚠️ Certificados Let's Encrypt expirados - usando configuração básica"
    fi
fi

# Configuração NGINX principal
cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
    
    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=app:10m rate=5r/s;
    
    # Virtual Host Configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

# Criar diretório sites-available e sites-enabled
mkdir -p /etc/nginx/{sites-available,sites-enabled,conf.d}

# Configuração SamurEye principal
if [ "$USE_LETSENCRYPT" = true ]; then
    # Configuração com SSL válido
    cat > /etc/nginx/sites-available/samureye << EOF
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name $APP_DOMAIN $API_DOMAIN $CA_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

# App Frontend (app.samureye.com.br)
server {
    listen 443 ssl http2;
    server_name $APP_DOMAIN;
    
    ssl_certificate $SSL_CERT_PATH;
    ssl_private_key $SSL_KEY_PATH;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Rate limiting
    limit_req zone=app burst=20 nodelay;
    
    location / {
        proxy_pass http://$BACKEND_SERVER;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# API Backend (api.samureye.com.br)
server {
    listen 443 ssl http2;
    server_name $API_DOMAIN;
    
    ssl_certificate $SSL_CERT_PATH;
    ssl_private_key $SSL_KEY_PATH;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    
    # Rate limiting for API
    limit_req zone=api burst=50 nodelay;
    
    location / {
        proxy_pass http://$BACKEND_SERVER;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# Step-CA (ca.samureye.com.br)
server {
    listen 443 ssl http2;
    server_name $CA_DOMAIN;
    
    ssl_certificate $SSL_CERT_PATH;
    ssl_private_key $SSL_KEY_PATH;
    
    location / {
        proxy_pass https://127.0.0.1:8443;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # SSL settings for internal proxy
        proxy_ssl_verify off;
    }
}
EOF
else
    # Configuração básica sem SSL (para teste)
    cat > /etc/nginx/sites-available/samureye << EOF
# Basic HTTP configuration (no SSL)
server {
    listen 80;
    server_name $APP_DOMAIN $API_DOMAIN $CA_DOMAIN;
    
    location / {
        proxy_pass http://$BACKEND_SERVER;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
fi

# Ativar site
ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# ============================================================================
# 7. CONFIGURAÇÃO DE FIREWALL
# ============================================================================

log "🔒 Configurando firewall..."

# Reset UFW
ufw --force reset

# Política padrão
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH
ufw allow 22/tcp

# Permitir HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Permitir step-ca
ufw allow 8443/tcp

# Permitir rede interna SamurEye
ufw allow from 192.168.100.0/24 to any port 22
ufw allow from 192.168.100.0/24 to any port 80
ufw allow from 192.168.100.0/24 to any port 443

# Ativar firewall
ufw --force enable

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
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF

# ============================================================================
# 9. INICIALIZAÇÃO DE SERVIÇOS
# ============================================================================

log "🚀 Iniciando serviços..."

# Testar configuração NGINX
nginx -t

# Iniciar serviços
services_to_start=("nginx" "fail2ban" "ufw")
for service in "${services_to_start[@]}"; do
    systemctl enable "$service"
    systemctl start "$service"
    
    if systemctl is-active --quiet "$service"; then
        log "✅ $service iniciado com sucesso"
    else
        error "❌ Falha ao iniciar $service"
    fi
done

# ============================================================================
# 10. TESTES DE VALIDAÇÃO
# ============================================================================

log "🧪 Executando testes de validação..."

# Teste 1: NGINX
if systemctl is-active --quiet nginx; then
    log "✅ NGINX: Rodando"
else
    error "❌ NGINX: Falhou"
fi

# Teste 2: step-ca
if systemctl is-active --quiet step-ca; then
    log "✅ step-ca: Rodando"
else
    warn "⚠️ step-ca: Não ativo"
fi

# Teste 3: Conectividade com backend
if curl -s -o /dev/null -w "%{http_code}" "http://$BACKEND_SERVER" | grep -q "200\|301\|302"; then
    log "✅ Backend vlxsam02: Acessível"
else
    warn "⚠️ Backend vlxsam02: Não acessível"
fi

# Teste 4: Resolução DNS
if nslookup "$APP_DOMAIN" >/dev/null 2>&1; then
    log "✅ DNS: Resolvendo $APP_DOMAIN"
else
    warn "⚠️ DNS: Problemas com resolução"
fi

# Teste 5: Portas abertas
open_ports=$(netstat -tlnp | grep -E ':80|:443|:8443' | wc -l)
if [ "$open_ports" -ge 2 ]; then
    log "✅ Portas: $open_ports portas abertas"
else
    warn "⚠️ Portas: Apenas $open_ports portas abertas"
fi

# ============================================================================
# 11. INFORMAÇÕES FINAIS
# ============================================================================

echo ""
log "🎉 HARD RESET DO GATEWAY CONCLUÍDO!"
echo ""
echo "📋 RESUMO DA CONFIGURAÇÃO:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 URLs Configuradas:"
echo "   • App:     https://$APP_DOMAIN"
echo "   • API:     https://$API_DOMAIN"
echo "   • CA:      https://$CA_DOMAIN"
echo ""
echo "🔐 Certificados SSL:"
if [ "$USE_LETSENCRYPT" = true ]; then
    echo "   • Status:  Certificados Let's Encrypt restaurados"
    echo "   • Válido:  $(openssl x509 -in "$SSL_CERT_PATH" -enddate -noout | cut -d= -f2)"
else
    echo "   • Status:  Configuração HTTP (sem SSL)"
    echo "   • Ação:    Configure certificados SSL manualmente"
fi
echo ""
echo "📂 Backup:"
echo "   • Local:   $CERTS_BACKUP_DIR"
echo "   • Conteúdo: Certificados + Configurações"
echo ""
echo "🔧 Próximos Passos:"
echo "   1. Verificar conectividade: curl -I http://$APP_DOMAIN"
echo "   2. Testar backend: curl -I http://$BACKEND_SERVER"
if [ "$USE_LETSENCRYPT" != true ]; then
    echo "   3. Configurar SSL: certbot --nginx -d $DOMAIN -d *.$DOMAIN"
fi
echo "   4. Monitorar logs: tail -f /var/log/nginx/access.log"
echo ""
echo "🚨 IMPORTANTE:"
echo "   • Certificados salvos em: $CERTS_BACKUP_DIR"
echo "   • Firewall configurado para rede 192.168.100.0/24"
echo "   • Fail2ban ativo para proteção contra ataques"
echo ""

exit 0