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
# 0. LIMPEZA COMPLETA (RESET)
# ============================================================================

log "🧹 Executando limpeza completa do sistema..."

# Parar serviços antes da limpeza
if systemctl is-active --quiet nginx; then
    log "Parando NGINX..."
    systemctl stop nginx
fi

if systemctl is-active --quiet step-ca; then
    log "Parando step-ca..."
    systemctl stop step-ca
fi

# Remover todas as configurações NGINX existentes
log "Removendo configurações NGINX antigas..."
rm -rf /etc/nginx/sites-enabled/*
rm -rf /etc/nginx/sites-available/samureye*
rm -rf /etc/nginx/conf.d/upstream.conf

# Backup da configuração nginx principal se existir
if [ -f /etc/nginx/nginx.conf ]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d-%H%M%S)
fi

# Remover certificados Let's Encrypt antigos se existirem
if [ -d "/etc/letsencrypt/live" ]; then
    log "Removendo certificados SSL antigos..."
    rm -rf /etc/letsencrypt/live/*
    rm -rf /etc/letsencrypt/archive/*
    rm -rf /etc/letsencrypt/renewal/*
fi

# Remover step-ca antigo se existir
if [ -d "/etc/step-ca" ]; then
    log "Removendo step-ca anterior..."
    rm -rf /etc/step-ca/*
fi

# Remover arquivos temporários de step-ca antigos
log "Limpando arquivos temporários..."
rm -f /tmp/step-ca-init.sh
rm -f /tmp/step-ca-init-fixed.sh
rm -f /tmp/step-ca.tar.gz
rm -f /tmp/step-cli.tar.gz

# Remover usuário step-ca antigo
if id "step-ca" &>/dev/null; then
    userdel step-ca 2>/dev/null || true
fi

# Remover serviços systemd antigos
if [ -f "/etc/systemd/system/step-ca.service" ]; then
    systemctl disable step-ca 2>/dev/null || true
    rm -f /etc/systemd/system/step-ca.service
fi

systemctl daemon-reload

log "✅ Limpeza completa finalizada"

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
    fail2ban \
    openssl

# ============================================================================
# 1.5. INSTALAÇÃO STEP-CA
# ============================================================================

log "🔐 Instalando step-ca Certificate Authority..."

# Instalar step CLI e step-ca
STEP_VERSION="0.25.2"
STEP_CA_VERSION="0.25.2"

# Download e instalação do step CLI
log "Baixando step CLI v$STEP_VERSION..."
wget -q -O /tmp/step-cli.tar.gz "https://github.com/smallstep/cli/releases/download/v$STEP_VERSION/step_linux_${STEP_VERSION}_amd64.tar.gz"
tar -xzf /tmp/step-cli.tar.gz -C /tmp/
mv "/tmp/step_$STEP_VERSION/bin/step" /usr/local/bin/step
chmod +x /usr/local/bin/step

# Download e instalação do step-ca
log "Baixando step-ca v$STEP_CA_VERSION..."
STEP_CA_URL="https://github.com/smallstep/certificates/releases/download/v$STEP_CA_VERSION/step-ca_linux_${STEP_CA_VERSION}_amd64.tar.gz"
log "URL: $STEP_CA_URL"

wget -q -O /tmp/step-ca.tar.gz "$STEP_CA_URL"
tar -xzf /tmp/step-ca.tar.gz -C /tmp/

# Verificar o que foi realmente extraído
log "Conteúdo extraído em /tmp:"
ls -la /tmp/step-ca* || true

# Buscar step-ca nos locais possíveis
STEP_CA_BINARY=""
if [ -f "/tmp/step-ca_linux_${STEP_CA_VERSION}_amd64/step-ca" ]; then
    STEP_CA_BINARY="/tmp/step-ca_linux_${STEP_CA_VERSION}_amd64/step-ca"
    log "✅ step-ca encontrado em: $STEP_CA_BINARY"
elif [ -f "/tmp/step-ca" ]; then
    STEP_CA_BINARY="/tmp/step-ca"
    log "✅ step-ca encontrado em: $STEP_CA_BINARY"
else
    # Procurar em qualquer arquivo step-ca* extraído
    STEP_CA_BINARY=$(find /tmp -name "step-ca" -type f -executable 2>/dev/null | head -1)
    if [ -n "$STEP_CA_BINARY" ]; then
        log "✅ step-ca encontrado em: $STEP_CA_BINARY"
    else
        error "❌ step-ca não encontrado em nenhum local conhecido"
        exit 1
    fi
fi

# Mover binário para localização final
mv "$STEP_CA_BINARY" /usr/local/bin/step-ca
chmod +x /usr/local/bin/step-ca
log "step-ca instalado em /usr/local/bin/step-ca"

# Criar usuário step-ca
useradd --system --home /etc/step-ca --shell /bin/false step-ca || true

# Verificar instalação
log "Verificando instalação do step e step-ca..."
if step version > /dev/null 2>&1; then
    log "✅ step CLI instalado corretamente: $(step version | head -1)"
else
    error "❌ Falha na instalação do step CLI"
    exit 1
fi

if step-ca version > /dev/null 2>&1; then
    log "✅ step-ca instalado corretamente: $(step-ca version | head -1)"
else
    error "❌ Falha na instalação do step-ca"
    exit 1
fi

log "step-ca Certificate Authority CLI instalado com sucesso"

# Configurar step-ca
log "Configurando step-ca Certificate Authority..."

# Diretório de configuração
STEP_CA_DIR="/etc/step-ca"
mkdir -p "$STEP_CA_DIR"/{certs,secrets,config}
chown -R step-ca:step-ca "$STEP_CA_DIR"
chmod -R 755 "$STEP_CA_DIR"

log "Diretório $STEP_CA_DIR configurado com permissões corretas"

# Definir variáveis para inicialização
CA_NAME="SamurEye Internal CA"
DNS_NAME="ca.samureye.com.br"
ADDRESS=":9000"
PASSWORD="samureye-ca-$(openssl rand -hex 16)"

log "Inicializando Certificate Authority..."

# Criar arquivo de senha
echo "$PASSWORD" > "$STEP_CA_DIR/password.txt"
chown step-ca:step-ca "$STEP_CA_DIR/password.txt"
chmod 600 "$STEP_CA_DIR/password.txt"

# Mudar para o diretório step-ca
cd "$STEP_CA_DIR"

# Criar certificados e configuração manualmente para evitar problemas interativos
log "Criando certificados e configuração step-ca manualmente..."

# Criar estrutura de diretórios
mkdir -p "$STEP_CA_DIR"/{certs,secrets,config,db}

# Gerar chave privada root
openssl genrsa -aes256 -passout "pass:$PASSWORD" -out "$STEP_CA_DIR/secrets/root_ca_key" 4096
chmod 600 "$STEP_CA_DIR/secrets/root_ca_key"

# Gerar certificado root auto-assinado
openssl req -new -x509 -key "$STEP_CA_DIR/secrets/root_ca_key" -passin "pass:$PASSWORD" \
    -out "$STEP_CA_DIR/certs/root_ca.crt" -days 3650 \
    -subj "/C=BR/ST=SP/L=Sao Paulo/O=SamurEye/OU=Certificate Authority/CN=SamurEye Internal CA"
chmod 644 "$STEP_CA_DIR/certs/root_ca.crt"

# Gerar chave privada intermediate
openssl genrsa -aes256 -passout "pass:$PASSWORD" -out "$STEP_CA_DIR/secrets/intermediate_ca_key" 4096
chmod 600 "$STEP_CA_DIR/secrets/intermediate_ca_key"

# Gerar CSR intermediate
openssl req -new -key "$STEP_CA_DIR/secrets/intermediate_ca_key" -passin "pass:$PASSWORD" \
    -out "$STEP_CA_DIR/intermediate_ca.csr" \
    -subj "/C=BR/ST=SP/L=Sao Paulo/O=SamurEye/OU=Certificate Authority/CN=SamurEye Internal Intermediate CA"

# Assinar certificado intermediate com root
openssl x509 -req -in "$STEP_CA_DIR/intermediate_ca.csr" \
    -CA "$STEP_CA_DIR/certs/root_ca.crt" -CAkey "$STEP_CA_DIR/secrets/root_ca_key" \
    -passin "pass:$PASSWORD" -CAcreateserial \
    -out "$STEP_CA_DIR/certs/intermediate_ca.crt" -days 1825 \
    -extensions v3_intermediate_ca \
    -extfile <(cat << 'EXT'
[v3_intermediate_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EXT
)

# Limpar CSR temporário
rm "$STEP_CA_DIR/intermediate_ca.csr"

# Gerar chave provisioner EC P-256
openssl ecparam -genkey -name prime256v1 -noout -out "$STEP_CA_DIR/secrets/provisioner_key.pem"

# Converter chave para formato JWK e extrair componentes
PROVISIONER_JWK=$(openssl pkey -in "$STEP_CA_DIR/secrets/provisioner_key.pem" -pubout -outform DER | base64 -w 0)

# Criar configuração step-ca com configuração mínima válida
cat > "$STEP_CA_DIR/config/ca.json" << JSON_CONFIG
{
  "root": "/etc/step-ca/certs/root_ca.crt",
  "federatedRoots": null,
  "crt": "/etc/step-ca/certs/intermediate_ca.crt",
  "key": "/etc/step-ca/secrets/intermediate_ca_key",
  "address": ":9000",
  "insecureAddress": "",
  "dnsNames": ["ca.samureye.com.br"],
  "logger": {"format": "text"},
  "db": {
    "type": "badgerv2",
    "dataSource": "/etc/step-ca/db",
    "badgerFileLoadingMode": ""
  },
  "authority": {
    "provisioners": [
      {
        "type": "ACME",
        "name": "acme"
      }
    ]
  },
  "tls": {
    "cipherSuites": [
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
    ],
    "minVersion": 1.2,
    "maxVersion": 1.3,
    "renegotiation": false
  }
}
JSON_CONFIG

# Ajustar permissões da chave provisioner
chmod 600 "$STEP_CA_DIR/secrets/provisioner_key.pem"

# Gerar fingerprint do certificado root
FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -in "$STEP_CA_DIR/certs/root_ca.crt" | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
echo "$FINGERPRINT" > "$STEP_CA_DIR/fingerprint.txt"

# Configurar permissões finais
chown -R step-ca:step-ca "$STEP_CA_DIR"
chmod -R 700 "$STEP_CA_DIR"
chmod 644 "$STEP_CA_DIR"/certs/*.crt
chmod 644 "$STEP_CA_DIR/fingerprint.txt"

log "Certificados e configuração step-ca criados com sucesso"
log "CA Fingerprint: $FINGERPRINT"

log "step-ca inicializado com sucesso"
log "CA Name: $CA_NAME"
log "DNS: $DNS_NAME"
log "Address: $ADDRESS"
log "Password saved to: $STEP_CA_DIR/password.txt"
log "CA Fingerprint: $FINGERPRINT"

log "step-ca inicializado e configurado com sucesso"

# Verificar configuração antes de iniciar serviço
log "Verificando configuração step-ca..."

# Testar se a configuração está válida
if sudo -u step-ca step-ca version > /dev/null 2>&1; then
    log "✅ step-ca binary funcional"
else
    error "❌ step-ca binary não está funcionando"
fi

# Verificar se o arquivo de configuração existe e é válido
if [ -f "$STEP_CA_DIR/config/ca.json" ]; then
    log "✅ Arquivo de configuração encontrado"
    # Validar JSON
    if jq empty "$STEP_CA_DIR/config/ca.json" 2>/dev/null; then
        log "✅ Configuração JSON válida"
    else
        error "❌ Configuração JSON inválida"
    fi
else
    error "❌ Arquivo de configuração não encontrado"
fi

# Atualizar configuração do serviço systemd
log "Atualizando configuração do serviço systemd..."

# Recriar serviço com configuração corrigida
cat > /etc/systemd/system/step-ca.service << 'EOF'
[Unit]
Description=Step-CA Certificate Authority
Documentation=https://smallstep.com/docs/step-ca
After=network.target
Wants=network.target

[Service]
Type=simple
User=step-ca
Group=step-ca
Environment=STEPPATH=/etc/step-ca
WorkingDirectory=/etc/step-ca
ExecStart=/usr/local/bin/step-ca config/ca.json --password-file=password.txt
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=30
StartLimitBurst=3

# Security settings
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/etc/step-ca
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Recarregar daemon e habilitar serviço
systemctl daemon-reload
systemctl enable step-ca

# Testar inicialização manual primeiro
log "Testando step-ca manualmente..."
sudo -u step-ca bash -c "cd /etc/step-ca && timeout 5 /usr/local/bin/step-ca config/ca.json --password-file=password.txt" &
MANUAL_PID=$!
sleep 2

# Verificar se o processo manual funcionou
if kill -0 $MANUAL_PID 2>/dev/null; then
    log "✅ step-ca funciona manualmente"
    kill $MANUAL_PID 2>/dev/null || true
    wait $MANUAL_PID 2>/dev/null || true
    
    # Agora tentar iniciar o serviço
    log "Iniciando serviço step-ca..."
    systemctl start step-ca
    
    # Aguardar inicialização
    sleep 3
    
    # Verificar status
    if systemctl is-active step-ca >/dev/null 2>&1; then
        log "✅ step-ca service iniciado com sucesso"
        
        # Mostrar informações
        FINGERPRINT=$(cat /etc/step-ca/fingerprint.txt 2>/dev/null || echo "N/A")
        log "CA Fingerprint: $FINGERPRINT"
        log "CA URL: https://ca.samureye.com.br"
        log "CA Config: /etc/step-ca/config/ca.json"
        log "CA Password: /etc/step-ca/password.txt"
    else
        warn "❌ Falha ao iniciar step-ca service"
        log "Status do serviço:"
        systemctl status step-ca --no-pager || true
        log "Logs do serviço:"
        journalctl -u step-ca --no-pager -n 20 || true
    fi
else
    error "❌ step-ca não funciona manualmente - verificar configuração"
fi

rm -f /tmp/step-*
log "step-ca Certificate Authority configurado"

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

    # Rate limiting zones (definidas aqui globalmente)
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=app:10m rate=30r/s;
    limit_req_zone $binary_remote_addr zone=auth:10m rate=20r/m;
    limit_req_zone $binary_remote_addr zone=upload:10m rate=10r/m;
    limit_req_zone $binary_remote_addr zone=admin:10m rate=30r/m;
    limit_req_zone $binary_remote_addr zone=admin_login:10m rate=10r/m;
    limit_req_zone $binary_remote_addr zone=dashboard:10m rate=200r/m;
    limit_req_zone $binary_remote_addr zone=object_storage:10m rate=500r/m;
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
# Upstream para aplicação SamurEye em vlxsam02 (React 18 + Vite dev server)
upstream samureye_app {
    server 172.24.1.152:5000 max_fails=3 fail_timeout=30s;
    # Adicionar mais servidores aqui para load balancing
    # server 172.24.1.152:5001 backup;
    
    keepalive 16;
}

# Upstream para WebSocket
upstream samureye_ws {
    server 172.24.1.152:5000;
    keepalive 16;
}
EOF

# Remover configuração padrão e qualquer link órfão
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/samureye* 2>/dev/null || true

# Configuração temporária do site SamurEye (sem SSL)
cat > /etc/nginx/sites-available/samureye-temp << 'EOF'
# SamurEye - Configuração NGINX Gateway (Temporária - sem SSL)
# Domínio: *.samureye.com.br
# Servidor: vlxsam01 (172.24.1.151)

# Servidor HTTP temporário para validação Let's Encrypt
server {
    listen 80;
    listen [::]:80;
    server_name samureye.com.br *.samureye.com.br app.samureye.com.br;
    
    # Permitir validação Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }
    
    # Proxy para aplicação durante configuração
    location / {
        proxy_pass http://samureye_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Rate limiting básico
        limit_req zone=general burst=20 nodelay;
    }
}
EOF

# Configuração HTTPS final (será aplicada após obter certificados)
cat > /etc/nginx/sites-available/samureye << 'EOF'
# SamurEye - Configuração NGINX Gateway (RESET COMPLETO - 28/08/2025)
# Domínio: *.samureye.com.br
# Servidor: vlxsam01 (172.24.1.151)
# CORREÇÃO: Removidas definições duplicadas de limit_req_zone

# Upstream backend (rate limiting zones já definidas no nginx.conf)
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
    
    # step-ca Certificate Authority endpoints
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        
        # Timeouts para step-ca
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# PRIMEIRO: Ativar configuração temporária SEM SSL
log "Ativando configuração temporária (sem SSL)..."
ln -sf /etc/nginx/sites-available/samureye-temp /etc/nginx/sites-enabled/samureye

# Garantir que NGINX está habilitado no boot
systemctl enable nginx >/dev/null 2>&1 || true

# Criar diretório para validação Let's Encrypt
mkdir -p /var/www/html/.well-known/acme-challenge
chown -R www-data:www-data /var/www/html

# Testar configuração temporária
if nginx -t; then
    log "✅ Configuração NGINX temporária válida"
else
    error "❌ Erro na configuração NGINX temporária"
fi

# Verificar se NGINX está rodando e iniciar/recarregar conforme necessário
NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
log "Status atual do NGINX: $NGINX_STATUS"

if [ "$NGINX_STATUS" = "active" ]; then
    log "NGINX está rodando, recarregando configuração..."
    if systemctl reload nginx; then
        log "✅ NGINX recarregado com sucesso"
    else
        warn "Falha no reload, tentando restart..."
        systemctl restart nginx
        if systemctl is-active nginx >/dev/null 2>&1; then
            log "✅ NGINX reiniciado com sucesso"
        else
            error "❌ Falha ao reiniciar NGINX"
        fi
    fi
else
    log "NGINX não está rodando ($NGINX_STATUS), iniciando serviço..."
    
    # Habilitar o serviço primeiro
    systemctl enable nginx
    
    # Tentar iniciar
    if systemctl start nginx; then
        sleep 2
        if systemctl is-active nginx >/dev/null 2>&1; then
            log "✅ NGINX iniciado com sucesso"
        else
            log "NGINX não respondeu, verificando status..."
            systemctl status nginx --no-pager
        fi
    else
        error "❌ Falha ao iniciar NGINX - verificando logs"
        journalctl -u nginx --no-pager -n 10
    fi
fi

log "NGINX configurado temporariamente (HTTP apenas)"

# ============================================================================
# 5. CONFIGURAÇÃO DE CERTIFICADOS SSL
# ============================================================================

log "📜 Configurando certificados SSL..."

# Criar script principal para certificado wildcard (DNS challenge)
cat > /opt/request-ssl.sh << 'EOF'
#!/bin/bash

# Script para solicitar certificado SSL wildcard para SamurEye
# Usa DNS-01 challenge (certificado wildcard *.samureye.com.br)

set -e

echo "🔐 Solicitando certificado SSL WILDCARD com DNS-01 challenge..."
echo ""
echo "IMPORTANTE: Você precisará adicionar registros TXT no DNS!"
echo "=================================================="

# Solicitar certificado wildcard usando DNS challenge manual
certbot certonly \
    --manual \
    --preferred-challenges=dns \
    --email admin@samureye.com.br \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --agree-tos \
    --no-eff-email \
    --manual-public-ip-logging-ok \
    -d samureye.com.br \
    -d "*.samureye.com.br"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Certificado wildcard obtido com sucesso!"
    
    # Remover configuração temporária
    rm -f /etc/nginx/sites-enabled/samureye-temp
    
    # Ativar configuração final com SSL
    ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/samureye
    
    # Testar configuração final
    if nginx -t; then
        # Recarregar NGINX
        systemctl reload nginx
        echo "🚀 SSL wildcard configurado com sucesso!"
        echo ""
        echo "URLs funcionais:"
        echo "  https://samureye.com.br"
        echo "  https://app.samureye.com.br"
        echo "  https://api.samureye.com.br"
        echo "  https://qualquer.samureye.com.br"
    else
        echo "❌ Erro na configuração NGINX"
        exit 1
    fi
else
    echo "❌ Falha ao obter certificado wildcard"
    echo "Verifique se os registros DNS TXT foram adicionados corretamente"
    exit 1
fi
EOF

chmod +x /opt/request-ssl.sh

# Criar script HTTP fallback (para casos específicos)
cat > /opt/request-ssl-http.sh << 'EOF'
#!/bin/bash

# Script FALLBACK para certificado SSL com HTTP-01 challenge
# Use apenas se DNS challenge não for possível

set -e

echo "🔐 Solicitando certificado SSL com HTTP-01 challenge (fallback)..."
echo ""
echo "AVISO: Este método requer que os domínios apontem para este servidor!"
echo "================================================================="

# Verificar se os domínios apontam para este servidor
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "IP do servidor: $SERVER_IP"
echo ""

for domain in "samureye.com.br" "app.samureye.com.br" "api.samureye.com.br"; do
    DOMAIN_IP=$(dig +short $domain | tail -1)
    if [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
        echo "✅ $domain aponta para $SERVER_IP"
    else
        echo "❌ $domain aponta para $DOMAIN_IP (deveria ser $SERVER_IP)"
    fi
done

echo ""
read -p "Continuar com HTTP challenge? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelado. Use /opt/request-ssl.sh para DNS challenge"
    exit 1
fi

# Solicitar certificado usando HTTP-01
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

if [ $? -eq 0 ]; then
    echo "✅ Certificado HTTP obtido. Ativando configuração HTTPS..."
    
    # Remover configuração temporária
    rm -f /etc/nginx/sites-enabled/samureye-temp
    
    # Ativar configuração final com SSL
    ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/samureye
    
    # Testar configuração final
    nginx -t && systemctl reload nginx
    
    echo "🚀 SSL HTTP configurado com sucesso!"
    echo "Acesse: https://app.samureye.com.br"
else
    echo "❌ Falha ao obter certificado HTTP"
    exit 1
fi
EOF

chmod +x /opt/request-ssl-http.sh

# ============================================================================
# 6. SCRIPTS DE MONITORAMENTO
# ============================================================================

log "📊 Criando scripts de monitoramento..."

# Criar diretório de scripts se não existir
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

# Verificar status final
if systemctl is-active --quiet nginx; then
    log "✅ NGINX iniciado com sucesso"
    log "Status dos serviços:"
    log "  NGINX: $(systemctl is-active nginx)"
    log "  step-ca: $(systemctl is-active step-ca)"
else
    error "❌ Falha ao iniciar NGINX"
fi

# Teste de conectividade básica
log "🔍 Executando testes básicos..."
if curl -s --connect-timeout 5 http://127.0.0.1/ >/dev/null; then
    log "✅ Teste HTTP local: OK"
else
    warn "⚠️ Teste HTTP local: FALHOU (pode ser normal se backend não estiver rodando)"
fi

# Verificar portas abertas
if ss -tlnp | grep ":80" >/dev/null; then
    log "✅ Porta 80 (HTTP): Aberta"
else
    warn "⚠️ Porta 80 (HTTP): Não encontrada"
fi

if ss -tlnp | grep ":443" >/dev/null; then
    log "✅ Porta 443 (HTTPS): Preparada"
else
    warn "⚠️ Porta 443 (HTTPS): Não encontrada"
fi

if ss -tlnp | grep ":9000" >/dev/null; then
    log "✅ Porta 9000 (step-ca): Aberta"
else
    warn "⚠️ Porta 9000 (step-ca): Não encontrada"
fi

log "🎉 Instalação do vlxsam01 concluída com sucesso!"

echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "========================"
echo ""
echo "✅ Sistema preparado e atualizado"
echo "✅ step-ca Certificate Authority configurado"
echo "✅ Firewall UFW configurado (SSH, HTTP, HTTPS)"
echo "✅ NGINX configurado com proxy reverso"
echo "✅ Rate limiting e security headers aplicados"
echo "✅ Scripts SSL preparados"
echo "✅ Cron jobs configurados"
echo "✅ Fail2Ban ativo"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "=================="
echo ""

# Mostrar fingerprint da CA step-ca
if [[ -f /etc/step-ca/fingerprint.txt ]]; then
    CA_FINGERPRINT=$(cat /etc/step-ca/fingerprint.txt)
    echo "🔐 STEP-CA CERTIFICATE AUTHORITY:"
    echo "   Status: $(systemctl is-active step-ca)"
    echo "   URL: https://ca.samureye.com.br"
    echo "   Fingerprint: $CA_FINGERPRINT"
    echo ""
    echo "   Para usar no vlxsam04 collector:"
    echo "   STEP_CA_FINGERPRINT=$CA_FINGERPRINT"
    echo ""
fi

echo "1. Solicitar certificado SSL WILDCARD (recomendado):"
echo "   /opt/request-ssl.sh"
echo "   ↳ Seguir instruções para adicionar registros TXT no DNS"
echo ""
echo "2. Alternativa - Certificado HTTP (se DNS não for possível):"
echo "   /opt/request-ssl-http.sh"
echo "   ↳ Requer DNS apontando para $(hostname -I | awk '{print $1}')"
echo ""
echo "3. Configurar DNS (obrigatório):"
echo "   samureye.com.br        → $(hostname -I | awk '{print $1}')"
echo "   *.samureye.com.br      → $(hostname -I | awk '{print $1}')"
echo "   ca.samureye.com.br     → $(hostname -I | awk '{print $1}')  # step-ca"
echo ""
echo "4. Testar configuração:"
echo "   /opt/samureye/scripts/health-check.sh"
echo "   /opt/samureye/scripts/check-ssl.sh"
echo "   systemctl status step-ca  # verificar CA"
echo ""
echo "5. Verificar logs:"
echo "   tail -f /var/log/nginx/samureye-access.log"
echo "   tail -f /var/log/nginx/samureye-error.log"
echo "   journalctl -f -u step-ca  # logs da CA"
echo ""
echo "🌐 URLs que funcionarão após SSL:"
echo "   https://app.samureye.com.br   # Frontend"
echo "   https://api.samureye.com.br   # Backend API"
echo "   https://ca.samureye.com.br    # Certificate Authority"
echo "   https://qualquer.samureye.com.br (wildcard)"
echo ""
echo "⚠️  IMPORTANTE:"
echo "   • Wildcard DNS challenge é o método recomendado!"
echo "   • step-ca rodando na porta 9000 (proxy via NGINX 443)"
echo "   • Collectors precisam do fingerprint CA para registro mTLS"
echo "   • Este script é um RESET COMPLETO - remove configurações antigas"
echo "   • Backend vlxsam02:5000 deve estar rodando para funcionamento completo"
echo ""
echo "🔧 SOLUÇÃO DE PROBLEMAS:"
echo "======================="
echo "   • Logs NGINX: tail -f /var/log/nginx/error.log"
echo "   • Status step-ca: systemctl status step-ca"
echo "   • Testar backend: curl http://172.24.1.152:5000/api/system/settings"
echo "   • Recriar configuração: execute este script novamente"
echo "   • Verificar DNS: nslookup app.samureye.com.br"
echo ""
echo "📞 Se precisar de ajuda, este script pode ser executado novamente."
echo "    Ele faz limpeza completa e recria tudo do zero."
echo ""
echo "🎯 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"

# ============================================================================
# CONFIGURAÇÃO SSL AUTOMÁTICA (se certificado wildcard existir)
# ============================================================================

# Verificar se certificado wildcard já existe e aplicar SSL automaticamente
if [ -f "/etc/letsencrypt/live/samureye.com.br/fullchain.pem" ]; then
    log "🔧 Certificado wildcard encontrado! Aplicando configuração SSL automaticamente..."
    
    # Baixar e aplicar script de correção SSL
    if curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/fix-nginx-ssl-complete.sh | bash; then
        log "✅ Configuração SSL aplicada automaticamente"
        
        echo ""
        log "🔗 SamurEye Gateway configurado e ativo:"
        echo "  Aplicação: https://app.samureye.com.br"
        echo "  API:       https://api.samureye.com.br" 
        echo "  Portal:    https://samureye.com.br"
        echo "  CA:        https://ca.samureye.com.br"
        echo "  Health:    https://app.samureye.com.br/health"
        echo ""
        echo "✅ SamurEye Gateway (vlxsam01) TOTALMENTE CONFIGURADO COM SSL!"
    else
        warn "Falha na aplicação automática do SSL - configure manualmente"
    fi
else
    echo ""
    log "📋 Para finalizar a configuração SSL:"
    echo ""
    echo "# 1. Obter certificado wildcard SSL (DNS challenge):"
    echo "sudo certbot certonly --manual --preferred-challenges=dns -d samureye.com.br -d '*.samureye.com.br'"
    echo ""
    echo "# 2. Aplicar configuração SSL automaticamente:"
    echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/fix-nginx-ssl-complete.sh | bash"
    echo ""
    echo "🔗 URLs após configurar SSL:"
    echo "  Aplicação: https://app.samureye.com.br"
    echo "  API:       https://api.samureye.com.br"
    echo "  Portal:    https://samureye.com.br"
    echo "  CA:        https://ca.samureye.com.br"
fi