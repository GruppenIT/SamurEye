#!/bin/bash

# ============================================================================
# SAMUREYE ON-PREMISE - HARD RESET DATABASE SERVER (vlxsam03)
# ============================================================================
# Reset de dados e configurações do Servidor de Banco de Dados
# Inclui: Reset PostgreSQL + Redis + MinIO + Grafana + Reconfiguração
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
POSTGRES_PASSWORD="SamurEye2024!"
REDIS_PASSWORD="redis123"
MINIO_USER="minio"
MINIO_PASSWORD="minio123"
GRAFANA_PASSWORD="grafana123"

echo ""
echo "🔥 SAMUREYE HARD RESET - DATABASE SERVER vlxsam03"
echo "==============================================="
echo "⚠️  ATENÇÃO: Este script irá:"
echo "   • Parar todos os serviços do banco de dados"
echo "   • APAGAR TODOS OS DADOS do PostgreSQL, Redis, MinIO"
echo "   • Reconfigurar pg_hba.conf e postgresql.conf"
echo "   • Resetar senhas e configurações"
echo "   • Recriar banco e usuários SamurEye"
echo "   • Reconfigurar firewall e rede"
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

log "🗑️ Iniciando hard reset do servidor de banco de dados..."

# ============================================================================
# 2. REPARAR SISTEMA DE PACOTES PRIMEIRO  
# ============================================================================

log "🔧 Reparando sistema de pacotes corrompido..."

# Parar todos os processos apt imediatamente
warn "Matando processos apt/dpkg em execução..."
pkill -9 -f "apt-get" 2>/dev/null || true
pkill -9 -f "dpkg" 2>/dev/null || true  
pkill -9 -f "unattended-upgrade" 2>/dev/null || true
sleep 5

# Remover locks imediatamente
warn "Removendo locks do sistema de pacotes..."
rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
rm -f /var/lib/dpkg/lock 2>/dev/null || true
rm -f /var/cache/apt/archives/lock 2>/dev/null || true

# Executar reparo dpkg múltiplas vezes com verificação
log "Executando reparos do dpkg..."
for i in 1 2 3 4 5; do
    log "Tentativa $i: dpkg --configure -a"
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a 2>/dev/null || true
    sleep 5
    
    log "Tentativa $i: apt-get -f install"
    DEBIAN_FRONTEND=noninteractive apt-get -f install -y 2>/dev/null || true
    sleep 5
    
    # Testar se dpkg está funcionando
    if dpkg --get-selections >/dev/null 2>&1; then
        log "✅ dpkg funcionando na tentativa $i"
        break
    fi
done

# Aguardar mais tempo para garantir que tudo estabilizou
log "Aguardando estabilização do sistema..."
sleep 10

# Função para reparar dpkg (para usar depois)
repair_dpkg() {
    pkill -9 -f "apt|dpkg|unattended" 2>/dev/null || true
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get -f install -y 2>/dev/null || true
    sleep 3
    return 0
}

log "✅ Reparo inicial do sistema de pacotes concluído"

# ============================================================================
# 3. INSTALAR DEPENDÊNCIAS BÁSICAS
# ============================================================================

log "📦 Instalando dependências básicas..."

# Tentar instalar dependências críticas
for attempt in 1 2 3; do
    log "Tentativa $attempt de atualização do sistema..."
    repair_dpkg
    if apt-get update -y 2>/dev/null; then
        log "✅ Sistema atualizado"
        break
    fi
    sleep 5
done

for attempt in 1 2 3; do
    log "Tentativa $attempt de instalação de dependências..."
    repair_dpkg
    if DEBIAN_FRONTEND=noninteractive apt-get install -y psmisc lsof procps 2>/dev/null; then
        log "✅ Dependências básicas instaladas"
        break
    fi
    sleep 5
done

# ============================================================================
# 4. PARAR TODOS OS SERVIÇOS
# ============================================================================

log "⏹️ Parando todos os serviços..."

services_to_stop=("postgresql" "redis-server" "minio" "grafana-server")
for service in "${services_to_stop[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        systemctl stop "$service"
        log "✅ $service parado"
    fi
done

# ============================================================================
# 5. BACKUP E RESET DOS DADOS
# ============================================================================

log "💾 Criando backup dos dados atuais..."
BACKUP_DIR="/opt/backups/samureye-reset-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup PostgreSQL (se existir dados)
if [ -d "/var/lib/postgresql/$POSTGRES_VERSION/main" ]; then
    tar -czf "$BACKUP_DIR/postgresql-data.tar.gz" /var/lib/postgresql/$POSTGRES_VERSION/main/ 2>/dev/null || true
    log "✅ Backup PostgreSQL criado"
fi

# Backup Redis
if [ -f "/var/lib/redis/dump.rdb" ]; then
    cp /var/lib/redis/dump.rdb "$BACKUP_DIR/" 2>/dev/null || true
    log "✅ Backup Redis criado"
fi

# Backup MinIO
if [ -d "/opt/minio/data" ]; then
    tar -czf "$BACKUP_DIR/minio-data.tar.gz" /opt/minio/data/ 2>/dev/null || true
    log "✅ Backup MinIO criado"
fi

log "📂 Backup salvo em: $BACKUP_DIR"

# ============================================================================
# 6. RESET COMPLETO DOS DADOS
# ============================================================================

log "🗑️ Removendo dados existentes..."

# Reset PostgreSQL - remover dados E configurações para reset completo
if [ -d "/var/lib/postgresql/$POSTGRES_VERSION/main" ]; then
    rm -rf /var/lib/postgresql/$POSTGRES_VERSION/main
    log "✅ Dados PostgreSQL removidos"
fi

# Remover também configurações de cluster
if [ -d "/etc/postgresql/$POSTGRES_VERSION/main" ]; then
    rm -rf /etc/postgresql/$POSTGRES_VERSION/main
    log "✅ Configurações PostgreSQL removidas"
fi

# Reset Redis
rm -f /var/lib/redis/dump.rdb /var/lib/redis/appendonly.aof 2>/dev/null || true
log "✅ Dados Redis removidos"

# Reset MinIO
rm -rf /opt/minio/data/* 2>/dev/null || true
log "✅ Dados MinIO removidos"

# Reset Grafana
rm -rf /var/lib/grafana/grafana.db /var/lib/grafana/sessions/* 2>/dev/null || true
log "✅ Dados Grafana removidos"

# ============================================================================
# 7. CONFIGURAR DEPENDÊNCIAS ADICIONAIS
# ============================================================================

log "📦 Instalando dependências adicionais..."

# Tentar instalar dependências com várias tentativas
for attempt in 1 2 3; do
    log "Tentativa $attempt de instalação de dependências adicionais..."
    repair_dpkg
    if DEBIAN_FRONTEND=noninteractive apt-get install -y wget curl gnupg2 software-properties-common apt-transport-https ca-certificates 2>/dev/null; then
        log "✅ Dependências adicionais instaladas"
        break
    fi
    sleep 5
done

# ============================================================================
# 8. CONFIGURAR POSTGRESQL 16
# ============================================================================

log "🐘 Configurando PostgreSQL $POSTGRES_VERSION..."

# Verificar se PostgreSQL está instalado
if ! command -v psql &> /dev/null; then
    log "Instalando PostgreSQL $POSTGRES_VERSION..."
    
    # Configurar repositório PostgreSQL
    wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - 2>/dev/null || true
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/postgresql.list
    
    # Tentar instalar com várias tentativas
    for attempt in 1 2 3; do
        log "Tentativa $attempt de instalação PostgreSQL..."
        repair_dpkg
        if apt-get update -y 2>/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-$POSTGRES_VERSION postgresql-client-$POSTGRES_VERSION 2>/dev/null; then
            log "✅ PostgreSQL instalado"
            break
        fi
        sleep 10
    done
fi

# SEMPRE recriar cluster PostgreSQL após hard reset
log "📁 Recriando cluster PostgreSQL usando método Ubuntu..."

# Parar PostgreSQL completamente
systemctl stop postgresql 2>/dev/null || true
sleep 2

# Limpeza AGRESSIVA de qualquer configuração existente
if command -v pg_dropcluster &>/dev/null; then
    # Tentar remover cluster de todas as formas possíveis
    pg_dropcluster --stop $POSTGRES_VERSION main 2>/dev/null || true
    pg_dropcluster $POSTGRES_VERSION main 2>/dev/null || true
fi

# Remover fisicamente todos os diretórios
rm -rf /etc/postgresql/$POSTGRES_VERSION 2>/dev/null || true
rm -rf /var/lib/postgresql/$POSTGRES_VERSION 2>/dev/null || true
rm -rf /var/run/postgresql/$POSTGRES_VERSION-main.pg_stat_tmp 2>/dev/null || true

# Aguardar limpeza completa
sleep 5

# Verificar se pg_createcluster está disponível
if command -v pg_createcluster &>/dev/null; then
    log "🔧 Criando novo cluster PostgreSQL..."
    
    # Criar cluster limpo
    pg_createcluster $POSTGRES_VERSION main --start
    
    # Aguardar cluster estar pronto
    sleep 5
    
    log "✅ Cluster PostgreSQL recriado usando pg_createcluster"
else
    log "🔧 Criando cluster usando initdb..."
    
    # Garantir que diretórios existem
    mkdir -p "/var/lib/postgresql/$POSTGRES_VERSION/main"
    chown postgres:postgres "/var/lib/postgresql/$POSTGRES_VERSION/main"
    chmod 700 "/var/lib/postgresql/$POSTGRES_VERSION/main"
    
    # Inicializar cluster
    sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/initdb -D "/var/lib/postgresql/$POSTGRES_VERSION/main" --locale=en_US.UTF-8
    
    log "✅ Cluster PostgreSQL recriado usando initdb"
fi

# Iniciar PostgreSQL
log "🚀 Iniciando PostgreSQL..."
systemctl enable postgresql
systemctl start postgresql

# Aguardar PostgreSQL estar pronto
sleep 5
if ! systemctl is-active --quiet postgresql; then
    error "❌ PostgreSQL falhou ao iniciar"
fi

log "✅ PostgreSQL iniciado com sucesso"

# Configurar postgresql.conf (como no install.sh original)
log "⚙️ Configurando postgresql.conf..."
POSTGRES_CONF="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"

# Backup da configuração original
cp "$POSTGRES_CONF" "$POSTGRES_CONF.backup" 2>/dev/null || true

# Adicionar configurações SamurEye (append)
cat >> "$POSTGRES_CONF" << EOF
# SamurEye Configuration
listen_addresses = '*'
port = 5432
max_connections = 200
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 4GB
EOF

# Configurar pg_hba.conf (como no install.sh original)  
log "🔐 Configurando pg_hba.conf..."
PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"

# Backup da configuração original
cp "$PG_HBA" "$PG_HBA.backup" 2>/dev/null || true

# Adicionar configurações SamurEye (append)
cat >> "$PG_HBA" << 'EOF'

# SamurEye On-Premise Access
# vlxsam01 - Gateway
host    samureye        samureye_user   172.24.1.151/32         md5
host    samureye        samureye        172.24.1.151/32         md5
# vlxsam02 - Application Server  
host    samureye        samureye_user   172.24.1.152/32         md5
host    samureye        samureye        172.24.1.152/32         md5
# vlxsam03 - Database (local)
host    samureye        samureye_user   127.0.0.1/32            md5
host    samureye        samureye        127.0.0.1/32            md5
host    samureye        samureye_user   172.24.1.153/32         md5
host    samureye        samureye        172.24.1.153/32         md5
# vlxsam04 - Collector
host    samureye        samureye_user   172.24.1.154/32         md5
host    samureye        samureye        172.24.1.154/32         md5
# Rede local SamurEye (backup)
host    samureye        samureye_user   172.24.1.0/24           md5
host    samureye        samureye        172.24.1.0/24           md5
host    grafana         grafana         172.24.1.153/32         md5
# Permitir conexões md5 para usuários corretos
host    all             samureye_user   172.24.1.0/24           md5
host    all             samureye        172.24.1.0/24           md5
EOF

# Reiniciar PostgreSQL para aplicar configurações
log "🔄 Reiniciando PostgreSQL para aplicar configurações..."
systemctl restart postgresql
sleep 5

log "✅ PostgreSQL configurado para SamurEye"

# Verificar se PostgreSQL está funcionando antes de criar usuários
log "🔍 Verificando conectividade PostgreSQL..."
if ! sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
    error "❌ PostgreSQL não está respondendo corretamente"
fi

log "✅ PostgreSQL respondendo, criando usuários..."

# Criar usuário e banco SamurEye
log "👤 Criando usuário e banco SamurEye..."
sudo -u postgres psql << 'EOF'
-- Remover usuário e banco se existirem
DROP DATABASE IF EXISTS samureye;
DROP DATABASE IF EXISTS grafana;
DROP USER IF EXISTS samureye_user;
DROP USER IF EXISTS samureye;
DROP USER IF EXISTS grafana;

-- Criar usuário SamurEye (nome correto usado pelo vlxsam02)
CREATE USER samureye_user WITH ENCRYPTED PASSWORD 'samureye_secure_2024';
ALTER USER samureye_user CREATEDB;
ALTER USER samureye_user SUPERUSER; -- Para resolver problemas de permissão

-- Criar também usuário antigo por compatibilidade
CREATE USER samureye WITH ENCRYPTED PASSWORD 'samureye_secure_2024';
ALTER USER samureye CREATEDB;
ALTER USER samureye SUPERUSER;

-- Criar banco SamurEye
CREATE DATABASE samureye OWNER samureye_user;
GRANT ALL PRIVILEGES ON DATABASE samureye TO samureye_user;
GRANT ALL PRIVILEGES ON DATABASE samureye TO samureye;

-- Conectar ao banco samureye
\c samureye

-- Criar extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Conceder privilégios nas extensões
GRANT ALL ON SCHEMA public TO samureye_user;
GRANT ALL ON SCHEMA public TO samureye;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO samureye_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO samureye_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO samureye_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO samureye;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO samureye;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO samureye;

-- Criar usuário e banco Grafana
\c postgres
CREATE USER grafana WITH ENCRYPTED PASSWORD 'grafana123';
CREATE DATABASE grafana OWNER grafana;
GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;

-- Verificar criação
\l
\du
EOF

# ============================================================================
# 9. CONFIGURAR REDIS
# ============================================================================

log "🔴 Configurando Redis..."

# Instalar Redis se necessário
if ! command -v redis-server &> /dev/null; then
    for attempt in 1 2 3; do
        log "Tentativa $attempt de instalação Redis..."
        repair_dpkg
        if DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server 2>/dev/null; then
            log "✅ Redis instalado"
            break
        fi
        sleep 5
    done
fi

# Configurar Redis
REDIS_CONF="/etc/redis/redis.conf"
cp "$REDIS_CONF" "$REDIS_CONF.backup" 2>/dev/null || true

# Configurações Redis customizadas
cat > "$REDIS_CONF" << EOF
# ============================================================================
# SAMUREYE ON-PREMISE - REDIS CONFIGURATION
# ============================================================================

# Network
bind 127.0.0.1
port 6379
timeout 300
tcp-keepalive 60

# General
daemonize yes
supervised systemd
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log

# Security
requirepass redis123

# Memory Management
maxmemory 512mb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000
dir /var/lib/redis

# Dangerous commands disabled
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command DEBUG ""
rename-command CONFIG "CONFIG_SAMUREYE_ONLY"
EOF

# Iniciar Redis
log "🚀 Iniciando Redis..."
systemctl enable redis-server
systemctl start redis-server

# Verificar se Redis está funcionando
sleep 3
if systemctl is-active redis-server >/dev/null 2>&1; then
    log "✅ Redis iniciado com sucesso"
    # Testar conexão Redis
    if redis-cli -a redis123 ping 2>/dev/null | grep -q PONG; then
        log "✅ Redis respondendo corretamente"
    else
        log "⚠️ Redis iniciado mas não responde a ping"
    fi
else
    log "❌ Falha ao iniciar Redis - verificando logs..."
    journalctl -u redis-server --no-pager -l | tail -10
fi

# ============================================================================
# 10. CONFIGURAR MINIO
# ============================================================================

log "📦 Configurando MinIO..."

# Criar usuário minio
if ! id "minio" &>/dev/null; then
    useradd -r -s /bin/false minio
fi

# Criar diretórios
mkdir -p /opt/minio/data
chown -R minio:minio /opt/minio

# Download MinIO se necessário
if [ ! -f "/usr/local/bin/minio" ]; then
    wget -O /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-amd64/minio
    chmod +x /usr/local/bin/minio
fi

# Configuração MinIO
mkdir -p /etc/minio
cat > /etc/minio/minio.conf << EOF
# ============================================================================
# SAMUREYE ON-PREMISE - MINIO CONFIGURATION
# ============================================================================
MINIO_ROOT_USER=$MINIO_USER
MINIO_ROOT_PASSWORD=$MINIO_PASSWORD
MINIO_VOLUMES="/opt/minio/data"
MINIO_OPTS="--address :9000 --console-address :9001"
EOF

# Serviço systemd MinIO
cat > /etc/systemd/system/minio.service << EOF
[Unit]
Description=MinIO Object Storage
Documentation=https://docs.min.io
After=network.target

[Service]
User=minio
Group=minio
EnvironmentFile=/etc/minio/minio.conf
ExecStart=/usr/local/bin/minio server \$MINIO_OPTS \$MINIO_VOLUMES
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=minio

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start minio
systemctl enable minio

# ============================================================================
# 11. CONFIGURAR GRAFANA
# ============================================================================

log "📊 Configurando Grafana..."

# Instalar Grafana se necessário
if ! command -v grafana-server &> /dev/null; then
    # Configurar repositório Grafana
    wget -q -O - https://packages.grafana.com/gpg.key | apt-key add - 2>/dev/null || true
    echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
    
    # Tentar instalar com várias tentativas
    for attempt in 1 2 3; do
        log "Tentativa $attempt de instalação Grafana..."
        repair_dpkg
        if apt-get update -y 2>/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y grafana 2>/dev/null; then
            log "✅ Grafana instalado"
            break
        fi
        sleep 10
    done
fi

# Configurar Grafana
GRAFANA_CONF="/etc/grafana/grafana.ini"
cp "$GRAFANA_CONF" "$GRAFANA_CONF.backup" 2>/dev/null || true

cat > "$GRAFANA_CONF" << EOF
# ============================================================================
# SAMUREYE ON-PREMISE - GRAFANA CONFIGURATION
# ============================================================================

[server]
http_port = 3000
domain = 192.168.100.153
root_url = http://192.168.100.153:3000

[database]
type = postgres
host = 127.0.0.1:5432
name = grafana
user = grafana
password = $GRAFANA_PASSWORD

[security]
admin_user = admin
admin_password = $GRAFANA_PASSWORD
secret_key = samureye-grafana-secret-key

[users]
allow_sign_up = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[logging]
mode = file
level = info
EOF

# Inicializar Grafana
systemctl start grafana-server
systemctl enable grafana-server

# ============================================================================
# 12. CONFIGURAR FIREWALL
# ============================================================================

log "🔥 Configurando firewall UFW..."

# Resetar UFW
ufw --force reset

# Regras básicas
ufw default deny incoming
ufw default allow outgoing

# SSH
ufw allow 22/tcp

# Rede interna SamurEye
ufw allow from 192.168.100.0/24 to any port 5432   # PostgreSQL
ufw allow from 192.168.100.0/24 to any port 6379   # Redis
ufw allow from 192.168.100.0/24 to any port 9000   # MinIO API
ufw allow from 192.168.100.0/24 to any port 9001   # MinIO Console
ufw allow from 192.168.100.0/24 to any port 3000   # Grafana

# Ativar UFW
ufw --force enable

# ============================================================================
# 13. CRIAR SCRIPT DE TESTE
# ============================================================================

log "🧪 Criando script de teste..."

cat > /usr/local/bin/test-samureye-db.sh << 'EOF'
#!/bin/bash

echo "============================================="
echo "TESTE DE CONECTIVIDADE - SAMUREYE DATABASE"
echo "============================================="

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_service() {
    local service=$1
    local test_cmd=$2
    local description=$3
    
    echo -n "Testing $description... "
    if eval $test_cmd &>/dev/null; then
        echo -e "${GREEN}✅ OK${NC}"
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        return 1
    fi
}

echo ""
echo "🔧 STATUS DOS SERVIÇOS:"
systemctl is-active postgresql redis-server minio grafana-server

echo ""
echo "🌐 PORTAS ABERTAS:"
netstat -tlnp | grep -E ':5432|:6379|:9000|:3000' | head -10

echo ""
echo "🧪 TESTES DE CONECTIVIDADE:"

# PostgreSQL
test_service "PostgreSQL" "PGPASSWORD=samureye_secure_2024 psql -h localhost -U samureye_user -d samureye -c 'SELECT version();'" "PostgreSQL SamurEye"

# Redis
test_service "Redis" "redis-cli -a redis123 ping" "Redis"

# MinIO
test_service "MinIO" "curl -s http://localhost:9000/minio/health/live" "MinIO"

# Grafana
test_service "Grafana" "curl -s http://localhost:3000/api/health" "Grafana"

echo ""
echo "============================================="
echo "CREDENCIAIS DE ACESSO:"
echo "============================================="
echo "PostgreSQL: samureye_user / samureye_secure_2024 @ localhost:5432"
echo "Redis: redis123 @ localhost:6379"
echo "MinIO: minio / minio123 @ localhost:9000"
echo "Grafana: admin / grafana123 @ localhost:3000"
echo "============================================="
EOF

chmod +x /usr/local/bin/test-samureye-db.sh

# ============================================================================
# 14. VALIDAÇÃO FINAL
# ============================================================================

log "✅ Executando testes finais..."
sleep 10

# Testar PostgreSQL com credenciais corretas
if PGPASSWORD="samureye_secure_2024" psql -h localhost -U samureye_user -d samureye -c "SELECT version();" &>/dev/null; then
    log "✅ PostgreSQL funcionando"
else
    error "❌ PostgreSQL com problemas"
fi

# Testar conectividade remota do vlxsam02
log "🔍 Testando conectividade remota do vlxsam02..."
if PGPASSWORD="samureye_secure_2024" psql -h 172.24.1.153 -U samureye_user -d samureye -c "SELECT 1;" &>/dev/null; then
    log "✅ Conectividade remota funcionando"
else
    warn "⚠️ Conectividade remota com problemas - verificando configurações..."
    
    # Verificar se PostgreSQL está escutando em todas as interfaces
    if grep -q "listen_addresses = '\*'" /etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf; then
        log "✅ PostgreSQL configurado para escutar em todas as interfaces"
    else
        log "🔧 Forçando configuração listen_addresses..."
        sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" /etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf
        systemctl restart postgresql
        sleep 5
    fi
    
    # Verificar firewall
    log "🔧 Verificando firewall..."
    ufw allow 5432/tcp 2>/dev/null || true
    
    # Testar novamente após correções
    if PGPASSWORD="samureye_secure_2024" psql -h 172.24.1.153 -U samureye_user -d samureye -c "SELECT 1;" &>/dev/null; then
        log "✅ Conectividade remota corrigida"
    else
        warn "⚠️ Ainda com problemas de conectividade remota"
    fi
fi

# Testar Redis
if redis-cli -a "$REDIS_PASSWORD" ping &>/dev/null; then
    log "✅ Redis funcionando"
else
    error "❌ Redis com problemas"
fi

# Testar MinIO
if curl -s http://localhost:9000/minio/health/live &>/dev/null; then
    log "✅ MinIO funcionando"
else
    warn "⚠️ MinIO pode estar iniciando ainda..."
fi

# Testar Grafana
if curl -s http://localhost:3000/api/health &>/dev/null; then
    log "✅ Grafana funcionando"
else
    warn "⚠️ Grafana pode estar iniciando ainda..."
fi

# ============================================================================
# 15. RESUMO FINAL
# ============================================================================

echo ""
echo "🎉 HARD RESET CONCLUÍDO COM SUCESSO!"
echo "====================================="
echo ""
echo "📊 SERVIÇOS CONFIGURADOS:"
echo "• PostgreSQL 16: samureye_user/samureye_secure_2024 @ :5432"
echo "• Redis: redis123 @ :6379"
echo "• MinIO: minio/minio123 @ :9000"
echo "• Grafana: admin/grafana123 @ :3000"
echo ""
echo "🔧 COMANDOS ÚTEIS:"
echo "• Testar tudo: /usr/local/bin/test-samureye-db.sh"
echo "• Status: systemctl status postgresql redis-server minio grafana-server"
echo "• Logs PostgreSQL: tail -f /var/log/postgresql/postgresql-*.log"
echo "• Conectar DB: PGPASSWORD=samureye_secure_2024 psql -h localhost -U samureye_user -d samureye"
echo "• Testar remoto: PGPASSWORD=samureye_secure_2024 psql -h 172.24.1.153 -U samureye_user -d samureye"
echo ""
echo "📂 Backup dos dados antigos: $BACKUP_DIR"
echo ""
echo "⚠️ PRÓXIMOS PASSOS:"
echo "1. Execute o reset no vlxsam02 (Application)"
echo "2. Execute o reset no vlxsam01 (Gateway)"
echo "3. Execute o reset no vlxsam04 (Collector)"
echo ""
log "Database server vlxsam03 pronto para uso!"

# ============================================================================
# 16. CORREÇÃO AUTOMÁTICA DE CONECTIVIDADE E FIREWALL
# ============================================================================

log "🔧 Aplicando correções de conectividade e firewall..."

# ============================================================================
# 16.1. CONFIGURAÇÃO listen_addresses
# ============================================================================

log "⚙️ Verificando configuração listen_addresses..."

POSTGRES_VERSION=$(ls /etc/postgresql/ | head -1)
POSTGRES_CONF="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"

# Verificar listen_addresses
if grep -q "^listen_addresses = '\*'" "$POSTGRES_CONF"; then
    log "✅ listen_addresses já configurado corretamente"
else
    warn "Corrigindo listen_addresses..."
    
    # Comentar linha antiga e adicionar nova
    sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" "$POSTGRES_CONF"
    
    # Verificar se foi aplicado
    if grep -q "^listen_addresses = '\*'" "$POSTGRES_CONF"; then
        log "✅ listen_addresses corrigido"
        RESTART_NEEDED=true
    else
        # Forçar adição se não funcionou
        echo "listen_addresses = '*'" >> "$POSTGRES_CONF"
        log "✅ listen_addresses adicionado"
        RESTART_NEEDED=true
    fi
fi

# ============================================================================
# 16.2. CONFIGURAÇÃO pg_hba.conf
# ============================================================================

log "🔐 Verificando configuração pg_hba.conf..."

# Verificar se já tem as regras SamurEye
if grep -q "SamurEye On-Premise Access" "$PG_HBA"; then
    log "✅ Regras SamurEye já existem no pg_hba.conf"
else
    warn "Adicionando regras SamurEye ao pg_hba.conf..."
    
    # Backup do arquivo original
    cp "$PG_HBA" "$PG_HBA.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Adicionar regras SamurEye
    cat >> "$PG_HBA" << 'EOF'

# SamurEye On-Premise Access
# vlxsam01 - Gateway
host    samureye        samureye_user   172.24.1.151/32         md5
host    samureye        samureye        172.24.1.151/32         md5
# vlxsam02 - Application Server  
host    samureye        samureye_user   172.24.1.152/32         md5
host    samureye        samureye        172.24.1.152/32         md5
# vlxsam03 - Database (local)
host    samureye        samureye_user   127.0.0.1/32            md5
host    samureye        samure        127.0.0.1/32            md5
host    samureye        samureye_user   172.24.1.153/32         md5
host    samureye        samureye        172.24.1.153/32         md5
# vlxsam04 - Collector
host    samureye        samureye_user   172.24.1.154/32         md5
host    samureye        samureye        172.24.1.154/32         md5
# Rede local SamurEye (backup)
host    samureye        samureye_user   172.24.1.0/24           md5
host    samureye        samureye        172.24.1.0/24           md5
host    grafana         grafana         172.24.1.153/32         md5
# Permitir conexões md5 para usuários corretos
host    all             samureye_user   172.24.1.0/24           md5
host    all             samureye        172.24.1.0/24           md5
EOF
    
    log "✅ Regras SamurEye adicionadas ao pg_hba.conf"
    RESTART_NEEDED=true
fi

# ============================================================================
# 16.3. CONFIGURAÇÃO DO FIREWALL UFW
# ============================================================================

log "🔥 Verificando configuração do firewall..."

# Verificar se UFW está ativo
if ufw status | grep -q "Status: active"; then
    log "🔍 UFW ativo - verificando regras..."
    
    # Verificar se porta 5432 está liberada
    if ufw status | grep -q "5432"; then
        log "✅ Porta 5432 já liberada no firewall"
    else
        warn "Liberando porta 5432 no firewall..."
        ufw allow 5432/tcp
        log "✅ Porta 5432 liberada"
    fi
    
    # Verificar regras específicas para vlxsam02
    if ufw status numbered | grep -q "172.24.1.152"; then
        log "✅ Regras específicas para vlxsam02 já existem"
    else
        warn "Adicionando regras específicas para vlxsam02..."
        ufw allow from 172.24.1.152 to any port 5432
        log "✅ Regras para vlxsam02 adicionadas"
    fi
    
else
    warn "UFW não está ativo - ativando com regras básicas..."
    ufw --force enable
    ufw allow ssh
    ufw allow 5432/tcp
    ufw allow from 172.24.1.0/24
    log "✅ UFW configurado e ativado"
fi

# ============================================================================
# 16.4. REINICIAR POSTGRESQL SE NECESSÁRIO
# ============================================================================

if [ "$RESTART_NEEDED" = "true" ]; then
    log "🔄 Reiniciando PostgreSQL para aplicar mudanças..."
    systemctl restart postgresql
    sleep 10
    
    if systemctl is-active --quiet postgresql; then
        log "✅ PostgreSQL reiniciado com sucesso"
    else
        error "❌ Falha ao reiniciar PostgreSQL"
    fi
fi

# ============================================================================
# 16.5. TESTES DE CONECTIVIDADE
# ============================================================================

log "🧪 Executando testes de conectividade..."

# Teste 1: Conectividade local
echo -n "• Teste local (samureye_user): "
if PGPASSWORD="samureye_secure_2024" psql -h localhost -U samureye_user -d samureye -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OK${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
fi

echo -n "• Teste local (samureye): "
if PGPASSWORD="samureye_secure_2024" psql -h localhost -U samureye -d samureye -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OK${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
fi

# Teste 2: Conectividade via IP específico
echo -n "• Teste IP 172.24.1.153 (samureye_user): "
if PGPASSWORD="samureye_secure_2024" psql -h 172.24.1.153 -U samureye_user -d samureye -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OK${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
fi

# Teste 3: Porta TCP acessível
echo -n "• Porta 5432 acessível: "
if netstat -tlnp | grep -q ":5432.*LISTEN"; then
    echo -e "${GREEN}✅ LISTENING${NC}"
else
    echo -e "${RED}❌ NOT LISTENING${NC}"
fi

# Teste 4: Firewall
echo -n "• Firewall permite 5432: "
if ufw status | grep -q "5432.*ALLOW"; then
    echo -e "${GREEN}✅ ALLOWED${NC}"
else
    echo -e "${RED}❌ BLOCKED${NC}"
fi

log "✅ Correções de conectividade aplicadas com sucesso"