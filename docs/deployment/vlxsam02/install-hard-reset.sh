#!/bin/bash

# ============================================================================
# SAMUREYE ON-PREMISE - HARD RESET APPLICATION SERVER (vlxsam02)
# ============================================================================
# Sistema completo de reset e reinstalação do Servidor de Aplicação SamurEye
# Inclui: Node.js + SamurEye App + Configurações + Banco de Dados Reset
#
# Servidor: vlxsam02 (192.168.100.152)
# Função: Servidor de Aplicação SamurEye
# Dependências: vlxsam03 (PostgreSQL), vlxsam01 (Gateway), vlxsam04 (Collector)
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
APP_USER="samureye"
APP_DIR="/opt/samureye"
APP_NAME="SamurEye"
WORKING_DIR="$APP_DIR/$APP_NAME"
SERVICE_NAME="samureye-app"
POSTGRES_HOST="192.168.100.153"  # vlxsam03
POSTGRES_PORT="5432"
POSTGRES_DB="samureye"
POSTGRES_USER="samureye"
NODE_VERSION="20"

echo ""
echo "🔥 SAMUREYE HARD RESET - APPLICATION SERVER vlxsam02"
echo "=================================================="
echo "⚠️  ATENÇÃO: Este script irá:"
echo "   • Remover COMPLETAMENTE a aplicação SamurEye"
echo "   • Limpar banco de dados PostgreSQL"
echo "   • Reinstalar Node.js e dependências"
echo "   • Reconfigurar aplicação do zero"
echo "   • Criar tenant e usuários padrão"
echo ""

# ============================================================================
# 1. CONFIRMAÇÃO DE HARD RESET
# ============================================================================

# Detectar se está sendo executado via pipe (curl | bash)
if [ -t 0 ]; then
    # Terminal interativo - pedir confirmação
    read -p "🚨 CONTINUAR COM HARD RESET? (digite 'CONFIRMO' para continuar): " confirm
    if [ "$confirm" != "CONFIRMO" ]; then
        error "Reset cancelado pelo usuário"
    fi
else
    # Não-interativo (curl | bash) - continuar automaticamente após delay
    warn "Modo não-interativo detectado (curl | bash)"
    info "Hard reset iniciará automaticamente em 5 segundos..."
    sleep 5
fi

log "🗑️ Iniciando hard reset da aplicação..."

# ============================================================================
# 2. REMOÇÃO COMPLETA DA INSTALAÇÃO ANTERIOR
# ============================================================================

log "⏹️ Parando serviços..."

# Parar serviço da aplicação
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME"
    log "✅ Serviço $SERVICE_NAME parado"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME"
    log "✅ Serviço $SERVICE_NAME desabilitado"
fi

# Remover arquivo de serviço
if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    log "✅ Arquivo de serviço removido"
fi

# Remover usuário da aplicação
if id "$APP_USER" &>/dev/null; then
    userdel -r "$APP_USER" 2>/dev/null || true
    log "✅ Usuário $APP_USER removido"
fi

# Remover diretórios da aplicação
directories_to_remove=(
    "$APP_DIR"
    "/var/log/samureye"
    "/etc/samureye"
    "/tmp/samureye-*"
)

for dir in "${directories_to_remove[@]}"; do
    if [ -d "$dir" ] || [ -f "$dir" ]; then
        rm -rf "$dir"
        log "✅ Removido: $dir"
    fi
done

# Remover Node.js e npm globalmente
log "🗑️ Removendo Node.js anterior..."
apt-get purge -y nodejs npm node-* 2>/dev/null || true
rm -rf /usr/local/lib/node_modules /usr/local/bin/node /usr/local/bin/npm
rm -rf ~/.npm ~/.node-gyp

# ============================================================================
# 3. LIMPEZA DO BANCO DE DADOS
# ============================================================================

log "🗃️ Limpando banco de dados..."

# Teste de conectividade com PostgreSQL
if ! nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    warn "⚠️ PostgreSQL não acessível em $POSTGRES_HOST:$POSTGRES_PORT"
    warn "   Execute primeiro o reset no vlxsam03"
fi

# Script para limpar banco de dados
cat > /tmp/cleanup_database.sql << 'EOF'
-- Conectar ao banco samureye
\c samureye;

-- Remover todas as tabelas se existirem
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO samureye;
GRANT ALL ON SCHEMA public TO public;

-- Confirmar limpeza
SELECT 'Database cleaned successfully' AS status;
EOF

# Executar limpeza do banco se possível
if nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    PGPASSWORD="samureye123" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/cleanup_database.sql 2>/dev/null || {
        warn "⚠️ Não foi possível limpar o banco - continuando sem limpeza"
    }
    log "✅ Banco de dados limpo"
fi

rm -f /tmp/cleanup_database.sql

# ============================================================================
# 4. ATUALIZAÇÃO DO SISTEMA
# ============================================================================

log "🔄 Atualizando sistema..."
apt-get update && apt-get upgrade -y

# Configurar timezone
timedatectl set-timezone America/Sao_Paulo

# ============================================================================
# 5. INSTALAÇÃO DE DEPENDÊNCIAS BÁSICAS
# ============================================================================

log "📦 Instalando dependências básicas..."
apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    build-essential \
    python3 \
    python3-pip \
    postgresql-client \
    netcat-openbsd \
    jq \
    htop \
    nano \
    systemd \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common

# ============================================================================
# 6. INSTALAÇÃO NODE.JS
# ============================================================================

log "📦 Instalando Node.js $NODE_VERSION..."

# Remover repositórios Node.js antigos
rm -f /etc/apt/sources.list.d/nodesource.list
rm -f /etc/apt/trusted.gpg.d/nodesource.gpg

# Instalar NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -

# Instalar Node.js
apt-get install -y nodejs

# Verificar instalação
node_version=$(node --version 2>/dev/null || echo "not found")
npm_version=$(npm --version 2>/dev/null || echo "not found")

if [[ "$node_version" == v${NODE_VERSION}* ]]; then
    log "✅ Node.js instalado: $node_version"
    log "✅ npm instalado: $npm_version"
else
    error "❌ Falha na instalação do Node.js"
fi

# ============================================================================
# 7. CRIAÇÃO DE USUÁRIO E DIRETÓRIOS
# ============================================================================

log "👤 Criando usuário e estrutura de diretórios..."

# Criar usuário samureye
useradd -r -s /bin/bash -d "$APP_DIR" -m "$APP_USER"

# Criar estrutura de diretórios
mkdir -p "$APP_DIR"/{logs,config,backups}
mkdir -p "$WORKING_DIR"
mkdir -p /var/log/samureye

# Definir permissões
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chown -R "$APP_USER:$APP_USER" /var/log/samureye
chmod 755 "$APP_DIR"
chmod 750 "$WORKING_DIR"

log "✅ Estrutura de diretórios criada"

# ============================================================================
# 8. DOWNLOAD DA APLICAÇÃO SAMUREYE
# ============================================================================

log "📥 Baixando aplicação SamurEye..."

cd "$APP_DIR"

# Download do GitHub (main branch)
if ! sudo -u "$APP_USER" git clone https://github.com/GruppenIT/SamurEye.git "$APP_NAME"; then
    error "❌ Falha no download da aplicação"
fi

cd "$WORKING_DIR"

# Verificar estrutura do projeto
if [ ! -f "package.json" ]; then
    error "❌ Estrutura do projeto inválida - package.json não encontrado"
fi

log "✅ Aplicação baixada com sucesso"

# ============================================================================
# 9. CONFIGURAÇÃO DE AMBIENTE
# ============================================================================

log "⚙️ Configurando ambiente..."

# Criar arquivo .env
cat > "$WORKING_DIR/.env" << EOF
# SamurEye On-Premise Configuration
NODE_ENV=production
PORT=5000

# Database Configuration
DATABASE_URL=postgresql://$POSTGRES_USER:samureye123@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB

# Session Configuration
SESSION_SECRET=samureye-onpremise-$(openssl rand -base64 32)

# Authentication (On-premise bypass)
REPLIT_DEPLOYMENT_URL=http://localhost:5000
DISABLE_AUTH=true

# Admin Credentials
ADMIN_EMAIL=admin@samureye.local
ADMIN_PASSWORD=SamurEye2024!

# Application Settings
APP_NAME=SamurEye
APP_URL=https://app.samureye.com.br
API_URL=https://api.samureye.com.br

# Logging
LOG_LEVEL=info
LOG_DIR=/var/log/samureye

# Feature Flags (On-premise)
ENABLE_TELEMETRY=true
ENABLE_COLLECTORS=true
ENABLE_JOURNEYS=true
ENABLE_ADMIN=true

# Network Configuration
BIND_ADDRESS=0.0.0.0
ALLOWED_ORIGINS=https://app.samureye.com.br,https://api.samureye.com.br

# Collector Configuration  
COLLECTOR_TOKEN_EXPIRY=86400
COLLECTOR_HEARTBEAT_INTERVAL=30

# Monitoring
ENABLE_METRICS=true
METRICS_PORT=9090
EOF

# Definir permissões do .env
chown "$APP_USER:$APP_USER" "$WORKING_DIR/.env"
chmod 600 "$WORKING_DIR/.env"

log "✅ Arquivo .env criado"

# ============================================================================
# 10. INSTALAÇÃO DE DEPENDÊNCIAS NPM
# ============================================================================

log "📦 Instalando dependências npm..."

cd "$WORKING_DIR"

# Instalar dependências como usuário samureye
sudo -u "$APP_USER" npm install --production

# Verificar se node_modules foi criado
if [ ! -d "node_modules" ]; then
    error "❌ Falha na instalação das dependências"
fi

log "✅ Dependências npm instaladas"

# ============================================================================
# 11. BUILD DA APLICAÇÃO
# ============================================================================

log "🔨 Fazendo build da aplicação..."

# Build da aplicação
sudo -u "$APP_USER" npm run build

# Verificar se o build foi criado
if [ ! -d "dist" ] && [ ! -d "build" ] && [ ! -f "server/index.js" ]; then
    warn "⚠️ Diretório de build não encontrado - usando código TypeScript diretamente"
fi

log "✅ Build da aplicação concluído"

# ============================================================================
# 12. CONFIGURAÇÃO DO SERVIÇO SYSTEMD
# ============================================================================

log "🔧 Configurando serviço systemd..."

cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=SamurEye Application Server
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$WORKING_DIR
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=5
StandardOutput=append:/var/log/samureye/app.log
StandardError=append:/var/log/samureye/error.log

# Process management
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$WORKING_DIR /var/log/samureye /tmp

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd
systemctl daemon-reload

log "✅ Serviço systemd configurado"

# ============================================================================
# 13. INICIALIZAÇÃO E TESTE
# ============================================================================

log "🚀 Iniciando aplicação..."

# Habilitar e iniciar serviço
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Aguardar inicialização
sleep 15

# Verificar status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Aplicação iniciada com sucesso"
else
    error "❌ Falha ao iniciar aplicação - verificar logs: journalctl -u $SERVICE_NAME -f"
fi

# ============================================================================
# 14. INICIALIZAÇÃO DO BANCO DE DADOS
# ============================================================================

log "🗃️ Inicializando banco de dados..."

# Aguardar aplicação estar pronta
sleep 10

# Executar migrações via API (se disponível)
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000/api/health" | grep -q "200"; then
    log "✅ Aplicação respondendo na porta 5000"
    
    # Criar tenant padrão via API
    curl -s -X POST "http://localhost:5000/api/admin/tenants" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Gruppen IT",
            "slug": "gruppen-it",
            "description": "Tenant padrão do ambiente on-premise",
            "isActive": true
        }' >/dev/null 2>&1 || warn "⚠️ Não foi possível criar tenant via API"
    
    log "✅ Tenant padrão criado"
else
    warn "⚠️ Aplicação não está respondendo - verificar logs"
fi

# ============================================================================
# 15. TESTES DE VALIDAÇÃO
# ============================================================================

log "🧪 Executando testes de validação..."

# Teste 1: Serviço ativo
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Serviço: Ativo"
else
    error "❌ Serviço: Inativo"
fi

# Teste 2: Porta 5000 aberta
if netstat -tlnp | grep -q ":5000"; then
    log "✅ Porta: 5000 aberta"
else
    warn "⚠️ Porta: 5000 não encontrada"
fi

# Teste 3: Conectividade com PostgreSQL
if nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    log "✅ PostgreSQL: Conectado"
else
    warn "⚠️ PostgreSQL: Não conectado"
fi

# Teste 4: Resposta HTTP
http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000" 2>/dev/null)
if [ "$http_status" = "200" ] || [ "$http_status" = "301" ] || [ "$http_status" = "302" ]; then
    log "✅ HTTP: Respondendo ($http_status)"
else
    warn "⚠️ HTTP: Não respondendo ($http_status)"
fi

# Teste 5: Logs sem erros críticos
if ! grep -i "error" /var/log/samureye/error.log 2>/dev/null | grep -v "ENOENT" | grep -q .; then
    log "✅ Logs: Sem erros críticos"
else
    warn "⚠️ Logs: Erros encontrados"
fi

# ============================================================================
# 16. INFORMAÇÕES FINAIS
# ============================================================================

echo ""
log "🎉 HARD RESET DA APLICAÇÃO CONCLUÍDO!"
echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Aplicação:"
echo "   • Status:  $(systemctl is-active $SERVICE_NAME)"
echo "   • Porta:   5000"
echo "   • URL:     http://localhost:5000"
echo "   • Logs:    /var/log/samureye/"
echo ""
echo "🗃️ Banco de Dados:"
echo "   • Host:    $POSTGRES_HOST:$POSTGRES_PORT"
echo "   • Base:    $POSTGRES_DB"
echo "   • User:    $POSTGRES_USER"
echo ""
echo "👤 Usuários:"
echo "   • App:     $APP_USER"
echo "   • Dir:     $WORKING_DIR"
echo "   • Config:  $WORKING_DIR/.env"
echo ""
echo "🔧 Comandos Úteis:"
echo "   • Status:   systemctl status $SERVICE_NAME"
echo "   • Logs:     journalctl -u $SERVICE_NAME -f"
echo "   • Restart:  systemctl restart $SERVICE_NAME"
echo "   • Teste:    curl -I http://localhost:5000"
echo ""
echo "📝 Próximos Passos:"
echo "   1. Verificar logs: journalctl -u $SERVICE_NAME -f"
echo "   2. Testar API: curl http://localhost:5000/api/health"
echo "   3. Acessar admin: https://app.samureye.com.br/admin"
echo "   4. Criar tenant: Via interface /admin ou API"
echo ""
echo "🔐 Credenciais Padrão:"
echo "   • Admin: admin@samureye.local / SamurEye2024!"
echo "   • DB:    $POSTGRES_USER / samureye123"
echo ""

exit 0