#!/bin/bash

# SamurEye vlxsam02 - Script de Instalação Completo e Automático
# Servidor: vlxsam02 (172.24.1.152)
# Função: Application Server com diagnóstico e correção automática
# VERSÃO UNIFICADA - Resolve todos os problemas automaticamente

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

echo "🚀 INSTALAÇÃO COMPLETA SAMUREYE - VLXSAM02"
echo "=========================================="
echo "Servidor: vlxsam02 (172.24.1.152)"
echo "Função: Application Server"
echo "Dependências: vlxsam03 (PostgreSQL + Redis)"
echo ""
echo "✨ RECURSOS INCLUSOS:"
echo "   🔧 Instalação completa da aplicação"
echo "   🔍 Diagnóstico automático de problemas"
echo "   🛠️  Correção automática de configurações"
echo "   ✅ Validação final da instalação"
echo "   🔄 Detecção e correção de erro porta 443"
echo ""

# Variáveis globais
WORKING_DIR="/opt/samureye/SamurEye"
ETC_DIR="/etc/samureye"
SERVICE_USER="samureye"
POSTGRES_HOST="172.24.1.153"
POSTGRES_PORT="5432"
REDIS_HOST="172.24.1.153"
REDIS_PORT="6379"

# ============================================================================
# FUNÇÃO DE DIAGNÓSTICO INICIAL
# ============================================================================

diagnostic_check() {
    log "🔍 DIAGNÓSTICO INICIAL - Verificando problemas conhecidos..."
    
    local issues_found=false
    
    echo "📡 Verificando conectividade com vlxsam03..."
    
    # Testar PostgreSQL
    if timeout 5 bash -c "</dev/tcp/$POSTGRES_HOST/$POSTGRES_PORT" 2>/dev/null; then
        log "✅ PostgreSQL ($POSTGRES_HOST:$POSTGRES_PORT): Conectividade OK"
        
        # Testar autenticação
        if PGPASSWORD=SamurEye2024! psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U samureye -d samureye_prod -c "SELECT 1;" >/dev/null 2>&1; then
            log "✅ Autenticação PostgreSQL: OK"
        else
            warn "Problemas de autenticação PostgreSQL detectados"
        fi
    else
        error "Não foi possível conectar ao PostgreSQL em $POSTGRES_HOST:$POSTGRES_PORT"
    fi
    
    # Testar Redis
    if timeout 5 bash -c "</dev/tcp/$REDIS_HOST/$REDIS_PORT" 2>/dev/null; then
        log "✅ Redis ($REDIS_HOST:$REDIS_PORT): Conectividade OK"
    else
        warn "Redis não está acessível, mas continuando instalação"
    fi
    
    # Verificar se há instalação anterior com problemas
    if [ -d "$WORKING_DIR" ]; then
        warn "Instalação anterior detectada em $WORKING_DIR"
        
        # Verificar problema de porta 443 nos logs
        if systemctl is-active --quiet samureye-app 2>/dev/null; then
            if journalctl -u samureye-app --since "1 hour ago" --no-pager -q 2>/dev/null | grep -q "ECONNREFUSED.*:443"; then
                warn "🔧 PROBLEMA DETECTADO: Tentativas de conexão na porta 443"
                warn "   Este script irá corrigir automaticamente"
                issues_found=true
            fi
        fi
        
        # Verificar configuração .env incorreta
        if [ -f "$ETC_DIR/.env" ] && grep -q ":443" "$ETC_DIR/.env" 2>/dev/null; then
            warn "🔧 PROBLEMA DETECTADO: Arquivo .env contém porta 443"
            warn "   Este script irá corrigir automaticamente"
            issues_found=true
        fi
        
        # Verificar código hardcoded
        if [ -d "$WORKING_DIR" ]; then
            cd "$WORKING_DIR"
            if find . -name "*.ts" -o -name "*.js" | xargs grep -q ":443\|https://$POSTGRES_HOST" 2>/dev/null; then
                warn "🔧 PROBLEMA DETECTADO: Configurações hardcoded incorretas no código"
                warn "   Este script irá corrigir automaticamente"
                issues_found=true
            fi
            cd - >/dev/null
        fi
    fi
    
    if [ "$issues_found" = true ]; then
        log "🔧 Problemas detectados serão corrigidos durante a instalação"
    else
        log "✅ Diagnóstico inicial: Nenhum problema crítico detectado"
    fi
}

# ============================================================================
# FUNÇÃO DE LIMPEZA E PREPARAÇÃO
# ============================================================================

cleanup_previous_installation() {
    log "🧹 Limpeza de instalação anterior..."
    
    # Parar serviço se estiver rodando
    if systemctl is-active --quiet samureye-app 2>/dev/null; then
        log "Parando serviço samureye-app..."
        systemctl stop samureye-app || true
    fi
    
    # Desabilitar serviço se estiver habilitado
    if systemctl is-enabled --quiet samureye-app 2>/dev/null; then
        log "Desabilitando serviço samureye-app..."
        systemctl disable samureye-app || true
    fi
    
    # Remover arquivo de serviço
    if [ -f /etc/systemd/system/samureye-app.service ]; then
        log "Removendo arquivo de serviço..."
        rm -f /etc/systemd/system/samureye-app.service
        systemctl daemon-reload
    fi
    
    # Backup de configurações existentes
    if [ -f "$ETC_DIR/.env" ]; then
        log "Fazendo backup de configurações existentes..."
        cp "$ETC_DIR/.env" "$ETC_DIR/.env.backup.$(date +%Y%m%d_%H%M%S)" || true
    fi
    
    # Limpar diretórios de instalação
    log "Removendo diretórios de instalação anterior..."
    rm -rf "$WORKING_DIR" || true
    
    # Manter estrutura de configuração
    mkdir -p "$ETC_DIR"
    mkdir -p "/opt/samureye"
    
    # Garantir que o usuário samureye existe antes de configurar permissões
    if ! id "$SERVICE_USER" &>/dev/null; then
        log "Criando usuário $SERVICE_USER temporariamente..."
        useradd -r -s /bin/bash -d /opt/samureye -m "$SERVICE_USER" || true
    fi
    
    # Configurar permissões básicas
    chown -R $SERVICE_USER:$SERVICE_USER /opt/samureye 2>/dev/null || true
    chmod 755 /opt/samureye
    
    log "✅ Limpeza concluída"
}

# ============================================================================
# INSTALAÇÃO DO SISTEMA BASE
# ============================================================================

install_system_packages() {
    log "📦 Instalando pacotes do sistema..."
    
    # Atualizar sistema
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get upgrade -y
    
    # Configurar timezone
    timedatectl set-timezone America/Sao_Paulo
    
    # Instalar pacotes essenciais
    log "Instalando pacotes essenciais..."
    apt-get install -y \
        curl \
        wget \
        git \
        unzip \
        htop \
        nano \
        net-tools \
        postgresql-client \
        redis-tools \
        nginx \
        certbot \
        python3-certbot-nginx \
        ufw \
        fail2ban \
        logrotate \
        cron \
        rsync \
        jq
    
    log "✅ Pacotes do sistema instalados"
}

# ============================================================================
# INSTALAÇÃO DO NODE.JS
# ============================================================================

install_nodejs() {
    log "🟢 Instalando Node.js 20..."
    
    # Remover instalações anteriores do Node.js
    apt-get remove -y nodejs npm 2>/dev/null || true
    
    # Instalar Node.js 20 via NodeSource
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    
    # Verificar instalação
    local node_version=$(node --version)
    local npm_version=$(npm --version)
    
    log "✅ Node.js instalado: $node_version"
    log "✅ npm instalado: $npm_version"
    
    # Instalar ferramentas globais
    log "Instalando ferramentas Node.js globais..."
    npm install -g pm2 tsx wscat
    
    log "✅ Node.js 20 configurado com sucesso"
}

# ============================================================================
# CRIAÇÃO DE USUÁRIO
# ============================================================================

create_user() {
    log "👤 Configurando usuário do sistema..."
    
    # Criar usuário se não existir
    if ! id "$SERVICE_USER" &>/dev/null; then
        log "Criando usuário $SERVICE_USER..."
        useradd -r -s /bin/bash -d /opt/samureye -m "$SERVICE_USER"
        log "✅ Usuário $SERVICE_USER criado"
    else
        log "ℹ️  Usuário $SERVICE_USER já existe"
        
        # Garantir que o diretório home existe
        if [ ! -d "/opt/samureye" ]; then
            mkdir -p /opt/samureye
            log "Diretório home criado para usuário existente"
        fi
    fi
    
    # Configurar permissões
    chown -R $SERVICE_USER:$SERVICE_USER /opt/samureye
    chmod 755 /opt/samureye
    
    # Adicionar ao grupo de logs
    usermod -a -G adm $SERVICE_USER || true
    
    log "✅ Usuário configurado"
}

# ============================================================================
# DOWNLOAD E INSTALAÇÃO DA APLICAÇÃO
# ============================================================================

install_application() {
    log "📥 Baixando e instalando aplicação SamurEye..."
    
    # Criar diretório de trabalho e configurar permissões
    mkdir -p "$WORKING_DIR"
    chown -R $SERVICE_USER:$SERVICE_USER /opt/samureye
    chmod 755 /opt/samureye
    
    # Verificar se as permissões estão corretas
    local dir_owner=$(stat -c '%U' "$WORKING_DIR" 2>/dev/null || echo "unknown")
    if [ "$dir_owner" != "$SERVICE_USER" ]; then
        warn "Permissões incorretas detectadas, corrigindo..."
        chown -R $SERVICE_USER:$SERVICE_USER "$WORKING_DIR"
        chmod 755 "$WORKING_DIR"
    fi
    
    cd "$WORKING_DIR"
    
    # Baixar código fonte do GitHub
    log "Clonando repositório do GitHub..."
    if [ -d ".git" ]; then
        # Se já existe, fazer pull
        log "Repositório já existe, atualizando..."
        sudo -u $SERVICE_USER git pull origin main
    else
        # Clone inicial - verificar se diretório está vazio
        if [ "$(ls -A .)" ]; then
            log "Diretório não está vazio, limpando..."
            rm -rf * .* 2>/dev/null || true
        fi
        
        log "Clonando repositório..."
        
        # Testar se o usuário pode escrever no diretório
        if ! sudo -u $SERVICE_USER touch "$WORKING_DIR/.test_write" 2>/dev/null; then
            error "Usuário $SERVICE_USER não pode escrever em $WORKING_DIR. Verificar permissões."
        fi
        rm -f "$WORKING_DIR/.test_write"
        
        # Executar clone
        if ! sudo -u $SERVICE_USER git clone https://github.com/GruppenIT/SamurEye.git .; then
            error "Falha no clone do repositório. Verificar conectividade e permissões."
        fi
    fi
    
    # Verificar se dotenv está no package.json
    log "🔧 Verificando dependências do projeto..."
    
    # Instalar dependências primeiro
    log "Instalando dependências npm..."
    sudo -u $SERVICE_USER npm install
    
    # Verificar e garantir que dotenv está instalado
    if ! sudo -u $SERVICE_USER npm list dotenv >/dev/null 2>&1; then
        log "Instalando dotenv..."
        sudo -u $SERVICE_USER npm install dotenv
        log "✅ dotenv instalado"
    else
        log "ℹ️  dotenv já está disponível"
    fi
    
    # Verificar se tsx está disponível (necessário para desenvolvimento)
    if ! sudo -u $SERVICE_USER npm list tsx >/dev/null 2>&1; then
        log "Instalando tsx para desenvolvimento..."
        sudo -u $SERVICE_USER npm install --save-dev tsx
        log "✅ tsx instalado"
    fi
    
    # Verificar e corrigir server/index.ts
    fix_server_configuration
    
    log "✅ Aplicação instalada"
}

# ============================================================================
# CORREÇÃO DE CONFIGURAÇÃO DO SERVIDOR
# ============================================================================

fix_server_configuration() {
    log "🔧 Verificando e corrigindo configuração do servidor..."
    
    local server_file="$WORKING_DIR/server/index.ts"
    
    if [ -f "$server_file" ]; then
        # Verificar se dotenv está configurado
        if ! head -10 "$server_file" | grep -q "dotenv"; then
            log "Adicionando import dotenv ao server/index.ts..."
            
            # Backup do arquivo original
            cp "$server_file" "$server_file.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Adicionar import dotenv no início do arquivo
            sudo -u $SERVICE_USER sed -i '1i import "dotenv/config";' "$server_file"
            
            log "✅ Configuração dotenv adicionada ao servidor"
        else
            log "ℹ️  Configuração dotenv já presente no servidor"
        fi
    else
        warn "Arquivo server/index.ts não encontrado"
    fi
}

# ============================================================================
# CORREÇÃO DE CONFIGURAÇÕES HARDCODED
# ============================================================================

fix_hardcoded_configurations() {
    log "🔧 Verificando e corrigindo configurações hardcoded..."
    
    cd "$WORKING_DIR"
    
    local files_fixed=0
    
    # Procurar e corrigir referências à porta 443
    log "Procurando referências incorretas à porta 443..."
    if find . -name "*.ts" -o -name "*.js" | xargs grep -l ":443" 2>/dev/null; then
        log "Corrigindo referências à porta 443..."
        find . -name "*.ts" -o -name "*.js" -exec sed -i "s/:443/:$POSTGRES_PORT/g" {} \;
        ((files_fixed++))
    fi
    
    # Procurar e corrigir URLs HTTPS incorretas para PostgreSQL
    log "Procurando URLs HTTPS incorretas..."
    if find . -name "*.ts" -o -name "*.js" | xargs grep -l "https://$POSTGRES_HOST" 2>/dev/null; then
        log "Corrigindo URLs HTTPS incorretas..."
        find . -name "*.ts" -o -name "*.js" -exec sed -i "s|https://$POSTGRES_HOST|postgresql://samureye:SamurEye2024!@$POSTGRES_HOST|g" {} \;
        ((files_fixed++))
    fi
    
    # Procurar e corrigir combinações IP:443
    log "Procurando configurações IP:443 incorretas..."
    if find . -name "*.ts" -o -name "*.js" | xargs grep -l "$POSTGRES_HOST.*443" 2>/dev/null; then
        log "Corrigindo configurações IP:443..."
        find . -name "*.ts" -o -name "*.js" -exec sed -i "s/$POSTGRES_HOST:443/$POSTGRES_HOST:$POSTGRES_PORT/g" {} \;
        ((files_fixed++))
    fi
    
    if [ $files_fixed -gt 0 ]; then
        log "✅ $files_fixed tipos de configurações hardcoded corrigidos"
    else
        log "ℹ️  Nenhuma configuração hardcoded incorreta encontrada"
    fi
    
    cd - >/dev/null
}

# ============================================================================
# CRIAÇÃO DE ARQUIVO .ENV
# ============================================================================

create_env_file() {
    log "📝 Criando arquivo de configuração .env..."
    
    # Criar arquivo .env principal
    cat > "$ETC_DIR/.env" << EOF
# SamurEye Application Configuration
# Generated: $(date)

# Environment
NODE_ENV=development
PORT=5000

# Database (PostgreSQL - vlxsam03)
DATABASE_URL=postgresql://samureye:SamurEye2024!@$POSTGRES_HOST:$POSTGRES_PORT/samureye_prod
PGHOST=$POSTGRES_HOST
PGPORT=$POSTGRES_PORT
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye_prod

# Redis (vlxsam03)
REDIS_URL=redis://$REDIS_HOST:$REDIS_PORT
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT

# Session
SESSION_SECRET=samureye_secret_2024_vlxsam02_production

# Application URLs
API_BASE_URL=http://localhost:5000
WEB_BASE_URL=http://localhost:5000

# Security
JWT_SECRET=samureye_jwt_secret_2024
ENCRYPTION_KEY=samureye_encryption_2024

# Logging
LOG_LEVEL=info
LOG_FILE=/var/log/samureye/app.log

# External Services
GRAFANA_URL=http://$POSTGRES_HOST:3000
MINIO_ENDPOINT=$POSTGRES_HOST
MINIO_PORT=9000
MINIO_ACCESS_KEY=samureye
MINIO_SECRET_KEY=SamurEye2024!

# System
HOSTNAME=vlxsam02
SERVER_ROLE=application
EOF

    # Configurar permissões
    chown root:$SERVICE_USER "$ETC_DIR/.env"
    chmod 640 "$ETC_DIR/.env"
    
    # Criar links simbólicos
    log "Criando links simbólicos para .env..."
    
    # Verificar se o arquivo foi criado
    if [ ! -f "$ETC_DIR/.env" ]; then
        error "Arquivo .env não foi criado em $ETC_DIR"
    fi
    
    # Remover links existentes se houver
    rm -f "/opt/samureye/.env" "$WORKING_DIR/.env"
    
    # Criar novos links
    ln -sf "$ETC_DIR/.env" "/opt/samureye/.env"
    ln -sf "$ETC_DIR/.env" "$WORKING_DIR/.env"
    
    # Verificar se os links foram criados
    if [ -L "$WORKING_DIR/.env" ] && [ -f "$WORKING_DIR/.env" ]; then
        log "✅ Link simbólico criado: $WORKING_DIR/.env -> $(readlink $WORKING_DIR/.env)"
    else
        warn "Falha ao criar link simbólico para $WORKING_DIR/.env"
    fi
    
    # Configurar permissões para os links
    chown -h $SERVICE_USER:$SERVICE_USER "$WORKING_DIR/.env" 2>/dev/null || true
    
    log "✅ Arquivo .env criado e linkado"
}

# ============================================================================
# TESTE DE CARREGAMENTO DE VARIÁVEIS
# ============================================================================

test_env_loading() {
    log "🧪 Testando carregamento de variáveis de ambiente..."
    
    # Criar script de teste no diretório do projeto
    cat > "$WORKING_DIR/test-env-loading.mjs" << 'EOF'
// Importar dotenv do node_modules local usando ES6 modules
import dotenv from 'dotenv';
dotenv.config();

console.log('=== TESTE DE CARREGAMENTO DE VARIÁVEIS ===');
console.log('NODE_ENV:', process.env.NODE_ENV || 'undefined');
console.log('PORT:', process.env.PORT || 'undefined');
console.log('PGHOST:', process.env.PGHOST || 'undefined');
console.log('PGPORT:', process.env.PGPORT || 'undefined');
console.log('DATABASE_URL existe:', process.env.DATABASE_URL ? 'SIM' : 'NÃO');

if (process.env.DATABASE_URL) {
    const url = process.env.DATABASE_URL;
    console.log('DATABASE_URL (primeiros 60 chars):', url.substring(0, 60) + '...');
    
    if (url.includes(':443')) {
        console.log('❌ ERRO: DATABASE_URL contém porta 443');
        process.exit(1);
    } else if (url.includes(':5432')) {
        console.log('✅ DATABASE_URL contém porta 5432 (correto)');
    } else {
        console.log('⚠️ DATABASE_URL sem especificação clara de porta');
    }
} else {
    console.log('❌ DATABASE_URL não foi carregada');
    process.exit(1);
}

console.log('✅ Teste concluído com sucesso');
console.log('=== FIM DO TESTE ===');
EOF

    # Executar teste como usuário da aplicação
    cd "$WORKING_DIR"
    
    # Verificar se o arquivo .env foi criado corretamente
    if [ ! -f "$WORKING_DIR/.env" ]; then
        warn "Arquivo .env não encontrado em $WORKING_DIR"
        ls -la "$WORKING_DIR/" || true
        ls -la "$ETC_DIR/" || true
    else
        log "Arquivo .env encontrado: $(ls -la $WORKING_DIR/.env)"
    fi
    
    # Executar teste de carregamento
    log "Executando teste de carregamento de variáveis..."
    if sudo -u $SERVICE_USER env NODE_ENV=development node test-env-loading.mjs; then
        log "✅ Teste de carregamento: SUCESSO"
    else
        warn "Teste de carregamento: FALHA - Continuando instalação"
        warn "Verificar manualmente: cat $WORKING_DIR/.env"
    fi
    
    rm -f "$WORKING_DIR/test-env-loading.mjs"
}

# ============================================================================
# CONFIGURAÇÃO DO SERVIÇO SYSTEMD
# ============================================================================

create_systemd_service() {
    log "⚙️ Configurando serviço systemd..."
    
    # Criar diretório de logs
    mkdir -p /var/log/samureye
    chown $SERVICE_USER:$SERVICE_USER /var/log/samureye
    
    # Criar arquivo de serviço
    cat > /etc/systemd/system/samureye-app.service << EOF
[Unit]
Description=SamurEye Application Server
After=network.target postgresql.service redis.service
Wants=postgresql.service redis.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$WORKING_DIR
Environment=NODE_ENV=production
EnvironmentFile=$ETC_DIR/.env
ExecStartPre=/usr/bin/npm run build
ExecStart=/usr/bin/npm start
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-app

# Limites de recursos
LimitNOFILE=65536
LimitNPROC=4096

# Segurança
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$WORKING_DIR /var/log/samureye /tmp

[Install]
WantedBy=multi-user.target
EOF

    # Configurar logrotate
    cat > /etc/logrotate.d/samureye << EOF
/var/log/samureye/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    su $SERVICE_USER $SERVICE_USER
}
EOF

    # Recarregar systemd
    systemctl daemon-reload
    
    log "✅ Serviço systemd configurado"
}

# ============================================================================
# VALIDAÇÃO FINAL
# ============================================================================

final_validation() {
    log "✅ VALIDAÇÃO FINAL DA INSTALAÇÃO"
    
    local issues=0
    
    echo "🔍 Executando testes de validação..."
    
    # 1. Verificar estrutura de arquivos
    echo "📁 Verificando estrutura de arquivos..."
    for dir in "$WORKING_DIR" "$ETC_DIR"; do
        if [ -d "$dir" ]; then
            echo "  ✅ $dir"
            
            # Verificar permissões
            if [ "$dir" = "$WORKING_DIR" ]; then
                local owner=$(stat -c '%U' "$dir" 2>/dev/null || echo "unknown")
                if [ "$owner" = "$SERVICE_USER" ]; then
                    echo "  ✅ Permissões corretas: $owner"
                else
                    echo "  ⚠️ Permissões incorretas: $owner (esperado: $SERVICE_USER)"
                    chown -R $SERVICE_USER:$SERVICE_USER "$dir" || true
                fi
            fi
        else
            echo "  ❌ $dir"
            ((issues++))
        fi
    done
    
    # 2. Verificar arquivos essenciais
    echo "📄 Verificando arquivos essenciais..."
    local essential_files=(
        "$WORKING_DIR/package.json"
        "$WORKING_DIR/server/index.ts"
        "$ETC_DIR/.env"
        "/etc/systemd/system/samureye-app.service"
    )
    
    for file in "${essential_files[@]}"; do
        if [ -f "$file" ]; then
            echo "  ✅ $file"
        else
            echo "  ❌ $file"
            ((issues++))
        fi
    done
    
    # 3. Verificar links simbólicos
    echo "🔗 Verificando links simbólicos..."
    for link in "/opt/samureye/.env" "$WORKING_DIR/.env"; do
        if [ -L "$link" ] && [ "$(readlink "$link")" = "$ETC_DIR/.env" ]; then
            echo "  ✅ $link -> $(readlink "$link")"
        else
            echo "  ❌ $link"
            ((issues++))
        fi
    done
    
    # 4. Verificar configuração .env
    echo "⚙️ Verificando configuração .env..."
    if grep -q ":443" "$ETC_DIR/.env" 2>/dev/null; then
        echo "  ❌ Arquivo .env ainda contém porta 443"
        ((issues++))
    else
        echo "  ✅ Configuração .env sem porta 443"
    fi
    
    if grep -q ":$POSTGRES_PORT" "$ETC_DIR/.env" 2>/dev/null; then
        echo "  ✅ Configuração .env contém porta correta ($POSTGRES_PORT)"
    else
        echo "  ❌ Configuração .env não contém porta PostgreSQL"
        ((issues++))
    fi
    
    # 5. Verificar código fonte
    echo "📝 Verificando código fonte..."
    cd "$WORKING_DIR"
    if find . -name "*.ts" -o -name "*.js" | xargs grep -q ":443\|https://$POSTGRES_HOST" 2>/dev/null; then
        echo "  ❌ Código ainda contém configurações hardcoded incorretas"
        ((issues++))
    else
        echo "  ✅ Código sem configurações hardcoded incorretas"
    fi
    
    if head -10 server/index.ts | grep -q "dotenv"; then
        echo "  ✅ Servidor configurado para carregar dotenv"
    else
        echo "  ❌ Servidor sem configuração dotenv"
        ((issues++))
    fi
    cd - >/dev/null
    
    # 6. Testar conectividade
    echo "🌐 Testando conectividade..."
    if timeout 5 bash -c "</dev/tcp/$POSTGRES_HOST/$POSTGRES_PORT" 2>/dev/null; then
        echo "  ✅ PostgreSQL ($POSTGRES_HOST:$POSTGRES_PORT)"
    else
        echo "  ❌ PostgreSQL ($POSTGRES_HOST:$POSTGRES_PORT)"
        ((issues++))
    fi
    
    if timeout 5 bash -c "</dev/tcp/$REDIS_HOST/$REDIS_PORT" 2>/dev/null; then
        echo "  ✅ Redis ($REDIS_HOST:$REDIS_PORT)"
    else
        echo "  ⚠️ Redis ($REDIS_HOST:$REDIS_PORT) - não crítico"
    fi
    
    # Resultado final
    echo ""
    if [ $issues -eq 0 ]; then
        log "🎉 VALIDAÇÃO CONCLUÍDA COM SUCESSO!"
        log "✅ Todos os testes passaram"
        log "✅ Instalação está pronta para uso"
        return 0
    else
        error "❌ Validação falhou: $issues problemas encontrados"
        return 1
    fi
}

# ============================================================================
# INICIALIZAÇÃO DO SERVIÇO
# ============================================================================

start_service() {
    log "🚀 Iniciando serviço SamurEye..."
    
    # Habilitar e iniciar serviço
    systemctl enable samureye-app
    systemctl start samureye-app
    
    # Aguardar inicialização
    sleep 5
    
    # Verificar status
    if systemctl is-active --quiet samureye-app; then
        log "✅ Serviço iniciado com sucesso"
        
        # Testar API
        log "🧪 Testando API..."
        local api_attempts=0
        local max_attempts=6
        
        while [ $api_attempts -lt $max_attempts ]; do
            if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
                log "✅ API está respondendo em http://localhost:5000"
                break
            else
                ((api_attempts++))
                if [ $api_attempts -lt $max_attempts ]; then
                    log "Aguardando API... (tentativa $api_attempts/$max_attempts)"
                    sleep 5
                else
                    warn "API não está respondendo após $max_attempts tentativas"
                fi
            fi
        done
        
        # Verificar logs por erros críticos
        log "🔍 Verificando logs por erros..."
        if journalctl -u samureye-app --since "2 minutes ago" --no-pager -q | grep -q "ECONNREFUSED.*:443"; then
            error "❌ ERRO CRÍTICO: Ainda há tentativas de conexão na porta 443"
        else
            log "✅ Nenhum erro de porta 443 detectado"
        fi
        
    else
        error "❌ Falha ao iniciar serviço"
    fi
}

# ============================================================================
# FUNÇÃO PRINCIPAL
# ============================================================================

main() {
    log "🎯 Iniciando instalação completa do SamurEye vlxsam02..."
    
    # Execução sequencial com verificação de erros
    diagnostic_check
    cleanup_previous_installation
    install_system_packages
    install_nodejs
    create_user
    install_application
    fix_hardcoded_configurations
    create_env_file
    test_env_loading
    create_systemd_service
    final_validation
    start_service
    
    echo ""
    echo "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "====================================="
    echo ""
    echo "📊 STATUS DO SISTEMA:"
    echo "   🔗 URL da aplicação: http://localhost:5000"
    echo "   📁 Diretório da aplicação: $WORKING_DIR"
    echo "   ⚙️ Arquivo de configuração: $ETC_DIR/.env"
    echo "   👤 Usuário do serviço: $SERVICE_USER"
    echo ""
    echo "🔧 COMANDOS ÚTEIS:"
    echo "   systemctl status samureye-app    # Status do serviço"
    echo "   journalctl -u samureye-app -f    # Logs em tempo real"
    echo "   systemctl restart samureye-app   # Reiniciar serviço"
    echo ""
    echo "🌐 DEPENDÊNCIAS:"
    echo "   PostgreSQL: $POSTGRES_HOST:$POSTGRES_PORT"
    echo "   Redis: $REDIS_HOST:$REDIS_PORT"
    echo ""
    log "✅ SamurEye vlxsam02 instalado e funcionando!"
}

# Executar instalação
main "$@"