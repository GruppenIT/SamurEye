#!/bin/bash
# SamurEye Frontend + Backend Installation Script (vlxsam02)
# Execute como root: sudo bash install.sh

set -e

echo "🚀 Iniciando instalação do SamurEye Frontend + Backend (vlxsam02)..."

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
APP_USER="samureye"
APP_DIR="/opt/samureye"
LOG_DIR="/var/log/samureye"

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
apt install -y curl wget git build-essential python3 python3-pip supervisor ufw htop unzip software-properties-common

# Configurar timezone
log "Configurando timezone para America/Sao_Paulo..."
timedatectl set-timezone America/Sao_Paulo

# Configurar firewall UFW
log "Configurando firewall UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 3000/tcp  # App principal
ufw allow 3001/tcp  # Scanner externo
ufw --force enable

# Instalar Node.js 20.x
log "Instalando Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Verificar instalação do Node.js
log "Verificando instalação do Node.js..."
node_version=$(node --version)
npm_version=$(npm --version)
log "Node.js: $node_version, NPM: $npm_version"

# Criar usuário para aplicação
log "Criando usuário para aplicação..."
if ! id "$APP_USER" &>/dev/null; then
    useradd -m -s /bin/bash $APP_USER
    usermod -aG sudo $APP_USER
    log "Usuário $APP_USER criado"
else
    log "Usuário $APP_USER já existe"
fi

# Criar diretórios
log "Criando diretórios da aplicação..."
mkdir -p $APP_DIR
mkdir -p $LOG_DIR
mkdir -p /opt/backup
mkdir -p /etc/samureye

# Definir permissões
chown -R $APP_USER:$APP_USER $APP_DIR
chown -R $APP_USER:$APP_USER $LOG_DIR
chmod 755 $APP_DIR
chmod 755 $LOG_DIR

# Configurar ambiente Node.js
log "Configurando ambiente Node.js..."
cat > /etc/profile.d/nodejs.sh << 'EOF'
export PATH=/usr/bin:$PATH
export NODE_ENV=production
EOF

# Instalar PM2 globalmente
log "Instalando PM2..."
npm install -g pm2
pm2 startup

# Criar arquivo de configuração do PM2
log "Criando configuração do PM2..."
cat > $APP_DIR/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [
    {
      name: 'samureye-app',
      script: 'server/index.js',
      cwd: '/opt/samureye',
      instances: 2,
      exec_mode: 'cluster',
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      },
      log_file: '/var/log/samureye/app.log',
      out_file: '/var/log/samureye/app-out.log',
      error_file: '/var/log/samureye/app-error.log',
      time: true
    },
    {
      name: 'samureye-scanner',
      script: 'scanner/index.js',
      cwd: '/opt/samureye',
      instances: 1,
      env: {
        NODE_ENV: 'production',
        PORT: 3001
      },
      log_file: '/var/log/samureye/scanner.log',
      out_file: '/var/log/samureye/scanner-out.log',
      error_file: '/var/log/samureye/scanner-error.log',
      time: true
    }
  ]
};
EOF

chown $APP_USER:$APP_USER $APP_DIR/ecosystem.config.js

# Criar arquivo de environment template
log "Criando template de variáveis de ambiente..."
cat > /etc/samureye/.env.template << 'EOF'
# Database Configuration
DATABASE_URL=postgresql://samureye:password@vlxsam03:5432/samureye
PGHOST=vlxsam03
PGPORT=5432
PGUSER=samureye
PGPASSWORD=secure_password_here
PGDATABASE=samureye

# Redis Configuration
REDIS_URL=redis://vlxsam03:6379

# Session Configuration
SESSION_SECRET=your_very_secure_session_secret_here_min_32_chars

# Authentication
REPL_ID=your_replit_app_id
ISSUER_URL=https://replit.com/oidc
REPLIT_DOMAINS=app.samureye.com.br,api.samureye.com.br

# Delinea Secret Server
DELINEA_API_KEY=your_delinea_api_key_here
DELINEA_BASE_URL=https://gruppenztna.secretservercloud.com

# External Scanner
SCANNER_ENDPOINT=https://scanner.samureye.com.br

# Application
NODE_ENV=production
PORT=3000
SCANNER_PORT=3001

# MinIO/S3 (optional)
MINIO_ENDPOINT=vlxsam03
MINIO_PORT=9000
MINIO_ACCESS_KEY=samureye
MINIO_SECRET_KEY=your_minio_secret_key

# Monitoring
GRAFANA_URL=http://vlxsam03:3000
FORTISIEM_HOST=your_fortisiem_host
FORTISIEM_PORT=514

# Logging
LOG_LEVEL=info
LOG_FILE=/var/log/samureye/app.log
EOF

chmod 600 /etc/samureye/.env.template
chown root:root /etc/samureye/.env.template

# Configurar logrotate
log "Configurando logrotate..."
cat > /etc/logrotate.d/samureye << 'EOF'
/var/log/samureye/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 samureye samureye
    postrotate
        /bin/kill -USR1 $(cat /var/run/pm2/pm2.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOF

# Criar script de health check
log "Criando script de health check..."
cat > /opt/health-check.sh << 'EOF'
#!/bin/bash

# Health check script for SamurEye services
LOG_FILE="/var/log/samureye/health-check.log"

echo "$(date): Starting health check" >> $LOG_FILE

# Check main app
if curl -f http://localhost:3000/api/health >/dev/null 2>&1; then
    echo "$(date): Main app OK" >> $LOG_FILE
else
    echo "$(date): Main app FAILED" >> $LOG_FILE
    pm2 restart samureye-app
fi

# Check scanner
if curl -f http://localhost:3001/health >/dev/null 2>&1; then
    echo "$(date): Scanner OK" >> $LOG_FILE
else
    echo "$(date): Scanner FAILED" >> $LOG_FILE
    pm2 restart samureye-scanner
fi

# Check disk space
DISK_USAGE=$(df /opt | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 85 ]; then
    echo "$(date): WARNING: Disk usage at ${DISK_USAGE}%" >> $LOG_FILE
fi

# Check memory
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [ $MEM_USAGE -gt 85 ]; then
    echo "$(date): WARNING: Memory usage at ${MEM_USAGE}%" >> $LOG_FILE
fi
EOF

chmod +x /opt/health-check.sh

# Configurar cron para health check
log "Configurando cron para health check..."
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/health-check.sh") | crontab -

# Criar script de backup
log "Criando script de backup..."
cat > /opt/backup-app.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/backup"
DATE=$(date +%Y%m%d_%H%M%S)
APP_BACKUP="$BACKUP_DIR/samureye_app_$DATE.tar.gz"

echo "Starting application backup at $(date)"

# Backup application files
tar -czf $APP_BACKUP \
    --exclude='node_modules' \
    --exclude='dist' \
    --exclude='build' \
    --exclude='*.log' \
    /opt/samureye

echo "Application backup completed: $APP_BACKUP"

# Keep only last 7 backups
ls -t $BACKUP_DIR/samureye_app_*.tar.gz | tail -n +8 | xargs rm -f

echo "Backup cleanup completed"
EOF

chmod +x /opt/backup-app.sh

# Configurar systemd service como backup para PM2
log "Criando systemd service..."
cat > /etc/systemd/system/samureye.service << 'EOF'
[Unit]
Description=SamurEye Application
After=network.target
Wants=network.target

[Service]
Type=forking
User=samureye
WorkingDirectory=/opt/samureye
ExecStart=/usr/bin/pm2 start ecosystem.config.js
ExecReload=/usr/bin/pm2 reload ecosystem.config.js
ExecStop=/usr/bin/pm2 stop ecosystem.config.js
ExecDelete=/usr/bin/pm2 delete ecosystem.config.js
PrivateTmp=true
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable samureye

# Criar script de deploy
log "Criando script de deploy..."
cat > /opt/deploy-samureye.sh << 'EOF'
#!/bin/bash

set -e

APP_DIR="/opt/samureye"
BACKUP_DIR="/opt/backup"
DATE=$(date +%Y%m%d_%H%M%S)

echo "Starting SamurEye deployment at $(date)"

# Backup current version
if [ -d "$APP_DIR" ]; then
    echo "Creating backup..."
    tar -czf "$BACKUP_DIR/pre_deploy_$DATE.tar.gz" \
        --exclude='node_modules' \
        --exclude='dist' \
        --exclude='build' \
        $APP_DIR
fi

# Stop services
echo "Stopping services..."
pm2 stop all || true

cd $APP_DIR

# Pull latest code (if using git)
if [ -d ".git" ]; then
    echo "Pulling latest code..."
    git pull origin main
fi

# Install dependencies
echo "Installing dependencies..."
npm ci --production

# Build frontend
echo "Building frontend..."
npm run build

# Run database migrations
echo "Running database migrations..."
npm run db:push

# Start services
echo "Starting services..."
pm2 start ecosystem.config.js

echo "Deployment completed successfully at $(date)"
EOF

chmod +x /opt/deploy-samureye.sh
chown $APP_USER:$APP_USER /opt/deploy-samureye.sh

log "Configuração concluída!"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "1. Configurar arquivo .env em /etc/samureye/"
echo "   cp /etc/samureye/.env.template /etc/samureye/.env"
echo "   nano /etc/samureye/.env"
echo ""
echo "2. Copiar código da aplicação para /opt/samureye/"
echo "   chown -R samureye:samureye /opt/samureye"
echo ""
echo "3. Instalar dependências e fazer build:"
echo "   cd /opt/samureye"
echo "   npm ci --production"
echo "   npm run build"
echo ""
echo "4. Configurar PM2 como usuário samureye:"
echo "   sudo -u samureye pm2 start ecosystem.config.js"
echo "   sudo -u samureye pm2 save"
echo ""
echo "5. Verificar se serviços estão rodando:"
echo "   pm2 status"
echo "   curl http://localhost:3000/api/health"
echo "   curl http://localhost:3001/health"
echo ""
echo "✅ Instalação do Frontend + Backend concluída com sucesso!"