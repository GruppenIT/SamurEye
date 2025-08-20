#!/bin/bash
# SamurEye Database + Redis Installation Script (vlxsam03)
# Execute como root: sudo bash install.sh

set -e

echo "🚀 Iniciando instalação do SamurEye Database + Redis (vlxsam03)..."

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para log
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

# Variáveis
DB_NAME="samureye"
DB_USER="samureye"
DB_PASSWORD=$(openssl rand -base64 32)
POSTGRES_VERSION="14"
BACKUP_DIR="/opt/backup"

# Verificar conectividade
log "Verificando conectividade com a internet..."
if ! ping -c 1 google.com &> /dev/null; then
    error "Sem conectividade com a internet"
fi

# Atualizar sistema
log "Atualizando sistema..."
apt update && apt upgrade -y

# Instalar pacotes essenciais
log "Instalando pacotes essenciais..."
apt install -y curl wget git postgresql-$POSTGRES_VERSION postgresql-contrib redis-server ufw fail2ban htop unzip software-properties-common

# Configurar timezone
log "Configurando timezone para America/Sao_Paulo..."
timedatectl set-timezone America/Sao_Paulo

# Configurar firewall UFW
log "Configurando firewall UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 5432/tcp  # PostgreSQL
ufw allow 6379/tcp  # Redis
ufw allow 9000/tcp  # MinIO
ufw allow 9001/tcp  # MinIO Console
ufw --force enable

# Configurar PostgreSQL
log "Configurando PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Configurar PostgreSQL para aceitar conexões remotas
log "Configurando PostgreSQL para conexões remotas..."
PG_CONFIG="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"

# Backup das configurações originais
cp $PG_CONFIG $PG_CONFIG.bak
cp $PG_HBA $PG_HBA.bak

# Configurar postgresql.conf
cat >> $PG_CONFIG << 'EOF'

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

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%a.log'
log_truncate_on_rotation = on
log_rotation_age = 1d
log_rotation_size = 0
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0

# Security
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'
EOF

# Configurar pg_hba.conf
cat > $PG_HBA << 'EOF'
# PostgreSQL Client Authentication Configuration File

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     md5

# IPv4 local connections:
host    all             all             127.0.0.1/32            md5

# SamurEye Application Servers
host    samureye        samureye        vlxsam02/32             md5
host    samureye        samureye        10.0.0.0/8              md5
host    samureye        samureye        172.16.0.0/12           md5
host    samureye        samureye        192.168.0.0/16          md5

# Replication (if needed)
# host    replication     all             vlxsam02/32             md5

# IPv6 local connections:
host    all             all             ::1/128                 md5
EOF

# Reiniciar PostgreSQL
systemctl restart postgresql

# Criar usuário e banco de dados
log "Criando banco de dados e usuário..."
sudo -u postgres psql << EOF
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

-- Extensões necessárias
\c $DB_NAME
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Conceder permissões
GRANT ALL ON SCHEMA public TO $DB_USER;
ALTER USER $DB_USER CREATEDB;

\q
EOF

# Configurar Redis
log "Configurando Redis..."
cp /etc/redis/redis.conf /etc/redis/redis.conf.bak

cat > /etc/redis/redis.conf << 'EOF'
# Redis Configuration for SamurEye

# Network
bind 0.0.0.0
port 6379
protected-mode yes
requirepass samureye_redis_secure_password_change_me

# General
daemonize yes
supervised systemd
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16

# Security
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command KEYS ""
rename-command CONFIG "CONFIG_b8f3e4a9c2"

# Persistence
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis

# Memory Management
maxmemory 512mb
maxmemory-policy allkeys-lru

# Append Only File
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Slow Log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Latency Monitor
latency-monitor-threshold 100
EOF

# Reiniciar Redis
systemctl restart redis-server
systemctl enable redis-server

# Instalar e configurar MinIO (para armazenamento de arquivos)
log "Instalando MinIO..."
wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio

# Criar usuário para MinIO
useradd -m -s /bin/bash minio || true

# Criar diretórios
mkdir -p /opt/minio/data
mkdir -p /etc/minio
mkdir -p /var/log/minio
chown -R minio:minio /opt/minio
chown -R minio:minio /var/log/minio

# Configurar MinIO
MINIO_ACCESS_KEY="samureye"
MINIO_SECRET_KEY=$(openssl rand -base64 32)

cat > /etc/minio/minio.conf << EOF
MINIO_ROOT_USER=$MINIO_ACCESS_KEY
MINIO_ROOT_PASSWORD=$MINIO_SECRET_KEY
MINIO_VOLUMES=/opt/minio/data
MINIO_OPTS="--console-address :9001"
EOF

# Criar service do MinIO
cat > /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=/usr/local/bin/minio

[Service]
WorkingDirectory=/opt/minio
User=minio
Group=minio
EnvironmentFile=/etc/minio/minio.conf
ExecStartPre=/bin/bash -c "if [ -z \"${MINIO_VOLUMES}\" ]; then echo \"Variable MINIO_VOLUMES not set in /etc/minio/minio.conf\"; exit 1; fi"
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES
Restart=always
RestartSec=5
LimitNOFILE=65536
TasksMax=infinity
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minio
systemctl start minio

# Criar diretório de backup
log "Configurando sistema de backup..."
mkdir -p $BACKUP_DIR
chown postgres:postgres $BACKUP_DIR

# Script de backup automático
cat > /opt/backup-database.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/backup"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="samureye"

echo "Starting database backup at $(date)"

# PostgreSQL backup
pg_dump -U samureye -h localhost $DB_NAME | gzip > $BACKUP_DIR/postgresql_$DATE.sql.gz

# Redis backup
cp /var/lib/redis/dump.rdb $BACKUP_DIR/redis_$DATE.rdb

# MinIO backup (data directory)
tar -czf $BACKUP_DIR/minio_$DATE.tar.gz /opt/minio/data

echo "Database backup completed at $(date)"

# Keep only last 7 backups
ls -t $BACKUP_DIR/postgresql_*.sql.gz | tail -n +8 | xargs rm -f
ls -t $BACKUP_DIR/redis_*.rdb | tail -n +8 | xargs rm -f
ls -t $BACKUP_DIR/minio_*.tar.gz | tail -n +8 | xargs rm -f

echo "Backup cleanup completed"
EOF

chmod +x /opt/backup-database.sh

# Configurar cron para backup diário
log "Configurando backup automático..."
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/backup-database.sh") | crontab -

# Script de monitoramento
cat > /opt/monitor-database.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/database-monitor.log"

echo "$(date): Starting database monitoring" >> $LOG_FILE

# Check PostgreSQL
if systemctl is-active --quiet postgresql; then
    echo "$(date): PostgreSQL OK" >> $LOG_FILE
else
    echo "$(date): PostgreSQL FAILED" >> $LOG_FILE
    systemctl start postgresql
fi

# Check Redis
if systemctl is-active --quiet redis-server; then
    echo "$(date): Redis OK" >> $LOG_FILE
else
    echo "$(date): Redis FAILED" >> $LOG_FILE
    systemctl start redis-server
fi

# Check MinIO
if systemctl is-active --quiet minio; then
    echo "$(date): MinIO OK" >> $LOG_FILE
else
    echo "$(date): MinIO FAILED" >> $LOG_FILE
    systemctl start minio
fi

# Check disk space
DISK_USAGE=$(df /opt | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 85 ]; then
    echo "$(date): WARNING: Disk usage at ${DISK_USAGE}%" >> $LOG_FILE
fi

# Check database connections
PG_CONNECTIONS=$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" | xargs)
if [ $PG_CONNECTIONS -gt 150 ]; then
    echo "$(date): WARNING: High database connections: $PG_CONNECTIONS" >> $LOG_FILE
fi
EOF

chmod +x /opt/monitor-database.sh

# Configurar cron para monitoramento
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/monitor-database.sh") | crontab -

# Configurar logrotate
log "Configurando logrotate..."
cat > /etc/logrotate.d/samureye-db << 'EOF'
/var/log/postgresql/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    postrotate
        systemctl reload postgresql
    endscript
}

/var/log/redis/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    postrotate
        systemctl reload redis-server
    endscript
}

/var/log/minio/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
}
EOF

# Salvar credenciais
log "Salvando credenciais..."
cat > /root/samureye-credentials.txt << EOF
# SamurEye Database Credentials
# IMPORTANTE: Mantenha este arquivo seguro!

PostgreSQL:
- Host: vlxsam03 (ou IP do servidor)
- Port: 5432
- Database: $DB_NAME
- Username: $DB_USER
- Password: $DB_PASSWORD

Redis:
- Host: vlxsam03 (ou IP do servidor)
- Port: 6379
- Password: samureye_redis_secure_password_change_me

MinIO:
- Host: vlxsam03 (ou IP do servidor)
- Port: 9000 (API), 9001 (Console)
- Access Key: $MINIO_ACCESS_KEY
- Secret Key: $MINIO_SECRET_KEY
- Console URL: http://vlxsam03:9001

Connection Strings:
- PostgreSQL: postgresql://$DB_USER:$DB_PASSWORD@vlxsam03:5432/$DB_NAME
- Redis: redis://:samureye_redis_secure_password_change_me@vlxsam03:6379
EOF

chmod 600 /root/samureye-credentials.txt

log "Configuração concluída!"
echo ""
echo "📋 INFORMAÇÕES IMPORTANTES:"
echo ""
echo "🔐 Credenciais salvas em: /root/samureye-credentials.txt"
echo ""
echo "🔗 Connection Strings:"
echo "PostgreSQL: postgresql://$DB_USER:$DB_PASSWORD@vlxsam03:5432/$DB_NAME"
echo "Redis: redis://:samureye_redis_secure_password_change_me@vlxsam03:6379"
echo ""
echo "📊 URLs de Acesso:"
echo "MinIO Console: http://vlxsam03:9001"
echo ""
echo "🔧 PRÓXIMOS PASSOS:"
echo "1. Alterar senhas padrão do Redis e MinIO"
echo "2. Configurar SSL/TLS para PostgreSQL (opcional)"
echo "3. Configurar backup remoto"
echo "4. Testar conectividade dos servidores de aplicação"
echo ""
echo "🧪 TESTES:"
echo "psql -h vlxsam03 -U $DB_USER -d $DB_NAME"
echo "redis-cli -h vlxsam03 -p 6379 -a samureye_redis_secure_password_change_me ping"
echo "curl http://vlxsam03:9000/minio/health/live"
echo ""
echo "✅ Instalação do Database + Redis concluída com sucesso!"