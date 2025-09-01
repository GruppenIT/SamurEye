#!/bin/bash

# ============================================================================
# SAMUREYE ON-PREMISE - HARD RESET DATABASE SERVER (vlxsam03)
# ============================================================================
# Sistema completo de reset e reinstalação do Servidor de Banco de Dados
# Inclui: PostgreSQL 16 + Redis + MinIO + Grafana + Configurações
#
# Servidor: vlxsam03 (192.168.100.153)
# Função: Servidor de Banco de Dados e Serviços de Apoio
# Dependências: Rede 192.168.100.0/24
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
POSTGRES_VERSION="16"
POSTGRES_USER="samureye"
POSTGRES_DB="samureye"
POSTGRES_PASSWORD="samureye123"
REDIS_PASSWORD="redis123"
MINIO_USER="minio"
MINIO_PASSWORD="minio123"
GRAFANA_PASSWORD="grafana123"

echo ""
echo "🔥 SAMUREYE HARD RESET - DATABASE SERVER vlxsam03"
echo "==============================================="
echo "⚠️  ATENÇÃO: Este script irá:"
echo "   • Remover COMPLETAMENTE PostgreSQL, Redis, MinIO e Grafana"
echo "   • APAGAR TODOS OS DADOS do banco de dados"
echo "   • Reinstalar todos os serviços do zero"
echo "   • Reconfigurar rede e firewall"
echo "   • Criar estrutura de dados inicial"
echo ""

# ============================================================================
# 1. CONFIRMAÇÃO DE HARD RESET
# ============================================================================

read -p "🚨 CONTINUAR COM HARD RESET? (digite 'CONFIRMO' para continuar): " confirm
if [ "$confirm" != "CONFIRMO" ]; then
    error "Reset cancelado pelo usuário"
fi

log "🗑️ Iniciando hard reset do servidor de banco de dados..."

# ============================================================================
# 2. REMOÇÃO COMPLETA DE SERVIÇOS
# ============================================================================

log "⏹️ Parando e removendo serviços..."

# Lista de serviços para remover
services_to_remove=("postgresql" "redis-server" "minio" "grafana-server")

for service in "${services_to_remove[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        systemctl stop "$service"
        log "✅ $service parado"
    fi
    
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        systemctl disable "$service"
        log "✅ $service desabilitado"
    fi
done

# Remover pacotes PostgreSQL completamente
log "🗑️ Removendo PostgreSQL..."
apt-get purge -y postgresql* 2>/dev/null || true
apt-get autoremove -y

# Remover pacotes Redis
log "🗑️ Removendo Redis..."
apt-get purge -y redis* 2>/dev/null || true

# Remover pacotes MinIO
log "🗑️ Removendo MinIO..."
rm -f /usr/local/bin/minio /usr/local/bin/mc
systemctl stop minio 2>/dev/null || true
systemctl disable minio 2>/dev/null || true
rm -f /etc/systemd/system/minio.service

# Remover Grafana
log "🗑️ Removendo Grafana..."
apt-get purge -y grafana 2>/dev/null || true

# Remover usuários de sistema
users_to_remove=("postgres" "redis" "minio" "grafana")
for user in "${users_to_remove[@]}"; do
    if id "$user" &>/dev/null; then
        userdel -r "$user" 2>/dev/null || true
        log "✅ Usuário $user removido"
    fi
done

# Remover diretórios de dados
directories_to_remove=(
    "/var/lib/postgresql"
    "/etc/postgresql"
    "/var/lib/redis"
    "/etc/redis"
    "/opt/minio"
    "/var/lib/minio"
    "/etc/minio"
    "/var/lib/grafana"
    "/etc/grafana"
    "/var/log/postgresql"
    "/var/log/redis"
    "/var/log/grafana"
)

for dir in "${directories_to_remove[@]}"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        log "✅ Removido: $dir"
    fi
done

systemctl daemon-reload

log "✅ Remoção completa dos serviços finalizada"

# ============================================================================
# 3. ATUALIZAÇÃO DO SISTEMA
# ============================================================================

log "🔄 Atualizando sistema..."
apt-get update && apt-get upgrade -y

# Configurar timezone
timedatectl set-timezone America/Sao_Paulo

# ============================================================================
# 4. INSTALAÇÃO DE DEPENDÊNCIAS BÁSICAS
# ============================================================================

log "📦 Instalando dependências básicas..."
apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    gnupg \
    lsb-release \
    ca-certificates \
    software-properties-common \
    apt-transport-https \
    netcat-openbsd \
    htop \
    nano \
    jq \
    systemd

# ============================================================================
# 5. INSTALAÇÃO E CONFIGURAÇÃO POSTGRESQL 16
# ============================================================================

log "🐘 Instalando PostgreSQL $POSTGRES_VERSION..."

# Adicionar repositório oficial PostgreSQL
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Atualizar e instalar PostgreSQL
apt-get update
apt-get install -y postgresql-$POSTGRES_VERSION postgresql-client-$POSTGRES_VERSION postgresql-contrib-$POSTGRES_VERSION

# Verificar instalação
if systemctl is-active --quiet postgresql; then
    log "✅ PostgreSQL $POSTGRES_VERSION instalado e ativo"
else
    error "❌ Falha na instalação do PostgreSQL"
fi

# Configurar PostgreSQL
log "⚙️ Configurando PostgreSQL..."

# Configurar postgresql.conf
PG_CONFIG="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
cp "$PG_CONFIG" "$PG_CONFIG.backup"

cat > "$PG_CONFIG" << EOF
# SamurEye PostgreSQL Configuration
# Basic Settings
data_directory = '/var/lib/postgresql/$POSTGRES_VERSION/main'
hba_file = '/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf'
ident_file = '/etc/postgresql/$POSTGRES_VERSION/main/pg_ident.conf'
external_pid_file = '/var/run/postgresql/$POSTGRES_VERSION-main.pid'

# Connection Settings
listen_addresses = '*'
port = 5432
max_connections = 200
superuser_reserved_connections = 3

# Memory Settings
shared_buffers = 256MB
work_mem = 4MB
maintenance_work_mem = 64MB
effective_cache_size = 1GB

# WAL Settings
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB
checkpoint_completion_target = 0.9

# Logging
log_destination = 'stderr,csvlog'
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Locale
lc_messages = 'en_US.UTF-8'
lc_monetary = 'pt_BR.UTF-8'
lc_numeric = 'pt_BR.UTF-8'
lc_time = 'pt_BR.UTF-8'
default_text_search_config = 'pg_catalog.portuguese'

# Other Settings
timezone = 'America/Sao_Paulo'
shared_preload_libraries = 'pg_stat_statements'
EOF

# Configurar pg_hba.conf para SamurEye
PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"
cp "$PG_HBA" "$PG_HBA.backup"

cat > "$PG_HBA" << 'EOF'
# SamurEye PostgreSQL Client Authentication Configuration

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     peer

# SamurEye On-Premise Access
# vlxsam01 - Gateway
host    samureye        samureye        192.168.100.151/32      md5
# vlxsam02 - Application Server  
host    samureye        samureye        192.168.100.152/32      md5
# vlxsam03 - Database (local)
host    samureye        samureye        127.0.0.1/32            md5
host    samureye        samureye        192.168.100.153/32      md5
# vlxsam04 - Collector
host    samureye        samureye        192.168.100.154/32      md5
# Rede local SamurEye (backup)
host    samureye        samureye        192.168.100.0/24        md5

# Admin access
host    all             postgres        192.168.100.0/24        md5
host    all             postgres        127.0.0.1/32            md5

# Deny all other connections
host    all             all             0.0.0.0/0               reject
EOF

# Reiniciar PostgreSQL para aplicar configurações
systemctl restart postgresql

log "✅ PostgreSQL configurado"

# Configurar banco SamurEye
log "🗃️ Configurando banco SamurEye..."

# Criar usuário samureye
sudo -u postgres psql << EOF
-- Criar usuário samureye
DROP USER IF EXISTS $POSTGRES_USER;
CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';

-- Criar database samureye
DROP DATABASE IF EXISTS $POSTGRES_DB;
CREATE DATABASE $POSTGRES_DB WITH OWNER $POSTGRES_USER;

-- Conceder privilégios
GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;
ALTER USER $POSTGRES_USER CREATEDB;

-- Configurar extensões
\c $POSTGRES_DB;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Confirmar criação
\l
\du
EOF

log "✅ Banco SamurEye configurado"

# ============================================================================
# 6. INSTALAÇÃO E CONFIGURAÇÃO REDIS
# ============================================================================

log "🔴 Instalando Redis..."

apt-get install -y redis-server

# Configurar Redis
REDIS_CONFIG="/etc/redis/redis.conf"
cp "$REDIS_CONFIG" "$REDIS_CONFIG.backup"

cat > "$REDIS_CONFIG" << EOF
# SamurEye Redis Configuration
bind 0.0.0.0
port 6379
protected-mode yes
requireauth $REDIS_PASSWORD

# Memory and Persistence
maxmemory 512mb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000

# Logging
loglevel notice
logfile /var/log/redis/redis-server.log

# Security
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command DEBUG ""

# Network
timeout 300
tcp-keepalive 300
EOF

# Reiniciar Redis
systemctl restart redis-server
systemctl enable redis-server

if systemctl is-active --quiet redis-server; then
    log "✅ Redis instalado e configurado"
else
    error "❌ Falha na configuração do Redis"
fi

# ============================================================================
# 7. INSTALAÇÃO E CONFIGURAÇÃO MINIO
# ============================================================================

log "📦 Instalando MinIO..."

# Criar usuário minio
useradd -r -s /bin/false minio

# Baixar MinIO
cd /tmp
wget -q https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
mv minio /usr/local/bin/

# Baixar MinIO Client
wget -q https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
mv mc /usr/local/bin/

# Criar diretórios
mkdir -p /opt/minio/data
mkdir -p /etc/minio
chown -R minio:minio /opt/minio

# Configurar MinIO
cat > /etc/minio/minio.conf << EOF
# SamurEye MinIO Configuration
MINIO_ROOT_USER=$MINIO_USER
MINIO_ROOT_PASSWORD=$MINIO_PASSWORD
MINIO_VOLUMES="/opt/minio/data"
MINIO_OPTS="--console-address :9001"
EOF

# Criar serviço systemd
cat > /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO Object Storage
After=network.target
Wants=network.target

[Service]
Type=simple
User=minio
Group=minio
EnvironmentFile=/etc/minio/minio.conf
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minio
systemctl start minio

if systemctl is-active --quiet minio; then
    log "✅ MinIO instalado e configurado"
else
    warn "⚠️ MinIO pode ter problemas - verificar logs"
fi

# ============================================================================
# 8. INSTALAÇÃO E CONFIGURAÇÃO GRAFANA
# ============================================================================

log "📊 Instalando Grafana..."

# Adicionar repositório Grafana
curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/grafana.gpg
echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list

# Instalar Grafana
apt-get update
apt-get install -y grafana

# Configurar Grafana
GRAFANA_CONFIG="/etc/grafana/grafana.ini"
cp "$GRAFANA_CONFIG" "$GRAFANA_CONFIG.backup"

cat > "$GRAFANA_CONFIG" << EOF
# SamurEye Grafana Configuration
[server]
http_addr = 0.0.0.0
http_port = 3000
domain = grafana.samureye.local

[database]
type = postgres
host = localhost:5432
name = grafana
user = $POSTGRES_USER
password = $POSTGRES_PASSWORD

[security]
admin_user = admin
admin_password = $GRAFANA_PASSWORD
secret_key = samureye-grafana-$(openssl rand -base64 32)

[auth]
disable_login_form = false

[auth.anonymous]
enabled = false

[log]
mode = file
level = info
EOF

# Criar banco para Grafana
sudo -u postgres psql << EOF
CREATE DATABASE grafana WITH OWNER $POSTGRES_USER;
GRANT ALL PRIVILEGES ON DATABASE grafana TO $POSTGRES_USER;
EOF

systemctl enable grafana-server
systemctl start grafana-server

if systemctl is-active --quiet grafana-server; then
    log "✅ Grafana instalado e configurado"
else
    warn "⚠️ Grafana pode ter problemas - verificar logs"
fi

# ============================================================================
# 9. CONFIGURAÇÃO DE FIREWALL
# ============================================================================

log "🔒 Configurando firewall..."

# Instalar UFW se não estiver instalado
apt-get install -y ufw

# Reset UFW
ufw --force reset

# Política padrão
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH
ufw allow 22/tcp

# Permitir PostgreSQL (apenas rede interna)
ufw allow from 192.168.100.0/24 to any port 5432

# Permitir Redis (apenas rede interna)
ufw allow from 192.168.100.0/24 to any port 6379

# Permitir MinIO (apenas rede interna)
ufw allow from 192.168.100.0/24 to any port 9000
ufw allow from 192.168.100.0/24 to any port 9001

# Permitir Grafana (apenas rede interna)
ufw allow from 192.168.100.0/24 to any port 3000

# Ativar firewall
ufw --force enable

log "✅ Firewall configurado"

# ============================================================================
# 10. TESTES DE VALIDAÇÃO
# ============================================================================

log "🧪 Executando testes de validação..."

# Teste 1: PostgreSQL
if systemctl is-active --quiet postgresql; then
    if sudo -u postgres psql -c "\l" | grep -q "$POSTGRES_DB"; then
        log "✅ PostgreSQL: Ativo e banco criado"
    else
        warn "⚠️ PostgreSQL: Ativo mas sem banco"
    fi
else
    error "❌ PostgreSQL: Inativo"
fi

# Teste 2: Redis
if systemctl is-active --quiet redis-server; then
    if redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q "PONG"; then
        log "✅ Redis: Ativo e respondendo"
    else
        warn "⚠️ Redis: Ativo mas sem resposta"
    fi
else
    warn "⚠️ Redis: Inativo"
fi

# Teste 3: MinIO
if systemctl is-active --quiet minio; then
    if netstat -tlnp | grep -q ":9000"; then
        log "✅ MinIO: Ativo na porta 9000"
    else
        warn "⚠️ MinIO: Ativo mas porta não encontrada"
    fi
else
    warn "⚠️ MinIO: Inativo"
fi

# Teste 4: Grafana
if systemctl is-active --quiet grafana-server; then
    if netstat -tlnp | grep -q ":3000"; then
        log "✅ Grafana: Ativo na porta 3000"
    else
        warn "⚠️ Grafana: Ativo mas porta não encontrada"
    fi
else
    warn "⚠️ Grafana: Inativo"
fi

# Teste 5: Conectividade de rede
for port in 5432 6379 9000 3000; do
    if netstat -tlnp | grep -q ":$port"; then
        log "✅ Porta $port: Aberta"
    else
        warn "⚠️ Porta $port: Fechada"
    fi
done

# ============================================================================
# 11. CRIAÇÃO DE SCRIPT DE TESTE CONEXÃO
# ============================================================================

log "📝 Criando script de teste de conexão..."

cat > /usr/local/bin/test-samureye-db.sh << 'EOF'
#!/bin/bash
# Script de teste das conexões SamurEye

echo "🧪 TESTE DE CONEXÕES SAMUREYE DATABASE SERVER"
echo "=============================================="

# Teste PostgreSQL
echo -n "PostgreSQL: "
if sudo -u postgres psql -c "\l" | grep -q "samureye"; then
    echo "✅ OK"
else
    echo "❌ FALHA"
fi

# Teste Redis
echo -n "Redis: "
if redis-cli -a "redis123" ping 2>/dev/null | grep -q "PONG"; then
    echo "✅ OK"
else
    echo "❌ FALHA"
fi

# Teste MinIO
echo -n "MinIO: "
if curl -s http://localhost:9000/minio/health/live | grep -q "OK"; then
    echo "✅ OK"
else
    echo "❌ FALHA"
fi

# Teste Grafana
echo -n "Grafana: "
if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo "✅ OK"
else
    echo "❌ FALHA"
fi

echo ""
echo "📊 Status dos Serviços:"
systemctl is-active postgresql redis-server minio grafana-server | paste <(echo -e "PostgreSQL\nRedis\nMinIO\nGrafana") -

echo ""
echo "🔌 Portas Abertas:"
netstat -tlnp | grep -E ":5432|:6379|:9000|:3000" | awk '{print $4}' | sort
EOF

chmod +x /usr/local/bin/test-samureye-db.sh

# ============================================================================
# 12. INFORMAÇÕES FINAIS
# ============================================================================

echo ""
log "🎉 HARD RESET DO DATABASE SERVER CONCLUÍDO!"
echo ""
echo "📋 RESUMO DOS SERVIÇOS INSTALADOS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐘 PostgreSQL $POSTGRES_VERSION:"
echo "   • Status:  $(systemctl is-active postgresql)"
echo "   • Porta:   5432"
echo "   • Base:    $POSTGRES_DB"
echo "   • User:    $POSTGRES_USER"
echo "   • Pass:    $POSTGRES_PASSWORD"
echo ""
echo "🔴 Redis:"
echo "   • Status:  $(systemctl is-active redis-server)"
echo "   • Porta:   6379"
echo "   • Pass:    $REDIS_PASSWORD"
echo ""
echo "📦 MinIO Object Storage:"
echo "   • Status:  $(systemctl is-active minio)"
echo "   • API:     http://192.168.100.153:9000"
echo "   • Console: http://192.168.100.153:9001"
echo "   • User:    $MINIO_USER"
echo "   • Pass:    $MINIO_PASSWORD"
echo ""
echo "📊 Grafana:"
echo "   • Status:  $(systemctl is-active grafana-server)"
echo "   • URL:     http://192.168.100.153:3000"
echo "   • User:    admin"
echo "   • Pass:    $GRAFANA_PASSWORD"
echo ""
echo "🔧 Comandos Úteis:"
echo "   • Teste:     /usr/local/bin/test-samureye-db.sh"
echo "   • Logs PG:   tail -f /var/log/postgresql/postgresql-*.log"
echo "   • Logs Redis: tail -f /var/log/redis/redis-server.log"
echo "   • Status:    systemctl status postgresql redis-server minio grafana-server"
echo ""
echo "🔌 Conectividade:"
echo "   • PostgreSQL: psql -h 192.168.100.153 -U $POSTGRES_USER -d $POSTGRES_DB"
echo "   • Redis:      redis-cli -h 192.168.100.153 -a $REDIS_PASSWORD"
echo ""
echo "🔒 Segurança:"
echo "   • Firewall ativo para rede 192.168.100.0/24"
echo "   • Acesso externo bloqueado"
echo "   • Senhas configuradas para todos os serviços"
echo ""
echo "📝 Próximos Passos:"
echo "   1. Testar conexões: /usr/local/bin/test-samureye-db.sh"
echo "   2. Verificar logs dos serviços"
echo "   3. Configurar vlxsam02 para conectar no banco"
echo ""

exit 0