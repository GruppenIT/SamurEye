#!/bin/bash
# Script para configuração de certificados SSL/TLS para SamurEye
# Execute no servidor vlxsam01 (Gateway)

set -e

echo "🔒 Configurando certificados SSL/TLS para SamurEye..."

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Domínios da SamurEye
DOMAINS="app.samureye.com.br api.samureye.com.br scanner.samureye.com.br"
EMAIL="admin@samureye.com.br"

log "Verificando pré-requisitos..."

# Verificar se certbot está instalado
if ! command -v certbot &> /dev/null; then
    error "Certbot não está instalado. Execute primeiro o script de instalação do gateway."
fi

# Verificar se NGINX está rodando
if ! systemctl is-active --quiet nginx; then
    error "NGINX não está rodando. Verifique a instalação."
fi

# Verificar DNS dos domínios
log "Verificando configuração DNS..."
for domain in $DOMAINS; do
    if ! nslookup $domain > /dev/null 2>&1; then
        warn "DNS não configurado para $domain"
    else
        log "DNS OK para $domain"
    fi
done

# Opção 1: Certificados Let's Encrypt (Recomendado para produção)
setup_letsencrypt() {
    log "Configurando certificados Let's Encrypt..."
    
    # Parar NGINX temporariamente para modo standalone
    systemctl stop nginx
    
    # Obter certificados
    certbot certonly \
        --standalone \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        -d app.samureye.com.br \
        -d api.samureye.com.br \
        -d scanner.samureye.com.br
    
    if [ $? -eq 0 ]; then
        log "Certificados Let's Encrypt obtidos com sucesso!"
        
        # Configurar renovação automática
        cat > /etc/cron.d/certbot-renew << 'EOF'
# Renovação automática de certificados Let's Encrypt
0 12 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx"
EOF
        
        log "Renovação automática configurada"
    else
        error "Falha ao obter certificados Let's Encrypt"
    fi
    
    # Reiniciar NGINX
    systemctl start nginx
}

# Opção 2: Certificados auto-assinados (Para desenvolvimento/teste)
setup_selfsigned() {
    log "Criando certificados auto-assinados para desenvolvimento..."
    
    # Criar diretório para certificados
    mkdir -p /etc/ssl/samureye
    
    # Criar chave privada
    openssl genrsa -out /etc/ssl/samureye/samureye.key 2048
    
    # Criar arquivo de configuração para certificado
    cat > /etc/ssl/samureye/cert.conf << 'EOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=BR
ST=SP
L=São Paulo
O=SamurEye
OU=IT Department
CN=app.samureye.com.br

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = app.samureye.com.br
DNS.2 = api.samureye.com.br
DNS.3 = scanner.samureye.com.br
DNS.4 = ca.samureye.com.br
DNS.5 = localhost
IP.1 = 127.0.0.1
EOF
    
    # Criar certificado auto-assinado
    openssl req -new -x509 -key /etc/ssl/samureye/samureye.key \
        -out /etc/ssl/samureye/samureye.crt \
        -days 365 \
        -config /etc/ssl/samureye/cert.conf \
        -extensions v3_req
    
    # Definir permissões
    chmod 600 /etc/ssl/samureye/samureye.key
    chmod 644 /etc/ssl/samureye/samureye.crt
    
    log "Certificados auto-assinados criados em /etc/ssl/samureye/"
}

# Opção 3: step-ca para CA interna (Para mTLS entre collectors)
setup_step_ca() {
    log "Configurando step-ca para CA interna..."
    
    # Instalar step-ca se não estiver instalado
    if ! command -v step-ca &> /dev/null; then
        log "Instalando step-ca..."
        wget https://github.com/smallstep/certificates/releases/download/v0.24.2/step-ca_linux_0.24.2_amd64.deb
        dpkg -i step-ca_linux_0.24.2_amd64.deb
        rm step-ca_linux_0.24.2_amd64.deb
    fi
    
    # Criar usuário para step-ca
    useradd -m -s /bin/bash step || true
    
    # Configurar diretório
    mkdir -p /opt/step-ca
    chown step:step /opt/step-ca
    
    # Inicializar CA
    sudo -u step step ca init \
        --name "SamurEye Internal CA" \
        --dns ca.samureye.com.br \
        --address 0.0.0.0:8443 \
        --provisioner admin \
        --root /opt/step-ca/certs/root_ca.crt \
        --key /opt/step-ca/secrets/root_ca_key \
        --password-file /opt/step-ca/secrets/password
    
    # Criar service
    cat > /etc/systemd/system/step-ca.service << 'EOF'
[Unit]
Description=Step CA
After=network.target
Wants=network.target

[Service]
Type=simple
User=step
WorkingDirectory=/opt/step-ca
ExecStart=/usr/bin/step-ca config/ca.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable step-ca
    systemctl start step-ca
    
    log "Step CA configurado e rodando na porta 8443"
}

# Configurar NGINX para usar certificados
configure_nginx_ssl() {
    log "Configurando NGINX para usar certificados SSL..."
    
    # Fazer backup da configuração atual
    cp /etc/nginx/sites-available/samureye /etc/nginx/sites-available/samureye.bak
    
    # Atualizar configuração para usar certificados corretos
    if [ -f "/etc/letsencrypt/live/app.samureye.com.br/fullchain.pem" ]; then
        log "Usando certificados Let's Encrypt"
        # Configuração já está correta no nginx-samureye.conf
    elif [ -f "/etc/ssl/samureye/samureye.crt" ]; then
        log "Usando certificados auto-assinados"
        
        # Atualizar caminhos dos certificados na configuração
        sed -i 's|/etc/letsencrypt/live/app.samureye.com.br/fullchain.pem|/etc/ssl/samureye/samureye.crt|g' /etc/nginx/sites-available/samureye
        sed -i 's|/etc/letsencrypt/live/app.samureye.com.br/privkey.pem|/etc/ssl/samureye/samureye.key|g' /etc/nginx/sites-available/samureye
        sed -i 's|/etc/letsencrypt/live/api.samureye.com.br/fullchain.pem|/etc/ssl/samureye/samureye.crt|g' /etc/nginx/sites-available/samureye
        sed -i 's|/etc/letsencrypt/live/api.samureye.com.br/privkey.pem|/etc/ssl/samureye/samureye.key|g' /etc/nginx/sites-available/samureye
        sed -i 's|/etc/letsencrypt/live/scanner.samureye.com.br/fullchain.pem|/etc/ssl/samureye/samureye.crt|g' /etc/nginx/sites-available/samureye
        sed -i 's|/etc/letsencrypt/live/scanner.samureye.com.br/privkey.pem|/etc/ssl/samureye/samureye.key|g' /etc/nginx/sites-available/samureye
        
        # Remover includes do Let's Encrypt
        sed -i '/include \/etc\/letsencrypt\/options-ssl-nginx.conf/d' /etc/nginx/sites-available/samureye
        sed -i '/ssl_dhparam \/etc\/letsencrypt\/ssl-dhparams.pem/d' /etc/nginx/sites-available/samureye
    fi
    
    # Testar configuração
    if nginx -t; then
        log "Configuração NGINX válida"
        systemctl reload nginx
        log "NGINX recarregado com sucesso"
    else
        error "Erro na configuração do NGINX"
    fi
}

# Script de verificação de certificados
create_cert_check_script() {
    log "Criando script de verificação de certificados..."
    
    cat > /opt/check-certificates.sh << 'EOF'
#!/bin/bash

echo "=== Verificação de Certificados SamurEye ==="
echo "Data: $(date)"
echo ""

DOMAINS="app.samureye.com.br api.samureye.com.br scanner.samureye.com.br"

for domain in $DOMAINS; do
    echo "Verificando $domain:"
    
    # Verificar se o site está acessível via HTTPS
    if curl -s --connect-timeout 5 https://$domain > /dev/null; then
        echo "  ✓ HTTPS acessível"
        
        # Verificar validade do certificado
        expiry=$(echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)
        echo "  ✓ Certificado válido até: $expiry"
        
        # Verificar se expira em menos de 30 dias
        expiry_epoch=$(date -d "$expiry" +%s)
        current_epoch=$(date +%s)
        days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [ $days_until_expiry -lt 30 ]; then
            echo "  ⚠️  ATENÇÃO: Certificado expira em $days_until_expiry dias!"
        else
            echo "  ✓ Certificado válido por mais $days_until_expiry dias"
        fi
    else
        echo "  ✗ HTTPS não acessível"
    fi
    echo ""
done

# Verificar certificados Let's Encrypt
if [ -d "/etc/letsencrypt/live" ]; then
    echo "Certificados Let's Encrypt:"
    certbot certificates
fi

echo "=== Fim da Verificação ==="
EOF
    
    chmod +x /opt/check-certificates.sh
    
    # Configurar cron para verificação semanal
    (crontab -l 2>/dev/null; echo "0 8 * * 1 /opt/check-certificates.sh | mail -s 'SamurEye Certificate Check' admin@samureye.com.br") | crontab -
}

# Menu principal
echo ""
echo "🔒 Setup de Certificados SSL/TLS para SamurEye"
echo ""
echo "Escolha uma opção:"
echo "1) Let's Encrypt (Produção - Recomendado)"
echo "2) Certificados Auto-assinados (Desenvolvimento/Teste)"
echo "3) Configurar step-ca (CA Interna para mTLS)"
echo "4) Apenas configurar NGINX"
echo "5) Verificar certificados existentes"
echo ""
read -p "Digite sua escolha (1-5): " choice

case $choice in
    1)
        setup_letsencrypt
        configure_nginx_ssl
        create_cert_check_script
        ;;
    2)
        setup_selfsigned
        configure_nginx_ssl
        create_cert_check_script
        ;;
    3)
        setup_step_ca
        ;;
    4)
        configure_nginx_ssl
        ;;
    5)
        /opt/check-certificates.sh 2>/dev/null || echo "Script de verificação não encontrado"
        ;;
    *)
        error "Opção inválida"
        ;;
esac

echo ""
echo "✅ Configuração de certificados concluída!"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "• Testar acesso HTTPS: https://app.samureye.com.br"
echo "• Verificar certificados: /opt/check-certificates.sh"
echo "• Monitorar logs: tail -f /var/log/nginx/error.log"
echo ""
echo "🔗 URLs de teste:"
echo "• https://app.samureye.com.br"
echo "• https://api.samureye.com.br/health"
echo "• https://scanner.samureye.com.br/health"