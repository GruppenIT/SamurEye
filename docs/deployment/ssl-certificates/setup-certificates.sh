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

# Função para verificar rate limit
check_rate_limit() {
    log "Verificando rate limits do Let's Encrypt..."
    
    # Verificar certificados existentes
    local existing_certs=$(certbot certificates 2>/dev/null | grep "samureye.com.br" | wc -l)
    
    if [ "$existing_certs" -ge 3 ]; then
        warn "Detectados $existing_certs certificados para samureye.com.br. Cuidado com rate limit."
        echo ""
        echo "Let's Encrypt permite 5 certificados por domínio por semana."
        echo "Recomendamos aguardar algumas horas se você já tentou hoje."
        echo ""
        read -p "Continuar mesmo assim? (s/N): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Ss]$ ]]; then
            error "Operação cancelada. Aguarde algumas horas e tente novamente."
        fi
    fi
    
    # Verificar logs recentes de erro
    if [ -f "/var/log/letsencrypt/letsencrypt.log" ]; then
        local recent_errors=$(grep -c "Service busy\|rate limit" /var/log/letsencrypt/letsencrypt.log 2>/dev/null || echo "0")
        if [ "$recent_errors" -gt 0 ]; then
            warn "Encontrados $recent_errors erros de rate limit no log recente."
            echo "Recomendamos aguardar 1-24 horas antes de tentar novamente."
            echo ""
            read -p "Tentar mesmo assim? (s/N): " force_attempt
            if [[ ! "$force_attempt" =~ ^[Ss]$ ]]; then
                error "Operação cancelada devido ao rate limiting."
            fi
        fi
    fi
}

# Função para aguardar propagação DNS
wait_dns_propagation() {
    local challenge_domain="$1"
    local expected_value="$2"
    local max_attempts=30
    local attempt=1
    
    echo ""
    echo "🔄 Aguardando propagação DNS..."
    echo "Verificando: $challenge_domain"
    echo "Valor esperado: $expected_value"
    echo ""
    
    while [ $attempt -le $max_attempts ]; do
        echo -n "Tentativa $attempt/$max_attempts: "
        
        local dns_result=$(dig +short TXT "$challenge_domain" @8.8.8.8 2>/dev/null | tr -d '"' | head -1)
        
        if [ "$dns_result" = "$expected_value" ]; then
            echo "✅ DNS propagado com sucesso!"
            return 0
        else
            echo "❌ Ainda propagando... (encontrado: '$dns_result')"
            sleep 10
        fi
        
        ((attempt++))
    done
    
    warn "DNS pode não estar totalmente propagado após ${max_attempts} tentativas"
    echo "Valor encontrado: '$dns_result'"
    echo "Valor esperado: '$expected_value'"
    echo ""
    read -p "Continuar mesmo assim? (s/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Ss]$ ]]; then
        return 1
    fi
    return 0
}

# Opção 1: Certificados Let's Encrypt via DNS-01 Challenge (Recomendado para produção)
setup_letsencrypt() {
    log "Configurando certificados Let's Encrypt via DNS Challenge..."
    
    # Verificar se o plugin DNS está disponível
    if ! certbot plugins | grep -q dns; then
        log "Instalando plugins DNS para certbot..."
        apt-get update
        apt-get install -y python3-certbot-dns-cloudflare python3-certbot-dns-route53 python3-certbot-dns-google
    fi
    
    echo ""
    echo "🌐 CONFIGURAÇÃO DNS CHALLENGE"
    echo ""
    echo "Para usar DNS-01 challenge, você precisa configurar credenciais do seu provedor DNS:"
    echo ""
    echo "Provedores suportados:"
    echo "1) Cloudflare"
    echo "2) Route53 (AWS)"
    echo "3) Google Cloud DNS"
    echo "4) Manual (para outros provedores)"
    echo ""
    read -p "Escolha seu provedor DNS (1-4): " dns_provider
    
    case $dns_provider in
        1)
            setup_cloudflare_dns
            ;;
        2)
            setup_route53_dns
            ;;
        3)
            setup_google_dns
            ;;
        4)
            setup_manual_dns
            ;;
        *)
            error "Opção inválida"
            ;;
    esac
}

setup_cloudflare_dns() {
    log "Configurando Cloudflare DNS..."
    
    echo ""
    echo "📋 CONFIGURAÇÃO CLOUDFLARE"
    echo ""
    echo "1. Acesse: https://dash.cloudflare.com/profile/api-tokens"
    echo "2. Crie um token com permissões:"
    echo "   - Zone:Zone:Read"
    echo "   - Zone:DNS:Edit"
    echo "3. Inclua o domínio samureye.com.br na zona"
    echo ""
    read -p "Digite seu Cloudflare API Token: " cf_token
    
    if [ -z "$cf_token" ]; then
        error "Token é obrigatório"
    fi
    
    # Criar arquivo de credenciais
    mkdir -p /etc/letsencrypt
    cat > /etc/letsencrypt/cloudflare.ini << EOF
dns_cloudflare_api_token = $cf_token
EOF
    
    chmod 600 /etc/letsencrypt/cloudflare.ini
    
    # Obter certificado wildcard
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        -d "*.samureye.com.br" \
        -d "samureye.com.br"
    
    setup_letsencrypt_success
}

setup_route53_dns() {
    log "Configurando Route53 DNS..."
    
    echo ""
    echo "📋 CONFIGURAÇÃO AWS ROUTE53"
    echo ""
    echo "1. Configure as credenciais AWS (AWS CLI ou IAM Role)"
    echo "2. O usuário/role deve ter permissões:"
    echo "   - route53:ChangeResourceRecordSets"
    echo "   - route53:ListHostedZones"
    echo "   - route53:GetHostedZone"
    echo ""
    read -p "Pressione ENTER após configurar as credenciais AWS..."
    
    # Verificar se AWS CLI está configurado
    if ! aws sts get-caller-identity &> /dev/null; then
        echo ""
        echo "Configure as credenciais AWS:"
        read -p "AWS Access Key ID: " aws_key
        read -p "AWS Secret Access Key: " aws_secret
        read -p "AWS Region [us-east-1]: " aws_region
        aws_region=${aws_region:-us-east-1}
        
        mkdir -p ~/.aws
        cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $aws_key
aws_secret_access_key = $aws_secret
EOF
        
        cat > ~/.aws/config << EOF
[default]
region = $aws_region
EOF
    fi
    
    # Obter certificado wildcard
    certbot certonly \
        --dns-route53 \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        -d "*.samureye.com.br" \
        -d "samureye.com.br"
    
    setup_letsencrypt_success
}

setup_google_dns() {
    log "Configurando Google Cloud DNS..."
    
    echo ""
    echo "📋 CONFIGURAÇÃO GOOGLE CLOUD DNS"
    echo ""
    echo "1. Crie uma Service Account no Google Cloud Console"
    echo "2. Atribua a role 'DNS Administrator'"
    echo "3. Baixe o arquivo JSON da chave"
    echo ""
    read -p "Digite o caminho completo para o arquivo JSON da service account: " gcp_key_file
    
    if [ ! -f "$gcp_key_file" ]; then
        error "Arquivo de chave não encontrado: $gcp_key_file"
    fi
    
    # Copiar arquivo de credenciais
    cp "$gcp_key_file" /etc/letsencrypt/google.json
    chmod 600 /etc/letsencrypt/google.json
    
    # Obter certificado wildcard
    certbot certonly \
        --dns-google \
        --dns-google-credentials /etc/letsencrypt/google.json \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        -d "*.samureye.com.br" \
        -d "samureye.com.br"
    
    setup_letsencrypt_success
}

setup_manual_dns() {
    log "Configurando DNS Manual..."
    
    echo ""
    echo "📋 CONFIGURAÇÃO MANUAL DNS"
    echo ""
    echo "ATENÇÃO: Você precisará criar registros TXT manualmente durante o processo."
    echo "IMPORTANTE: O Let's Encrypt pode solicitar MÚLTIPLOS registros TXT com o MESMO nome."
    echo "Alguns provedores DNS exigem que você mantenha AMBOS os registros."
    echo ""
    echo "Tenha acesso ao painel DNS do seu provedor aberto."
    echo ""
    read -p "Pressione ENTER para continuar..."
    
    # Verificar rate limits antes de prosseguir
    check_rate_limit
    
    echo ""
    echo "🔄 INICIANDO PROCESSO DE VALIDAÇÃO DNS"
    echo "Você precisará adicionar os registros TXT conforme solicitado..."
    echo ""
    
    # Obter certificado com validação manual - usando apenas o domínio principal primeiro
    log "Obtendo certificado wildcard..."
    certbot certonly \
        --manual \
        --preferred-challenges dns \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --manual-public-ip-logging-ok \
        -d "*.samureye.com.br" \
        -d "samureye.com.br"
    
    local result=$?
    
    if [ $result -eq 0 ]; then
        setup_letsencrypt_success
    else
        echo ""
        echo "❌ ERRO NA OBTENÇÃO DO CERTIFICADO"
        echo ""
        echo "Possíveis causas:"
        echo "1. Rate limit do Let's Encrypt (5 certs/domínio/semana)"
        echo "2. Registros DNS não configurados corretamente"
        echo "3. Propagação DNS ainda em andamento"
        echo ""
        echo "Soluções:"
        echo "- Aguarde algumas horas se hit rate limit"
        echo "- Verifique se TODOS os registros TXT foram adicionados"
        echo "- Use: dig TXT _acme-challenge.samureye.com.br"
        echo "- Tente novamente com staging: certbot --staging"
        echo ""
        error "Falha na obtenção do certificado"
    fi
}

# DNS Manual Assistido - Evita rate limiting e melhora a experiência
setup_dns_assisted() {
    log "Configurando DNS Manual Assistido..."
    
    echo ""
    echo "📋 DNS MANUAL ASSISTIDO"
    echo ""
    echo "Este método evita problemas de rate limiting criando um processo passo a passo."
    echo "Vamos usar certificado de staging primeiro, depois o real."
    echo ""
    
    # Verificar rate limits
    check_rate_limit
    
    echo "🔬 PASSO 1: TESTE COM CERTIFICADO DE STAGING"
    echo ""
    echo "Primeiro vamos obter um certificado de teste para validar o processo."
    echo "Isso não conta para o limite de rate do Let's Encrypt."
    echo ""
    read -p "Pressione ENTER para iniciar o teste com staging..."
    
    # Passo 1: Certificado de staging
    log "Obtendo certificado de staging para teste..."
    certbot certonly \
        --manual \
        --preferred-challenges dns \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --staging \
        --manual-public-ip-logging-ok \
        -d "*.samureye.com.br" \
        -d "samureye.com.br"
    
    local staging_result=$?
    
    if [ $staging_result -ne 0 ]; then
        error "Falha no certificado de staging. Verifique os registros DNS e tente novamente."
    fi
    
    log "✅ Certificado de staging obtido com sucesso!"
    echo ""
    echo "🎯 PASSO 2: CERTIFICADO DE PRODUÇÃO"
    echo ""
    echo "Agora que o processo foi validado, vamos obter o certificado real."
    echo "IMPORTANTE: Use os MESMOS registros DNS do teste anterior."
    echo ""
    
    # Limpar certificado de staging
    certbot delete --cert-name samureye.com.br --non-interactive 2>/dev/null || true
    
    read -p "Pressione ENTER para obter o certificado de produção..."
    
    # Passo 2: Certificado de produção
    log "Obtendo certificado de produção..."
    certbot certonly \
        --manual \
        --preferred-challenges dns \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --manual-public-ip-logging-ok \
        -d "*.samureye.com.br" \
        -d "samureye.com.br"
    
    local prod_result=$?
    
    if [ $prod_result -eq 0 ]; then
        log "✅ Certificado de produção obtido com sucesso!"
        setup_letsencrypt_success
    else
        echo ""
        echo "❌ ERRO NO CERTIFICADO DE PRODUÇÃO"
        echo ""
        echo "Possíveis soluções:"
        echo "1. Aguarde 10-15 minutos e tente novamente"
        echo "2. Verifique se os registros DNS ainda estão ativos"
        echo "3. Use: dig TXT _acme-challenge.samureye.com.br @8.8.8.8"
        echo "4. Se hit rate limit, aguarde 1-24 horas"
        echo ""
        
        read -p "Tentar novamente agora? (s/N): " retry_now
        if [[ "$retry_now" =~ ^[Ss]$ ]]; then
            log "Tentando novamente..."
            sleep 30
            certbot certonly \
                --manual \
                --preferred-challenges dns \
                --email $EMAIL \
                --agree-tos \
                --no-eff-email \
                --manual-public-ip-logging-ok \
                -d "*.samureye.com.br" \
                -d "samureye.com.br"
            
            if [ $? -eq 0 ]; then
                log "✅ Sucesso na segunda tentativa!"
                setup_letsencrypt_success
            else
                error "Falha persistente. Aguarde algumas horas e tente novamente."
            fi
        else
            error "Processo cancelado. Execute o script novamente quando estiver pronto."
        fi
    fi
}

setup_letsencrypt_success() {
    if [ $? -eq 0 ]; then
        log "Certificados Let's Encrypt obtidos com sucesso!"
        
        # Para certificados manuais, não configurar renovação automática
        if grep -q "manual" /etc/letsencrypt/renewal/samureye.com.br.conf 2>/dev/null; then
            warn "Certificado manual detectado - renovação automática não disponível"
            echo ""
            echo "📅 RENOVAÇÃO MANUAL NECESSÁRIA"
            echo "Este certificado expira em 90 dias e deve ser renovado manualmente."
            echo "Para renovar, execute novamente:"
            echo "  sudo ./setup-certificates.sh"
            echo "  Escolha opção 7 (DNS Manual Assistido)"
            echo ""
            
            # Configurar lembrete de renovação manual
            log "Configurando lembrete de renovação manual..."
            
            # Copiar script de lembrete
            cp "$(dirname "$0")/renewal-reminder.sh" /opt/renewal-reminder.sh 2>/dev/null || \
            cat > /opt/renewal-reminder.sh << 'EOF'
#!/bin/bash
CERT_PATH="/etc/letsencrypt/live/samureye.com.br/fullchain.pem"
if [ -f "$CERT_PATH" ]; then
    EXPIRY_DATE=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
    CURRENT_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
    if [ $DAYS_LEFT -le 30 ]; then
        echo "⚠️  Certificado SSL SamurEye expira em $DAYS_LEFT dias!"
        echo "Execute: sudo /opt/setup-certificates.sh (opção 7)"
        logger "SamurEye SSL certificate expires in $DAYS_LEFT days - manual renewal required"
    fi
fi
EOF
            
            chmod +x /opt/renewal-reminder.sh
            
            # Adicionar cron para verificação semanal
            cat > /etc/cron.d/ssl-renewal-reminder << 'EOF'
# Verificação semanal de expiração de certificado SSL SamurEye
0 9 * * 1 root /opt/renewal-reminder.sh
EOF
            
            log "Lembrete de renovação configurado (verificação semanal)"
        else
            # Configurar renovação automática apenas para certificados automatizados
            cat > /etc/cron.d/certbot-renew << 'EOF'
# Renovação automática de certificados Let's Encrypt
0 12 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx"
EOF
            log "Renovação automática configurada com hooks"
        fi
        
        # Script de pré-hook para parar nginx se necessário
        mkdir -p /etc/letsencrypt/renewal-hooks/pre
        cat > /etc/letsencrypt/renewal-hooks/pre/nginx-stop.sh << 'EOF'
#!/bin/bash
# Para nginx apenas se usando HTTP-01 challenge
if [ "$RENEWED_DOMAINS" ] && [ -f /etc/nginx/nginx.conf ]; then
    systemctl is-active --quiet nginx && systemctl stop nginx
fi
EOF
        
        # Script de pós-hook para iniciar nginx
        mkdir -p /etc/letsencrypt/renewal-hooks/post
        cat > /etc/letsencrypt/renewal-hooks/post/nginx-start.sh << 'EOF'
#!/bin/bash
# Reinicia nginx após renovação
if [ "$RENEWED_DOMAINS" ] && [ -f /etc/nginx/nginx.conf ]; then
    systemctl start nginx 2>/dev/null || systemctl reload nginx
fi
EOF
        
        chmod +x /etc/letsencrypt/renewal-hooks/pre/nginx-stop.sh
        chmod +x /etc/letsencrypt/renewal-hooks/post/nginx-start.sh
        
        log "Renovação automática configurada com hooks"
        
        # Testar renovação apenas para certificados não manuais
        if ! grep -q "manual" /etc/letsencrypt/renewal/samureye.com.br.conf 2>/dev/null; then
            log "Testando processo de renovação..."
            certbot renew --dry-run
            
            if [ $? -eq 0 ]; then
                log "Teste de renovação passou! Certificados serão renovados automaticamente."
            else
                warn "Teste de renovação falhou. Verifique a configuração."
            fi
        else
            log "Certificado manual - pular teste de renovação automática"
        fi
        
    else
        error "Falha ao obter certificados Let's Encrypt"
    fi
}

# Migrar certificados individuais para wildcard
migrate_to_wildcard() {
    log "Migrando certificados Let's Encrypt individuais para certificado wildcard..."
    
    # Verificar se existem certificados individuais
    if [ ! -d "/etc/letsencrypt/live/app.samureye.com.br" ]; then
        error "Certificados individuais não encontrados. Execute a opção 1 para criar novos certificados."
    fi
    
    log "Fazendo backup dos certificados atuais..."
    mkdir -p /opt/letsencrypt-backup
    cp -r /etc/letsencrypt/live /opt/letsencrypt-backup/
    cp -r /etc/letsencrypt/renewal /opt/letsencrypt-backup/
    
    log "Removendo certificados individuais..."
    certbot delete --cert-name app.samureye.com.br --non-interactive 2>/dev/null || true
    certbot delete --cert-name api.samureye.com.br --non-interactive 2>/dev/null || true  
    certbot delete --cert-name scanner.samureye.com.br --non-interactive 2>/dev/null || true
    
    log "Criando novo certificado wildcard..."
    setup_letsencrypt
    
    if [ $? -eq 0 ]; then
        log "Migração concluída com sucesso!"
        log "Backup dos certificados antigos salvo em /opt/letsencrypt-backup/"
    else
        error "Falha na migração. Restaurando certificados originais..."
        cp -r /opt/letsencrypt-backup/live /etc/letsencrypt/
        cp -r /opt/letsencrypt-backup/renewal /etc/letsencrypt/
    fi
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
    
    # Detectar tipo de certificado e configurar paths apropriados
    if [ -f "/etc/letsencrypt/live/samureye.com.br/fullchain.pem" ]; then
        log "Usando certificados Let's Encrypt wildcard"
        CERT_PATH="/etc/letsencrypt/live/samureye.com.br/fullchain.pem"
        KEY_PATH="/etc/letsencrypt/live/samureye.com.br/privkey.pem"
        
        # Atualizar todos os caminhos para usar certificado wildcard
        sed -i "s|ssl_certificate .*|ssl_certificate $CERT_PATH;|g" /etc/nginx/sites-available/samureye
        sed -i "s|ssl_certificate_key .*|ssl_certificate_key $KEY_PATH;|g" /etc/nginx/sites-available/samureye
        
        # Adicionar configurações SSL recomendadas do Let's Encrypt se não existirem
        if ! grep -q "options-ssl-nginx.conf" /etc/nginx/sites-available/samureye; then
            sed -i '/ssl_certificate_key/a\    include /etc/letsencrypt/options-ssl-nginx.conf;' /etc/nginx/sites-available/samureye
            sed -i '/options-ssl-nginx.conf/a\    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;' /etc/nginx/sites-available/samureye
        fi
        
    elif [ -f "/etc/letsencrypt/live/app.samureye.com.br/fullchain.pem" ]; then
        log "Usando certificados Let's Encrypt individuais (migrar para wildcard recomendado)"
        # Manter configuração existente por compatibilidade
        
    elif [ -f "/etc/ssl/samureye/samureye.crt" ]; then
        log "Usando certificados auto-assinados"
        CERT_PATH="/etc/ssl/samureye/samureye.crt"
        KEY_PATH="/etc/ssl/samureye/samureye.key"
        
        # Atualizar todos os caminhos para certificados auto-assinados
        sed -i "s|ssl_certificate .*|ssl_certificate $CERT_PATH;|g" /etc/nginx/sites-available/samureye
        sed -i "s|ssl_certificate_key .*|ssl_certificate_key $KEY_PATH;|g" /etc/nginx/sites-available/samureye
        
        # Remover includes do Let's Encrypt para auto-assinados
        sed -i '/include \/etc\/letsencrypt\/options-ssl-nginx.conf/d' /etc/nginx/sites-available/samureye
        sed -i '/ssl_dhparam \/etc\/letsencrypt\/ssl-dhparams.pem/d' /etc/nginx/sites-available/samureye
        
        # Adicionar configurações SSL básicas para auto-assinados
        if ! grep -q "ssl_protocols" /etc/nginx/sites-available/samureye; then
            sed -i '/ssl_certificate_key/a\    ssl_protocols TLSv1.2 TLSv1.3;' /etc/nginx/sites-available/samureye
            sed -i '/ssl_protocols/a\    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;' /etc/nginx/sites-available/samureye
            sed -i '/ssl_ciphers/a\    ssl_prefer_server_ciphers off;' /etc/nginx/sites-available/samureye
        fi
    else
        warn "Nenhum certificado encontrado. Configure certificados antes de prosseguir."
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
echo "1) Let's Encrypt via DNS Challenge (Produção - Recomendado)"
echo "2) Certificados Auto-assinados (Desenvolvimento/Teste)"
echo "3) Configurar step-ca (CA Interna para mTLS)"
echo "4) Apenas configurar NGINX"
echo "5) Verificar certificados existentes"
echo "6) Migrar certificados individuais para wildcard"
echo "7) DNS Manual Assistido (recomendado para primeiro uso)"
echo ""
read -p "Digite sua escolha (1-7): " choice

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
        # Usar script local se disponível, senão usar o instalado
        if [ -f "$(dirname "$0")/check-ssl-status.sh" ]; then
            bash "$(dirname "$0")/check-ssl-status.sh"
        elif [ -f "/opt/check-ssl-status.sh" ]; then
            /opt/check-ssl-status.sh
        else
            echo "Script de verificação não encontrado"
        fi
        ;;
    6)
        migrate_to_wildcard
        ;;
    7)
        setup_dns_assisted
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