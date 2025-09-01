#!/bin/bash

# vlxsam01 - Corrigir SSL e NGINX (Situação Real)
# Baseado na configuração atual do servidor

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-ssl-nginx.sh"
fi

echo "🔐 vlxsam01 - CORRIGIR SSL E NGINX (SITUAÇÃO REAL)"
echo "================================================="
echo ""

# ============================================================================
# 1. VERIFICAR SITUAÇÃO ATUAL
# ============================================================================

log "🔍 Verificando situação atual do servidor..."

# Verificar se NGINX está instalado
if ! command -v nginx >/dev/null 2>&1; then
    log "📦 Instalando NGINX..."
    apt-get update -q
    apt-get install -y nginx
fi

# Verificar onde estão os certificados SSL
SSL_LOCATIONS=(
    "/etc/letsencrypt/live/app.samureye.com.br"
    "/etc/ssl/certs/samureye"
    "/opt/ssl"
    "/etc/ssl/samureye"
    "/root/ssl"
)

SSL_PATH=""
for location in "${SSL_LOCATIONS[@]}"; do
    if [ -f "$location/fullchain.pem" ] || [ -f "$location/cert.pem" ]; then
        SSL_PATH="$location"
        log "✅ Certificados encontrados em: $SSL_PATH"
        break
    fi
done

if [ -z "$SSL_PATH" ]; then
    warn "⚠️ Certificados SSL não encontrados. Configurando para HTTP apenas"
    USE_SSL=false
else
    USE_SSL=true
    # Verificar se certificados estão válidos
    if openssl x509 -in "$SSL_PATH"/*.pem -noout -checkend 86400 >/dev/null 2>&1; then
        log "✅ Certificados válidos"
    else
        warn "⚠️ Certificados podem estar expirados"
    fi
fi

# ============================================================================
# 2. CONFIGURAR NGINX
# ============================================================================

log "⚙️ Configurando NGINX..."

# Criar diretório sites-available se não existir
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled

# Backup de configurações existentes
if [ -f "/etc/nginx/sites-available/default" ]; then
    cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup.$(date +%Y%m%d)
fi

# Remover configurações conflitantes
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/samureye.conf

if [ "$USE_SSL" = true ]; then
    # Configuração com SSL
    log "🔐 Criando configuração NGINX com SSL..."
    
    cat > /etc/nginx/sites-available/samureye.conf << EOF
# SamurEye - Configuração com SSL
server {
    listen 80;
    server_name app.samureye.com.br api.samureye.com.br *.samureye.com.br;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.samureye.com.br api.samureye.com.br *.samureye.com.br;

    # SSL Configuration
    ssl_certificate $SSL_PATH/fullchain.pem;
    ssl_certificate_key $SSL_PATH/privkey.pem;
    
    # Modern SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:50m;
    ssl_session_timeout 1d;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    
    # Logs
    access_log /var/log/nginx/samureye.access.log;
    error_log /var/log/nginx/samureye.error.log;
    
    # Client settings
    client_max_body_size 10M;
    client_body_timeout 60s;
    
    # Collector API - alta performance
    location ~ ^/collector-api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # API geral
    location ~ ^/api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # Frontend
    location / {
        proxy_pass http://192.168.100.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

else
    # Configuração apenas HTTP
    log "🌐 Criando configuração NGINX apenas HTTP..."
    
    cat > /etc/nginx/sites-available/samureye.conf << EOF
# SamurEye - Configuração HTTP apenas
server {
    listen 80;
    server_name app.samureye.com.br api.samureye.com.br *.samureye.com.br;
    
    # Logs
    access_log /var/log/nginx/samureye.access.log;
    error_log /var/log/nginx/samureye.error.log;
    
    # Client settings
    client_max_body_size 10M;
    client_body_timeout 60s;
    
    # Collector API
    location ~ ^/collector-api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # API geral
    location ~ ^/api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Frontend
    location / {
        proxy_pass http://192.168.100.152:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

fi

# Habilitar site
ln -sf /etc/nginx/sites-available/samureye.conf /etc/nginx/sites-enabled/

# ============================================================================
# 3. TESTAR E APLICAR
# ============================================================================

log "🧪 Testando configuração NGINX..."

if nginx -t; then
    log "✅ Configuração NGINX válida"
    
    systemctl enable nginx
    systemctl restart nginx
    
    if systemctl is-active --quiet nginx; then
        log "✅ NGINX rodando"
    else
        error "❌ NGINX falhou ao iniciar"
    fi
else
    error "❌ Erro na configuração NGINX"
fi

# ============================================================================
# 4. TESTE DE CONECTIVIDADE
# ============================================================================

log "🌐 Testando conectividade..."

sleep 5

# Testar proxy para vlxsam02
if curl -s -f http://192.168.100.152:5000/api/system/settings >/dev/null; then
    log "✅ vlxsam02 acessível"
else
    warn "⚠️ vlxsam02 pode não estar respondendo"
fi

# Testar proxy via NGINX
if [ "$USE_SSL" = true ]; then
    TEST_URL="https://app.samureye.com.br/api/system/settings"
else
    TEST_URL="http://app.samureye.com.br/api/system/settings"
fi

if curl -s -f "$TEST_URL" >/dev/null 2>&1; then
    log "✅ Proxy NGINX funcionando"
else
    warn "⚠️ Proxy NGINX pode ter problemas"
fi

# ============================================================================
# 5. RESULTADO
# ============================================================================

echo ""
log "🎯 NGINX CONFIGURADO COM SUCESSO"
echo "════════════════════════════════════════════════"
echo ""

if [ "$USE_SSL" = true ]; then
    echo "🔐 CONFIGURAÇÃO SSL:"
    echo "   ✓ Certificados: $SSL_PATH"
    echo "   ✓ HTTPS habilitado"
    echo "   ✓ Redirecionamento HTTP → HTTPS"
    echo ""
    echo "🌐 URLs DISPONÍVEIS:"
    echo "   • https://app.samureye.com.br"
    echo "   • https://app.samureye.com.br/api/"
    echo "   • https://app.samureye.com.br/collector-api/"
else
    echo "🌐 CONFIGURAÇÃO HTTP:"
    echo "   ✓ Sem SSL (certificados não encontrados)"
    echo "   ✓ Proxy para vlxsam02:5000"
    echo ""
    echo "🌐 URLs DISPONÍVEIS:"
    echo "   • http://app.samureye.com.br"
    echo "   • http://app.samureye.com.br/api/"
    echo "   • http://app.samureye.com.br/collector-api/"
fi

echo ""
echo "📊 MONITORAMENTO:"
echo "   • Status: systemctl status nginx"
echo "   • Logs: tail -f /var/log/nginx/samureye.access.log"
echo "   • Teste: curl -I $TEST_URL"
echo ""
echo "💡 PRÓXIMO PASSO:"
echo "   Continuar com vlxsam03 (banco de dados)"

exit 0