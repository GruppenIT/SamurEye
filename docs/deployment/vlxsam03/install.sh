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
# 4. INSTALAÇÃO GRAFANA
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
# 5. INSTALAÇÃO MINIO (OPCIONAL - BACKUP LOCAL)
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

# Neon Database (configurar com valores reais)
DATABASE_URL=postgresql://username:password@ep-xyz.us-east-1.aws.neon.tech/samureye?sslmode=require
PGDATABASE=samureye
PGHOST=ep-xyz.us-east-1.aws.neon.tech
PGPORT=5432
PGUSER=username
PGPASSWORD=password

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
services=("redis-server" "grafana-server" "minio")
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
echo "  • Redis (Cache/Sessions): 172.24.1.153:6379"
echo "  • Grafana (Monitoring): http://172.24.1.153:3000"
echo "  • MinIO (Backup): http://172.24.1.153:9000"
echo ""
echo "🔑 CREDENCIAIS PADRÃO:"
echo "  • Redis: senha 'SamurEye2024Redis!'"
echo "  • Grafana: admin/SamurEye2024!"
echo "  • MinIO: admin/SamurEye2024!"
echo ""
echo "⚠️ PRÓXIMOS PASSOS:"
echo "  1. Configurar DATABASE_URL no arquivo /etc/samureye/.env"
echo "  2. Configurar object storage no vlxsam02"
echo "  3. Executar testes: /opt/samureye/scripts/health-check.sh"
echo "  4. Verificar conectividade Neon: /opt/samureye/scripts/test-neon-connection.sh"
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