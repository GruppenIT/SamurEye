#!/bin/bash

# ============================================================================
# SAMUREYE - INSTALAÇÃO vlxsam03 (DATABASE/SERVICES)
# ============================================================================
# 
# Servidor: vlxsam03 (172.24.1.153)
# Função: Infraestrutura de dados e serviços
# Stack: Redis + Grafana + MinIO (backup) + Scripts
# 
# Componentes:
# - Redis para cache e sessões
# - Grafana para monitoramento multi-tenant
# - MinIO local opcional para backup
# - Scripts de teste para Neon Database e Object Storage
# - Scripts de backup para dados locais
# 
# ============================================================================

set -e

# Configuração para modo não-interativo (OBRIGATÓRIO para reset automático)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export APT_LISTCHANGES_FRONTEND=none

# Configurar respostas automáticas para PostgreSQL
echo "postgresql-16 postgresql-16/remove_clusters boolean true" | debconf-set-selections
echo "postgresql-common postgresql-common/obsolete-major boolean true" | debconf-set-selections

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funções auxiliares
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

# Verificar se é executado como root
if [ "$EUID" -ne 0 ]; then
    error "Este script deve ser executado como root (sudo)"
fi

# Configurações
SERVER_IP="172.24.1.153"
DATA_DIR="/opt/data"
BACKUP_DIR="/opt/backup"
SCRIPTS_DIR="/opt/samureye/scripts"
CONFIG_DIR="/etc/samureye"

log "🚀 Iniciando instalação vlxsam03 - Database/Services Server"
log "Servidor: $SERVER_IP"
log "Data Directory: $DATA_DIR"

# ============================================================================
# 1. ATUALIZAÇÃO DO SISTEMA
# ============================================================================

log "📦 Atualizando sistema base..."

apt update && apt upgrade -y

# Instalar dependências essenciais
apt install -y \
    curl \
    wget \
    gnupg \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    jq \
    htop \
    iotop \
    netcat-openbsd \
    redis-tools \
    postgresql-client-16

log "Sistema base atualizado"

# ============================================================================
# 2. CONFIGURAÇÃO DE USUÁRIOS E DIRETÓRIOS
# ============================================================================

log "👤 Configurando usuários e diretórios..."

# Criar usuário samureye se não existir
if ! id "samureye" &>/dev/null; then
    useradd -r -s /bin/bash -d /home/samureye samureye
    mkdir -p /home/samureye
    chown samureye:samureye /home/samureye
fi

# Criar diretórios essenciais
mkdir -p "$DATA_DIR"/{redis,grafana,logs}
mkdir -p "$BACKUP_DIR"/{redis,configs,logs,neon}
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p /var/log/samureye

# Definir permissões gerais (MinIO será criado separadamente)
chown -R samureye:samureye "$DATA_DIR" "$BACKUP_DIR"
chown -R samureye:samureye /var/log/samureye
chmod 750 "$DATA_DIR" "$BACKUP_DIR"

# Criar diretórios específicos para Redis com permissões corretas
mkdir -p "$DATA_DIR/redis"
chown redis:redis "$DATA_DIR/redis"
chmod 750 "$DATA_DIR/redis"

# Criar arquivo de log do Redis se não existir
touch /var/log/samureye/redis.log
chown redis:redis /var/log/samureye/redis.log
chmod 640 /var/log/samureye/redis.log

log "Usuários e diretórios configurados"

# ============================================================================
# 3. INSTALAÇÃO E CONFIGURAÇÃO REDIS
# ============================================================================

log "🔴 Instalando Redis..."

# Instalar Redis
apt install -y redis-server

# Parar Redis se estiver rodando para configuração limpa
systemctl stop redis-server 2>/dev/null || true
pkill redis-server 2>/dev/null || true
sleep 2

# Usar diretórios padrão Redis (evita problemas AppArmor Ubuntu 24.04)
mkdir -p /var/lib/redis
mkdir -p /var/log/redis
chown redis:redis /var/lib/redis
chown redis:redis /var/log/redis
chmod 750 /var/lib/redis
chmod 750 /var/log/redis

# Configuração Redis compatível com Ubuntu 24.04 (igual à solução manual testada)
cat > /etc/redis/redis.conf << 'EOF'
bind 0.0.0.0
port 6379
protected-mode yes
requirepass SamurEye2024Redis!
maxmemory 2gb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
loglevel notice
logfile /var/log/redis/redis-server.log
timeout 0
tcp-keepalive 300
maxclients 1000
daemonize no
supervised systemd
EOF

# Garantir permissões na configuração
chown redis:redis /etc/redis/redis.conf
chmod 640 /etc/redis/redis.conf

# Recarregar systemd e iniciar Redis (sem override problemático)
systemctl daemon-reload
systemctl enable redis-server
systemctl start redis-server

# Aguardar inicialização
sleep 3

# Verificar se Redis iniciou corretamente
if ! systemctl is-active --quiet redis-server; then
    error "Falha ao iniciar o Redis. Verifique os logs: journalctl -xeu redis-server.service"
fi

# Teste de conectividade
if redis-cli -h 127.0.0.1 -a SamurEye2024Redis! ping | grep -q PONG; then
    log "✅ Redis configurado e testado com sucesso"
else
    warn "⚠️ Redis iniciou mas conexão com senha falhou"
fi

log "Redis configurado e iniciado"

# ============================================================================
# 4. INSTALAÇÃO E CONFIGURAÇÃO POSTGRESQL
# ============================================================================

log "🐘 Instalando PostgreSQL 16..."

# DEBUG: Verificar se PostgreSQL já está instalado e funcionando
log "🔍 DEBUG: Verificando estado atual do PostgreSQL..."
if command -v pg_lsclusters >/dev/null 2>&1; then
    log "🔍 DEBUG: pg_lsclusters encontrado - verificando saída:"
    pg_lsclusters_output=$(pg_lsclusters 2>&1)
    log "🔍 DEBUG: Saída pg_lsclusters: $pg_lsclusters_output"
    
    # Verificar se há clusters corrompidos
    if echo "$pg_lsclusters_output" | grep -q "Invalid data directory\|Use of uninitialized value"; then
        warn "🧹 DEBUG: Cluster PostgreSQL corrompido detectado - executando limpeza completa..."
        
        # Parar serviços
        systemctl stop postgresql 2>/dev/null || true
        systemctl disable postgresql 2>/dev/null || true
        
        # Remover cluster corrompido ANTES da desinstalação
        pg_dropcluster --stop 16 main 2>/dev/null || true
        
        # Purgar completamente
        apt-get purge postgresql-16 postgresql-common postgresql-client-16 postgresql-client-common postgresql-contrib -y
        apt-get autoremove --purge -y
        
        # Limpeza de diretórios
        rm -rf /var/lib/postgresql/ /etc/postgresql/ /var/log/postgresql/ /run/postgresql/
        userdel postgres 2>/dev/null || true
        groupdel postgres 2>/dev/null || true
        
        log "✅ Cluster corrompido removido"
    else
        log "🔍 DEBUG: Clusters parecem OK - verificando se PostgreSQL está funcionando..."
        
        # DEBUG: Verificar status do serviço
        if systemctl is-active --quiet postgresql; then
            log "🔍 DEBUG: Serviço PostgreSQL está ATIVO"
        else
            log "🔍 DEBUG: Serviço PostgreSQL está INATIVO"
        fi
        
        # DEBUG: Tentar conexão
        if sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
            log "🔍 DEBUG: Conexão PostgreSQL funcionando"
            connection_ok=true
        else
            log "🔍 DEBUG: Conexão PostgreSQL falhando"
            connection_ok=false
        fi
        
        # PostgreSQL existe e está funcionando - verificar se precisa reinstalar
        if systemctl is-active --quiet postgresql && [ "$connection_ok" = "true" ]; then
            log "🔍 DEBUG: PostgreSQL já instalado e funcionando - pulando instalação"
            # Pular para próxima seção
            jump_to_database_config=true
        else
            warn "🔄 DEBUG: PostgreSQL instalado mas não funcionando - reinstalando..."
            log "🔍 DEBUG: Status serviço: $(systemctl is-active postgresql)"
            log "🔍 DEBUG: Status conexão: $connection_ok"
            # Fazer reinstalação limpa
            systemctl stop postgresql 2>/dev/null || true
            apt-get purge postgresql-16 postgresql-common postgresql-client-16 postgresql-client-common postgresql-contrib -y
            apt-get autoremove --purge -y
            rm -rf /var/lib/postgresql/ /etc/postgresql/ /var/log/postgresql/ /run/postgresql/
            userdel postgres 2>/dev/null || true
            groupdel postgres 2>/dev/null || true
        fi
    fi
else
    log "🔍 Nenhum PostgreSQL detectado - instalação limpa"
fi

# Instalar apenas se necessário
if [ "$jump_to_database_config" != "true" ]; then
    # Instalar PostgreSQL 16 em ambiente completamente limpo
    log "📦 DEBUG: Instalando PostgreSQL 16 em ambiente limpo..."
    apt-get update
    apt install -y postgresql-16 postgresql-contrib
    log "📦 DEBUG: Instalação de pacotes concluída"

    # DEBUG: Verificar se serviço foi criado
    if systemctl list-unit-files | grep -q postgresql.service; then
        log "📦 DEBUG: Serviço postgresql.service encontrado"
    else
        log "📦 DEBUG: ERRO - Serviço postgresql.service NÃO encontrado"
    fi

    # Iniciar e habilitar PostgreSQL
    log "📦 DEBUG: Iniciando serviço PostgreSQL..."
    systemctl start postgresql
    log "📦 DEBUG: Comando start executado - status: $?"
    
    log "📦 DEBUG: Habilitando serviço PostgreSQL..."
    systemctl enable postgresql
    log "📦 DEBUG: Comando enable executado - status: $?"
    
    log "📦 DEBUG: Aguardando 5 segundos..."
    sleep 5

    # DEBUG: Verificar status detalhado
    log "📦 DEBUG: Status detalhado do PostgreSQL:"
    systemctl status postgresql --no-pager || true
    
    # Verificar se PostgreSQL iniciou corretamente
    if systemctl is-active --quiet postgresql; then
        log "📦 DEBUG: Serviço PostgreSQL está ATIVO após instalação"
    else
        log "📦 DEBUG: ERRO - Serviço PostgreSQL está INATIVO após instalação"
        log "📦 DEBUG: Tentando restart..."
        systemctl restart postgresql
        sleep 3
        if systemctl is-active --quiet postgresql; then
            log "📦 DEBUG: Serviço PostgreSQL ATIVO após restart"
        else
            log "📦 DEBUG: ERRO CRÍTICO - PostgreSQL não inicia nem após restart"
            error "❌ Falha ao iniciar PostgreSQL após instalação"
        fi
    fi

    # DEBUG: Verificar se usuário postgres existe
    if id postgres >/dev/null 2>&1; then
        log "📦 DEBUG: Usuário postgres existe"
    else
        log "📦 DEBUG: ERRO - Usuário postgres NÃO existe"
    fi

    # Verificar conexão PostgreSQL
    log "📦 DEBUG: Testando conexão PostgreSQL..."
    if sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
        log "📦 DEBUG: Conexão PostgreSQL funcionando"
    else
        log "📦 DEBUG: ERRO - Conexão PostgreSQL falhando"
        log "📦 DEBUG: Tentando diagnóstico de conexão..."
        sudo -u postgres psql -c "SELECT version();" 2>&1 || true
        error "❌ Falha de conexão PostgreSQL - instalação corrompida"
    fi

    log "✅ DEBUG: PostgreSQL configurado e iniciado com sucesso"
fi

# Criar usuário samureye e banco de dados (com reset automático)
log "🗄️ DEBUG: Configurando usuário e banco de dados..."

# DEBUG: Verificar se PostgreSQL ainda está funcionando
if systemctl is-active --quiet postgresql; then
    log "🗄️ DEBUG: PostgreSQL ainda ativo antes da configuração do banco"
else
    log "🗄️ DEBUG: ERRO - PostgreSQL não está ativo antes da configuração do banco"
    systemctl status postgresql --no-pager || true
fi

# DEBUG: Teste de conexão antes da configuração
if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
    log "🗄️ DEBUG: Conexão PostgreSQL OK antes da configuração do banco"
else
    log "🗄️ DEBUG: ERRO - Conexão PostgreSQL falhou antes da configuração do banco"
    error "❌ PostgreSQL não está funcionando antes da configuração do banco"
fi

# Função de reset do banco (para funcionar como reset completo do servidor)
log "🗄️ DEBUG: Executando comandos SQL para configurar banco..."
sudo -u postgres psql << 'EOF'
-- Finalizar conexões existentes ao banco samureye_db se existir
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'samureye_db' AND pid <> pg_backend_pid();

-- Dropar banco se existir (reset completo)
DROP DATABASE IF EXISTS samureye_db;

-- Dropar e recriar usuário (reset completo)
DROP ROLE IF EXISTS samureye;
CREATE ROLE samureye WITH LOGIN PASSWORD 'SamurEye2024DB!' CREATEDB;

-- Criar banco novamente
CREATE DATABASE samureye_db OWNER samureye;
GRANT ALL PRIVILEGES ON DATABASE samureye_db TO samureye;
EOF

# Conectar ao banco samureye_db e ativar extensões
sudo -u postgres psql -d samureye_db << 'EOF'
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT ALL ON SCHEMA public TO samureye;
EOF

log "🗄️ DEBUG: Comandos SQL executados - verificando se PostgreSQL ainda funciona..."

# DEBUG: Verificação final
if systemctl is-active --quiet postgresql; then
    log "🗄️ DEBUG: PostgreSQL ainda ativo após configuração do banco"
else
    log "🗄️ DEBUG: ERRO CRÍTICO - PostgreSQL parou após configuração do banco"
    systemctl status postgresql --no-pager || true
fi

if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
    log "🗄️ DEBUG: Conexão PostgreSQL ainda funcionando após configuração"
else
    log "🗄️ DEBUG: ERRO CRÍTICO - Conexão PostgreSQL falhou após configuração"
fi

log "✅ DEBUG: PostgreSQL configurado com sucesso"

# Criar script SQL do schema
cat > /tmp/samureye_schema.sql << 'SCHEMA_EOF'
-- SamurEye Database Schema
-- Generated from shared/schema.ts

-- Enums
CREATE TYPE global_role AS ENUM ('global_admin', 'global_auditor');
CREATE TYPE tenant_role AS ENUM ('tenant_admin', 'operator', 'viewer', 'tenant_auditor');
CREATE TYPE collector_status AS ENUM ('online', 'offline', 'enrolling', 'error');
CREATE TYPE journey_type AS ENUM ('attack_surface', 'ad_hygiene', 'edr_testing');
CREATE TYPE journey_status AS ENUM ('pending', 'running', 'completed', 'failed', 'cancelled');
CREATE TYPE credential_type AS ENUM ('ssh', 'snmp', 'telnet', 'ldap', 'wmi', 'http', 'https', 'database', 'api_key', 'certificate');

-- Sessions table (mandatory for auth)
CREATE TABLE IF NOT EXISTS sessions (
    sid VARCHAR PRIMARY KEY,
    sess JSONB NOT NULL,
    expire TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS "IDX_session_expire" ON sessions(expire);

-- Users table (Replit Auth + local auth)
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR UNIQUE,
    first_name VARCHAR,
    last_name VARCHAR,
    profile_image_url VARCHAR,
    password VARCHAR,
    current_tenant_id VARCHAR,
    preferred_language VARCHAR DEFAULT 'pt-BR',
    global_role global_role,
    is_global_user BOOLEAN DEFAULT false,
    is_soc_user BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Tenants table
CREATE TABLE IF NOT EXISTS tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    slug VARCHAR UNIQUE NOT NULL,
    description TEXT,
    logo_url VARCHAR,
    settings JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Tenant users (many-to-many with roles)
CREATE TABLE IF NOT EXISTS tenant_users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role tenant_role NOT NULL DEFAULT 'viewer',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Collectors
CREATE TABLE IF NOT EXISTS collectors (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    hostname VARCHAR,
    ip_address VARCHAR,
    status collector_status NOT NULL DEFAULT 'offline',
    version VARCHAR,
    last_seen TIMESTAMP,
    enrollment_token VARCHAR,
    enrollment_token_expires TIMESTAMP,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Collector telemetry
CREATE TABLE IF NOT EXISTS collector_telemetry (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    collector_id VARCHAR NOT NULL REFERENCES collectors(id) ON DELETE CASCADE,
    cpu_usage REAL,
    memory_usage REAL,
    disk_usage REAL,
    network_throughput JSONB,
    processes JSONB,
    timestamp TIMESTAMP DEFAULT NOW()
);

-- Journeys
CREATE TABLE IF NOT EXISTS journeys (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    type journey_type NOT NULL,
    status journey_status NOT NULL DEFAULT 'pending',
    config JSONB NOT NULL,
    results JSONB,
    collector_id VARCHAR REFERENCES collectors(id),
    created_by VARCHAR NOT NULL REFERENCES users(id),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Credentials
CREATE TABLE IF NOT EXISTS credentials (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    type credential_type NOT NULL,
    description TEXT,
    credential_data JSONB NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_by VARCHAR NOT NULL REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Threat Intelligence
CREATE TABLE IF NOT EXISTS threat_intelligence (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    type VARCHAR NOT NULL,
    source VARCHAR NOT NULL,
    severity VARCHAR NOT NULL,
    title VARCHAR NOT NULL,
    description TEXT,
    data JSONB,
    score INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- System Settings
CREATE TABLE IF NOT EXISTS system_settings (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR NOT NULL,
    value TEXT,
    description TEXT,
    system_name VARCHAR DEFAULT 'SamurEye',
    system_description TEXT,
    support_email VARCHAR,
    logo_url VARCHAR,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Tenant User Auth (for local MFA)
CREATE TABLE IF NOT EXISTS tenant_user_auth (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_user_id VARCHAR NOT NULL REFERENCES tenant_users(id) ON DELETE CASCADE,
    username VARCHAR NOT NULL,
    password_hash VARCHAR,
    totp_secret VARCHAR,
    email_verified BOOLEAN DEFAULT false,
    last_login TIMESTAMP,
    login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Activities/Audit Log
CREATE TABLE IF NOT EXISTS activities (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR REFERENCES tenants(id) ON DELETE CASCADE,
    user_id VARCHAR NOT NULL REFERENCES users(id),
    action VARCHAR NOT NULL,
    resource VARCHAR NOT NULL,
    resource_id VARCHAR,
    metadata JSONB,
    ip_address VARCHAR,
    user_agent VARCHAR,
    timestamp TIMESTAMP DEFAULT NOW()
);

-- Insert initial system settings
INSERT INTO system_settings (key, value, description, system_name, system_description) 
VALUES 
    ('app_version', '1.0.0', 'Current application version', 'SamurEye', 'Breach & Attack Simulation Platform'),
    ('maintenance_mode', 'false', 'System maintenance mode', 'SamurEye', 'Breach & Attack Simulation Platform')
ON CONFLICT DO NOTHING;

-- Create initial admin tenant
INSERT INTO tenants (id, name, slug, description, is_active)
VALUES ('admin-tenant-id', 'Admin Organization', 'admin-org', 'Default administrative organization', true)
ON CONFLICT DO NOTHING;

SCHEMA_EOF

# Executar schema no banco
log "🗄️ Criando estrutura do banco de dados..."
sudo -u postgres psql -d samureye_db -f /tmp/samureye_schema.sql

# Configurar permissões finais
sudo -u postgres psql -d samureye_db << EOF
-- Garantir que o usuário samureye tem acesso total às tabelas
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO samureye;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO samureye;
GRANT USAGE ON SCHEMA public TO samureye;

-- Configurar privilégios padrão para futuras tabelas
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO samureye;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO samureye;
EOF

# Configurar PostgreSQL para aceitar conexões
cat > /etc/postgresql/16/main/postgresql.conf << 'PGCONF_EOF'
# SamurEye PostgreSQL Configuration
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

# Logging
log_destination = 'stderr,csvlog'
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on

# Extensions
shared_preload_libraries = 'pg_stat_statements'
PGCONF_EOF

# Configurar autenticação
cat > /etc/postgresql/16/main/pg_hba.conf << 'PGHBA_EOF'
# SamurEye PostgreSQL Authentication Configuration
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                md5
local   all             samureye                                md5
local   samureye_db     samureye                                md5

# IPv4 local connections
host    all             postgres        127.0.0.1/32            md5
host    samureye_db     samureye        127.0.0.1/32            md5

# IPv4 internal network connections (for other vlxsam servers)
host    samureye_db     samureye        172.24.1.0/24           md5
host    samureye_db     samureye        192.168.100.0/24        md5

# IPv6 local connections
host    all             all             ::1/128                 md5

# Replication connections
local   replication     postgres                                md5
host    replication     postgres        127.0.0.1/32            md5
host    replication     postgres        ::1/128                 md5
PGHBA_EOF

# Reiniciar PostgreSQL com nova configuração
systemctl restart postgresql
sleep 5

# Verificar se PostgreSQL está rodando
if systemctl is-active --quiet postgresql; then
    log "✅ PostgreSQL configurado e iniciado com sucesso"
else
    error "❌ Falha ao iniciar PostgreSQL"
fi

# Testar conexão PostgreSQL com detecção automática de ambiente
log "🔍 Testando conectividade PostgreSQL..."

# Tentar conexão local via postgres user primeiro (padrão vlxsam03)
if sudo -u postgres psql -d samureye_db -c "SELECT version();" > /dev/null 2>&1; then
    log "✅ Teste de conexão PostgreSQL local bem-sucedido"
    POSTGRES_TYPE="local"
elif PGPASSWORD="SamurEye2024DB!" psql -h 127.0.0.1 -U samureye -d samureye_db -c "SELECT version();" > /dev/null 2>&1; then
    log "✅ Teste de conexão PostgreSQL via IP bem-sucedido"
    POSTGRES_TYPE="network"
elif PGPASSWORD="SamurEye2024DB!" psql -h 172.24.1.153 -U samureye -d samureye_db -c "SELECT version();" > /dev/null 2>&1; then
    log "✅ Teste de conexão PostgreSQL vlxsam03 bem-sucedido"
    POSTGRES_TYPE="vlxsam03"
else
    warn "⚠️ Problema na conexão PostgreSQL - todas as tentativas falharam"
    POSTGRES_TYPE="failed"
fi

# Limpar arquivo temporário
rm -f /tmp/samureye_schema.sql

log "PostgreSQL configurado e banco samureye_db criado"

# ============================================================================
# 5. INSTALAÇÃO E CONFIGURAÇÃO GRAFANA
# ============================================================================

log "📊 Instalando Grafana..."

# Adicionar repositório Grafana
curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list

apt update
apt install -y grafana

# Configuração Grafana
cat > /etc/grafana/grafana.ini << 'EOF'
[server]
http_addr = 0.0.0.0
http_port = 3000
domain = 172.24.1.153
root_url = http://172.24.1.153:3000/

[database]
type = sqlite3
path = /opt/data/grafana/grafana.db

[security]
admin_user = admin
admin_password = SamurEye2024!
secret_key = SamurEyeGrafanaSecret2024
disable_gravatar = true

[auth.anonymous]
enabled = false

[log]
mode = file
level = info
file = /var/log/samureye/grafana.log

[paths]
data = /opt/data/grafana
logs = /var/log/samureye
plugins = /opt/data/grafana/plugins
provisioning = /etc/grafana/provisioning

[dashboards]
default_home_dashboard_path = /opt/data/grafana/dashboards/samureye-overview.json
EOF

# Parar Grafana completamente e resetar estado
systemctl stop grafana-server || true
systemctl disable grafana-server || true
systemctl reset-failed grafana-server || true

# Matar qualquer processo Grafana residual
pkill -f grafana-server || true
sleep 3

# Limpar possível PID file residual e dados problemáticos
rm -f /var/run/grafana/grafana-server.pid
rm -f /var/lib/grafana/grafana.db.lock || true
sleep 5

# Limpar logs antigos problemáticos
rm -f /var/log/samureye/grafana.log
touch /var/log/samureye/grafana.log

# Definir permissões Grafana corretamente
chown -R grafana:grafana /opt/data/grafana
chmod -R 755 /opt/data/grafana
chown grafana:grafana /var/log/samureye/grafana.log
chmod 644 /var/log/samureye/grafana.log

# Verificar se diretório está acessível
if ! sudo -u grafana test -w /opt/data/grafana; then
    warn "Grafana não consegue escrever em /opt/data/grafana, usando configuração padrão"
    
    # Usar diretório padrão do Grafana se houver problemas
    cat > /etc/grafana/grafana.ini << 'EOF'
[server]
http_addr = 0.0.0.0
http_port = 3000
domain = 172.24.1.153

[database]
type = sqlite3
path = /var/lib/grafana/grafana.db

[security]
admin_user = admin
admin_password = SamurEye2024!
secret_key = SamurEyeGrafanaSecret2024
disable_gravatar = true

[auth.anonymous]
enabled = false

[log]
mode = file
level = info
EOF
    
    log "Usando configuração padrão do Grafana"
else
    log "Diretório Grafana acessível, usando configuração personalizada"
fi

# Reabilitar e reiniciar Grafana com delay adequado
systemctl daemon-reload

# Reset completo de qualquer estado de falha
systemctl reset-failed grafana-server || true
sleep 2

systemctl enable grafana-server

log "Iniciando Grafana (aguarde 15 segundos)..."
systemctl start grafana-server
sleep 15

# Verificar Grafana com mais tempo
if systemctl is-active --quiet grafana-server; then
    log "✅ Grafana configurado e iniciado com sucesso"
else
    warn "⚠️ Problema persistente com Grafana. Logs detalhados:"
    journalctl -u grafana-server --no-pager --lines=10 || true
    
    # Tentar iniciar uma vez mais
    log "Tentando reiniciar Grafana..."
    systemctl restart grafana-server
    sleep 5
    
    if systemctl is-active --quiet grafana-server; then
        log "✅ Grafana iniciado na segunda tentativa"
    else
        warn "⚠️ Grafana precisa de configuração manual"
    fi
fi

# ============================================================================
# 6. INSTALAÇÃO MINIO (OPCIONAL - BACKUP LOCAL)
# ============================================================================

log "🗄️ Instalando MinIO (backup local)..."

# Parar MinIO completamente antes de atualizar binário
systemctl stop minio || true
systemctl disable minio || true

# Matar qualquer processo MinIO residual
pkill -f minio || true
sleep 5

# Aguardar possível flush de I/O
sync
sleep 2

# Remover binário antigo se existir
rm -f /usr/local/bin/minio

# Download e instalação MinIO
wget -O /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x /usr/local/bin/minio

# Criar usuário minio se não existir (sem home directory específico primeiro)
if ! id "minio" &>/dev/null; then
    useradd -r -s /bin/bash minio
fi

# Limpar diretório MinIO antigo se existir
if [ -d "/opt/data/minio" ]; then
    rm -rf /opt/data/minio
fi
if [ -d "/var/lib/minio" ]; then
    rm -rf /var/lib/minio
fi

# Estratégia diferente para MinIO - usar diretório mais simples
mkdir -p /var/lib/minio
chown -R minio:minio /var/lib/minio
chmod -R 755 /var/lib/minio

# Definir home directory
usermod -d /var/lib/minio minio 2>/dev/null || true

# Criar estrutura básica do MinIO
sudo -u minio mkdir -p /var/lib/minio/{data,config} 2>/dev/null || true
echo "Created MinIO structure in /var/lib/minio"

# Verificar estrutura
log "Estrutura MinIO criada:"
ls -la /var/lib/minio/ 2>/dev/null || log "Diretório MinIO não acessível"
log "✅ Diretório MinIO configurado"

# Configurar MinIO
mkdir -p /etc/default
cat > /etc/default/minio << 'EOF'
# MinIO configuration for SamurEye backup
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=SamurEye2024!
MINIO_VOLUMES=/var/lib/minio/data
MINIO_OPTS="--console-address :9001"
MINIO_SERVER_URL=http://172.24.1.153:9000
EOF

# Testar se MinIO consegue acessar o diretório
log "Testando acesso MinIO ao diretório..."
sudo -u minio /usr/local/bin/minio server --help > /dev/null 2>&1 || {
    error "MinIO binary não funciona corretamente"
}

# Verificar se diretório é válido para MinIO
if [ ! -d "/var/lib/minio/data" ] || [ ! -w "/var/lib/minio/data" ]; then
    error "Diretório MinIO não está acessível"
fi

# Systemd service para MinIO (simplificado para debug)
cat > /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO Object Storage
After=network.target
Wants=network.target

[Service]
Type=exec
User=minio
Group=minio
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server --console-address :9001 /var/lib/minio/data
TimeoutStopSec=30
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security (relaxada para debug)
NoNewPrivileges=false
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF

# Inicializar MinIO com verificações
systemctl daemon-reload
systemctl enable minio

# Aguardar e tentar iniciar MinIO
log "Iniciando MinIO..."
sleep 2
systemctl start minio

# Aguardar inicialização do MinIO
sleep 5

# Verificar se MinIO iniciou corretamente
if systemctl is-active --quiet minio; then
    log "✅ MinIO configurado e iniciado com sucesso"
else
    warn "⚠️ MinIO não iniciou corretamente. Verificando logs..."
    # Mostrar erro mas não falhar o script, pois MinIO é opcional
    journalctl -u minio.service --no-pager --lines=3 || true
    log "⚠️ MinIO será configurado como opcional (pode ser corrigido manualmente se necessário)"
fi

# ============================================================================
# 6. CONFIGURAÇÃO DE ENVIRONMENT
# ============================================================================

log "🔧 Configurando variáveis de ambiente..."

# Arquivo de configuração principal
cat > "$CONFIG_DIR/.env" << 'EOF'
# SamurEye vlxsam03 Configuration
# Database and Services Server

# Server Info
VLXSAM03_IP=172.24.1.153
NODE_ENV=production

# PostgreSQL Database (auto-detected connection)
# Priority: 1. Local postgres user, 2. localhost, 3. vlxsam03 IP
DATABASE_URL=postgresql://samureye:SamurEye2024DB!@127.0.0.1:5432/samureye_db?sslmode=disable
PGDATABASE=samureye_db
PGHOST=127.0.0.1
PGPORT=5432
PGUSER=samureye
PGPASSWORD=SamurEye2024DB!

# Alternative connection strings for fallback
DATABASE_URL_VLXSAM03=postgresql://samureye:SamurEye2024DB!@172.24.1.153:5432/samureye_db?sslmode=disable
DATABASE_URL_LOCAL=postgresql://samureye:SamurEye2024DB!@127.0.0.1:5432/samureye_db?sslmode=disable

# Redis Configuration  
REDIS_HOST=172.24.1.153
REDIS_PORT=6379
REDIS_PASSWORD=SamurEye2024Redis!
REDIS_URL=redis://:SamurEye2024Redis!@172.24.1.153:6379
REDIS_DATA_DIR=/var/lib/redis
REDIS_LOG_FILE=/var/log/redis/redis-server.log

# Object Storage (Google Cloud Storage)
# Configurado automaticamente no vlxsam02 via object storage setup
PUBLIC_OBJECT_SEARCH_PATHS=/repl-default-bucket-xyz/public
PRIVATE_OBJECT_DIR=/repl-default-bucket-xyz/.private
DEFAULT_OBJECT_STORAGE_BUCKET_ID=repl-default-bucket-xyz

# MinIO Local (Backup)
MINIO_HOST=172.24.1.153
MINIO_PORT=9000
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=SamurEye2024!
MINIO_URL=http://172.24.1.153:9000

# Grafana
GRAFANA_URL=http://172.24.1.153:3000
GRAFANA_USER=admin
GRAFANA_PASSWORD=SamurEye2024!

# Monitoring
GRAFANA_DATASOURCE_URL=http://172.24.1.153:6379
GRAFANA_REDIS_URL=redis://:SamurEye2024Redis!@172.24.1.153:6379

# Backup Settings
BACKUP_RETENTION_DAYS=30
BACKUP_DIR=/opt/backup
EOF

chmod 640 "$CONFIG_DIR/.env"
chown root:samureye "$CONFIG_DIR/.env"

log "Configuração de ambiente criada"

# ============================================================================
# 7. SCRIPTS DE TESTE E MONITORAMENTO
# ============================================================================

log "📝 Criando scripts de teste..."

# Script de teste Neon Database
cat > "$SCRIPTS_DIR/test-neon-connection.sh" << 'EOF'
#!/bin/bash

# Teste de conectividade Neon Database

source /etc/samureye/.env

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[$(date '+%H:%M:%S')] ERROR: $1"; exit 1; }

log "🧪 Testando conectividade Neon Database..."

if [ -z "$DATABASE_URL" ]; then
    error "DATABASE_URL não configurada"
fi

# Teste básico de conectividade
log "Testando conexão básica..."
if psql "$DATABASE_URL" -c "SELECT version();" >/dev/null 2>&1; then
    log "✅ Conexão Neon Database: OK"
    
    # Teste de latência
    start_time=$(date +%s%N)
    psql "$DATABASE_URL" -c "SELECT 1;" >/dev/null 2>&1
    end_time=$(date +%s%N)
    latency=$(( (end_time - start_time) / 1000000 ))
    
    log "⚡ Latência: ${latency}ms"
    
    # Teste de tabelas
    table_count=$(psql "$DATABASE_URL" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs)
    log "📊 Tabelas encontradas: $table_count"
    
else
    error "❌ Falha na conexão Neon Database"
fi

log "Teste Neon Database concluído"
EOF

# Script de teste PostgreSQL com detecção automática
cat > "$SCRIPTS_DIR/test-postgres-connection.sh" << 'EOF'
#!/bin/bash

# Teste de conectividade PostgreSQL com detecção automática de ambiente

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[$(date '+%H:%M:%S')] ERROR: $1"; exit 1; }

log "🐘 Testando conectividade PostgreSQL..."

# Função para testar tabelas e estrutura
test_database_structure() {
    local conn_cmd="$1"
    
    # Teste de tabelas
    table_count=$($conn_cmd -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs)
    log "📊 Tabelas encontradas: $table_count"
    
    # Verificar algumas tabelas específicas
    log "🔍 Verificando estrutura do banco..."
    
    # Verificar tabela de usuários
    if $conn_cmd -c "\d users" >/dev/null 2>&1; then
        log "✅ Tabela 'users': OK"
    else
        log "⚠️ Tabela 'users': não encontrada"
    fi
    
    # Verificar tabela de tenants
    if $conn_cmd -c "\d tenants" >/dev/null 2>&1; then
        log "✅ Tabela 'tenants': OK"
    else
        log "⚠️ Tabela 'tenants': não encontrada"
    fi
    
    # Verificar tabela de collectors
    if $conn_cmd -c "\d collectors" >/dev/null 2>&1; then
        log "✅ Tabela 'collectors': OK"
    else
        log "⚠️ Tabela 'collectors': não encontrada"
    fi
    
    # Verificar extensões
    log "🔧 Verificando extensões..."
    ext_uuid=$($conn_cmd -t -c "SELECT count(*) FROM pg_extension WHERE extname = 'uuid-ossp';" 2>/dev/null | xargs)
    if [ "$ext_uuid" = "1" ]; then
        log "✅ Extensão 'uuid-ossp': instalada"
    else
        log "⚠️ Extensão 'uuid-ossp': não instalada"
    fi
}

# Teste básico de conectividade com detecção automática
log "Testando conexão com banco samureye_db..."

# Tentar conexão local via postgres user primeiro (padrão vlxsam03)
if sudo -u postgres psql -d samureye_db -c "SELECT version();" >/dev/null 2>&1; then
    log "✅ Conexão PostgreSQL local via postgres user: OK"
    
    # Teste de latência
    start_time=$(date +%s%N)
    sudo -u postgres psql -d samureye_db -c "SELECT 1;" >/dev/null 2>&1
    end_time=$(date +%s%N)
    latency=$(( (end_time - start_time) / 1000000 ))
    
    log "⚡ Latência local: ${latency}ms"
    
    # Testar estrutura do banco
    test_database_structure "sudo -u postgres psql -d samureye_db"
    
elif PGPASSWORD="SamurEye2024DB!" psql -h 127.0.0.1 -U samureye -d samureye_db -c "SELECT version();" >/dev/null 2>&1; then
    log "✅ Conexão PostgreSQL via localhost: OK"
    
    # Teste de latência
    start_time=$(date +%s%N)
    PGPASSWORD="SamurEye2024DB!" psql -h 127.0.0.1 -U samureye -d samureye_db -c "SELECT 1;" >/dev/null 2>&1
    end_time=$(date +%s%N)
    latency=$(( (end_time - start_time) / 1000000 ))
    
    log "⚡ Latência localhost: ${latency}ms"
    
    # Testar estrutura do banco
    test_database_structure "PGPASSWORD=SamurEye2024DB! psql -h 127.0.0.1 -U samureye -d samureye_db"
    
elif PGPASSWORD="SamurEye2024DB!" psql -h 172.24.1.153 -U samureye -d samureye_db -c "SELECT version();" >/dev/null 2>&1; then
    log "✅ Conexão PostgreSQL via vlxsam03: OK"
    
    # Teste de latência
    start_time=$(date +%s%N)
    PGPASSWORD="SamurEye2024DB!" psql -h 172.24.1.153 -U samureye -d samureye_db -c "SELECT 1;" >/dev/null 2>&1
    end_time=$(date +%s%N)
    latency=$(( (end_time - start_time) / 1000000 ))
    
    log "⚡ Latência vlxsam03: ${latency}ms"
    
    # Testar estrutura do banco
    test_database_structure "PGPASSWORD=SamurEye2024DB! psql -h 172.24.1.153 -U samureye -d samureye_db"
    
else
    error "❌ Falha na conexão PostgreSQL - todas as tentativas falharam"
fi

log "Teste PostgreSQL concluído"
EOF

# Script de reset automático PostgreSQL para casos emergenciais
cat > "$SCRIPTS_DIR/reset-postgres.sh" << 'EOF'
#!/bin/bash

# Script de reset automático PostgreSQL - para casos emergenciais
# Este script corrige problemas de cluster e recria tudo do zero

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[$(date '+%H:%M:%S')] ERROR: $1"; exit 1; }

log "🔄 Iniciando reset completo PostgreSQL..."

# Parar PostgreSQL
systemctl stop postgresql 2>/dev/null || true
sleep 2

# Detectar problemas específicos de cluster
cluster_has_issues() {
    # Verificar se há erro de data directory
    if systemctl status postgresql 2>&1 | grep -q "Invalid data directory"; then
        return 0
    fi
    
    # Verificar se consegue iniciar
    if ! systemctl start postgresql 2>/dev/null; then
        return 0
    fi
    
    # Verificar se consegue conectar
    if ! sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

if cluster_has_issues; then
    log "⚠️ Detectados problemas no cluster PostgreSQL - executando limpeza completa..."
    
    # Limpeza completa
    systemctl stop postgresql 2>/dev/null || true
    systemctl disable postgresql 2>/dev/null || true
    apt-get purge postgresql-16 postgresql-common postgresql-client-16 postgresql-client-common -y
    apt-get autoremove --purge -y
    rm -rf /var/lib/postgresql/ /etc/postgresql/ /var/log/postgresql/ /run/postgresql/
    userdel postgres 2>/dev/null || true
    groupdel postgres 2>/dev/null || true
    
    # Reinstalação limpa
    apt-get update
    apt-get install -y postgresql-16 postgresql-contrib
    
    log "✅ PostgreSQL reinstalado"
fi

# Iniciar PostgreSQL
systemctl start postgresql
systemctl enable postgresql
sleep 3

# Verificar se iniciou corretamente
if ! systemctl is-active --quiet postgresql; then
    error "❌ Falha ao iniciar PostgreSQL após reset"
fi

# Recriar usuário e banco
log "🗄️ Recriando usuário e banco de dados..."

sudo -u postgres psql << 'PSQL_EOF'
-- Finalizar conexões existentes
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'samureye_db' AND pid <> pg_backend_pid();

-- Limpar e recriar
DROP DATABASE IF EXISTS samureye_db;
DROP ROLE IF EXISTS samureye;
CREATE ROLE samureye WITH LOGIN PASSWORD 'SamurEye2024DB!' CREATEDB;
CREATE DATABASE samureye_db OWNER samureye;
GRANT ALL PRIVILEGES ON DATABASE samureye_db TO samureye;
PSQL_EOF

# Ativar extensões
sudo -u postgres psql -d samureye_db << 'PSQL_EOF'
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT ALL ON SCHEMA public TO samureye;
PSQL_EOF

log "✅ Reset PostgreSQL concluído com sucesso"

# Testar conexão
if sudo -u postgres psql -d samureye_db -c "SELECT version();" >/dev/null 2>&1; then
    log "✅ Teste de conexão: OK"
else
    error "❌ Teste de conexão falhou"
fi

EOF

# Script de teste Object Storage
cat > "$SCRIPTS_DIR/test-object-storage.sh" << 'EOF'
#!/bin/bash

# Teste de conectividade Object Storage

source /etc/samureye/.env

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[$(date '+%H:%M:%S')] ERROR: $1"; exit 1; }

log "🧪 Testando conectividade Object Storage..."

# Teste de conectividade Google Cloud Storage
log "Testando Google Cloud Storage API..."
if curl -s --connect-timeout 10 "https://storage.googleapis.com" >/dev/null; then
    log "✅ Google Cloud Storage API: OK"
else
    error "❌ Falha na conexão Google Cloud Storage API"
fi

# Verificar variáveis de ambiente
log "Verificando configuração..."
if [ -n "$PUBLIC_OBJECT_SEARCH_PATHS" ]; then
    log "✅ PUBLIC_OBJECT_SEARCH_PATHS: configurado"
else
    log "⚠️ PUBLIC_OBJECT_SEARCH_PATHS: não configurado"
fi

if [ -n "$PRIVATE_OBJECT_DIR" ]; then
    log "✅ PRIVATE_OBJECT_DIR: configurado"
else
    log "⚠️ PRIVATE_OBJECT_DIR: não configurado"
fi

if [ -n "$DEFAULT_OBJECT_STORAGE_BUCKET_ID" ]; then
    log "✅ DEFAULT_OBJECT_STORAGE_BUCKET_ID: configurado"
else
    log "⚠️ DEFAULT_OBJECT_STORAGE_BUCKET_ID: não configurado"
fi

log "Teste Object Storage concluído"
EOF

# Script de health check completo
cat > "$SCRIPTS_DIR/health-check.sh" << 'EOF'
#!/bin/bash

# Health check completo vlxsam03

echo "=== SAMUREYE vlxsam03 HEALTH CHECK ==="
echo "Data: $(date)"
echo "Servidor: vlxsam03 (172.24.1.153)"
echo ""

# Redis
echo "🔴 REDIS:"
if redis-cli -h 172.24.1.153 -a SamurEye2024Redis! ping >/dev/null 2>&1; then
    echo "✅ Redis: Online"
    memory_usage=$(redis-cli -h 172.24.1.153 -a SamurEye2024Redis! info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
    echo "   Memória: $memory_usage"
else
    echo "❌ Redis: Offline"
fi

# Grafana
echo ""
echo "📊 GRAFANA:"
if curl -f -s http://172.24.1.153:3000/api/health >/dev/null 2>&1; then
    echo "✅ Grafana: Online"
else
    echo "❌ Grafana: Offline"
fi

# MinIO
echo ""
echo "🗄️ MINIO (Backup):"
if curl -f -s http://172.24.1.153:9000/minio/health/live >/dev/null 2>&1; then
    echo "✅ MinIO: Online"
else
    echo "❌ MinIO: Offline"
fi

# Conectividade externa
echo ""
echo "🌐 CONECTIVIDADE EXTERNA:"

# Neon Database
source /etc/samureye/.env
if [ -n "$DATABASE_URL" ] && psql "$DATABASE_URL" -c "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ Neon Database: Conectado"
else
    echo "❌ Neon Database: Desconectado"
fi

# Google Cloud Storage
if curl -s --connect-timeout 5 "https://storage.googleapis.com" >/dev/null; then
    echo "✅ Google Cloud Storage: Conectado"
else
    echo "❌ Google Cloud Storage: Desconectado"
fi

# Recursos do sistema
echo ""
echo "💻 SISTEMA:"
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
mem_usage=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')
disk_usage=$(df -h /opt | awk 'NR==2 {print $5}')

echo "CPU: ${cpu_usage}%"
echo "Memória: $mem_usage"
echo "Disco: $disk_usage"

echo ""
echo "=== FIM DO HEALTH CHECK ==="
EOF

# Script de backup
cat > "$SCRIPTS_DIR/daily-backup.sh" << 'EOF'
#!/bin/bash

# Backup diário vlxsam03

set -e

source /etc/samureye/.env

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"; exit 1; }

BACKUP_DATE=$(date +%Y%m%d)
BACKUP_DIR="/opt/backup"

log "🔄 Iniciando backup diário..."

# Backup Redis
log "Backing up Redis..."
mkdir -p "$BACKUP_DIR/redis/$BACKUP_DATE"
redis-cli -h 172.24.1.153 -a SamurEye2024Redis! --rdb "$BACKUP_DIR/redis/$BACKUP_DATE/dump.rdb"
# Backup Redis data directory
cp -r /var/lib/redis/* "$BACKUP_DIR/redis/$BACKUP_DATE/" 2>/dev/null || true

# Backup Neon Database (se configurado)
if [ -n "$DATABASE_URL" ]; then
    log "Backing up Neon Database..."
    mkdir -p "$BACKUP_DIR/neon/$BACKUP_DATE"
    pg_dump "$DATABASE_URL" | gzip > "$BACKUP_DIR/neon/$BACKUP_DATE/samureye_backup.sql.gz"
fi

# Backup configurações
log "Backing up configurations..."
mkdir -p "$BACKUP_DIR/configs/$BACKUP_DATE"
cp -r /etc/samureye "$BACKUP_DIR/configs/$BACKUP_DATE/"
cp -r /etc/redis "$BACKUP_DIR/configs/$BACKUP_DATE/"
cp -r /etc/grafana "$BACKUP_DIR/configs/$BACKUP_DATE/"

# Backup logs
log "Backing up logs..."
mkdir -p "$BACKUP_DIR/logs/$BACKUP_DATE"
cp -r /var/log/samureye "$BACKUP_DIR/logs/$BACKUP_DATE/"

# Limpeza de backups antigos (30 dias)
log "Cleaning old backups..."
find "$BACKUP_DIR" -type d -name "20*" -mtime +30 -exec rm -rf {} + 2>/dev/null || true

log "✅ Backup concluído: $BACKUP_DATE"
EOF

# Tornar scripts executáveis
chmod +x "$SCRIPTS_DIR"/*.sh
chown -R samureye:samureye "$SCRIPTS_DIR"

# Criar link simbólico para facilitar acesso ao reset PostgreSQL
ln -sf "$SCRIPTS_DIR/reset-postgres.sh" /usr/local/bin/samureye-reset-postgres
chmod +x /usr/local/bin/samureye-reset-postgres

log "Scripts de teste criados"

# ============================================================================
# 8. CONFIGURAÇÃO CRON PARA BACKUPS
# ============================================================================

log "⏰ Configurando cron para backups..."

# Crontab para backup diário
cat > /etc/cron.d/samureye-backup << 'EOF'
# SamurEye Daily Backup
# Executa às 02:00 todos os dias

0 2 * * * samureye /opt/samureye/scripts/daily-backup.sh >> /var/log/samureye/backup.log 2>&1
EOF

# Health check a cada 5 minutos
cat > /etc/cron.d/samureye-health << 'EOF'
# SamurEye Health Check
# Executa a cada 5 minutos

*/5 * * * * samureye /opt/samureye/scripts/health-check.sh >> /var/log/samureye/health.log 2>&1
EOF

log "Cron jobs configurados"

# ============================================================================
# 9. CONFIGURAÇÃO DE LOGS
# ============================================================================

log "📋 Configurando rotação de logs..."

cat > /etc/logrotate.d/samureye << 'EOF'
/var/log/samureye/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 samureye samureye
    postrotate
        systemctl reload redis-server grafana-server minio 2>/dev/null || true
    endscript
}
EOF

log "Rotação de logs configurada"

# ============================================================================
# 10. FINALIZAÇÃO
# ============================================================================

log "🎯 Finalizando instalação..."

# Verificar status dos serviços
services=("postgresql" "redis-server" "grafana-server" "minio")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        log "✅ $service: Ativo"
    else
        warn "⚠️ $service: Inativo"
    fi
done

# Informações importantes
echo ""
echo "============================================================================"
echo "🎉 INSTALAÇÃO vlxsam03 CONCLUÍDA"
echo "============================================================================"
echo ""
echo "📊 SERVIÇOS INSTALADOS:"
echo "  • PostgreSQL (Database): 172.24.1.153:5432"
echo "  • Redis (Cache/Sessions): 172.24.1.153:6379"
echo "  • Grafana (Monitoring): http://172.24.1.153:3000"
echo "  • MinIO (Backup): http://172.24.1.153:9000"
echo ""
echo "🔑 CREDENCIAIS PADRÃO:"
echo "  • PostgreSQL: samureye/SamurEye2024DB! (banco: samureye_db)"
echo "  • Redis: senha 'SamurEye2024Redis!'"
echo "  • Grafana: admin/SamurEye2024!"
echo "  • MinIO: admin/SamurEye2024!"
echo ""
echo "⚠️ PRÓXIMOS PASSOS:"
echo "  1. Configurar object storage no vlxsam02"
echo "  2. Executar testes: /opt/samureye/scripts/health-check.sh"
echo "  3. Verificar conectividade PostgreSQL: /opt/samureye/scripts/test-postgres-connection.sh"
echo "  4. Para reset completo PostgreSQL (emergencial): samureye-reset-postgres"
echo ""
echo "📁 DIRETÓRIOS IMPORTANTES:"
echo "  • Dados: /opt/data"
echo "  • Backups: /opt/backup"
echo "  • Scripts: /opt/samureye/scripts"
echo "  • Configuração: /etc/samureye"
echo "  • Logs: /var/log/samureye"
echo ""
echo "============================================================================"

log "✅ Instalação vlxsam03 concluída com sucesso!"