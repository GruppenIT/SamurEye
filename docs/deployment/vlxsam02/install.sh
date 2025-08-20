#!/bin/bash

# SamurEye vlxsam02 - Application Server Installation
# Servidor: vlxsam02 (172.24.1.152)
# Função: Frontend React + Backend Node.js + Scanner Service

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

log "🚀 Iniciando instalação do SamurEye Application Server (vlxsam02)..."

# ============================================================================
# 1. PREPARAÇÃO DO SISTEMA
# ============================================================================

info "📋 Configurando sistema base..."

# Atualizar sistema
log "Atualizando sistema Ubuntu..."
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y

# Configurar timezone
log "Configurando timezone para America/Sao_Paulo..."
timedatectl set-timezone America/Sao_Paulo

# Instalar pacotes essenciais
log "Instalando pacotes essenciais..."
apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    python3 \
    python3-pip \
    htop \
    unzip \
    software-properties-common \
    ufw \
    fail2ban \
    supervisor \
    sqlite3

# ============================================================================
# 2. CONFIGURAÇÃO DE USUÁRIO
# ============================================================================

log "👤 Configurando usuário samureye..."

# Variáveis de usuário
APP_USER="samureye"
APP_PASSWORD="SamurEye2024!"
APP_HOME="/home/samureye"
APP_DIR="/opt/samureye"
LOG_DIR="/var/log/samureye"

# Criar usuário se não existir
if ! id "$APP_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$APP_USER"
    log "Usuário $APP_USER criado"
else
    log "Usuário $APP_USER já existe"
fi

# Definir senha
echo "$APP_USER:$APP_PASSWORD" | chpasswd
log "Senha definida para o usuário $APP_USER"

# Adicionar ao grupo sudo
usermod -aG sudo "$APP_USER"

# Configurar sudoers para automação
if ! grep -q "$APP_USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
    echo "$APP_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    log "Configurado sudo sem senha para $APP_USER"
fi

# Criar diretórios
mkdir -p "$APP_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$APP_HOME/.ssh"
mkdir -p /opt/backup
mkdir -p /etc/samureye

# Definir permissões
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chown -R "$APP_USER:$APP_USER" "$LOG_DIR"
chown -R "$APP_USER:$APP_USER" "$APP_HOME"
chmod 700 "$APP_HOME/.ssh"

# ============================================================================
# 3. INSTALAÇÃO NODE.JS
# ============================================================================

log "📦 Instalando Node.js 20.x LTS..."

# Instalar Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Verificar instalação
node_version=$(node --version)
npm_version=$(npm --version)
log "Node.js: $node_version, NPM: $npm_version"

# Instalar PM2 globalmente
log "Instalando PM2..."
npm install -g pm2

# Configurar PM2 startup para usuário samureye
sudo -u "$APP_USER" pm2 startup
env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u "$APP_USER" --hp "$APP_HOME"

# ============================================================================
# 4. CONFIGURAÇÃO DE FIREWALL
# ============================================================================

log "🔥 Configurando firewall UFW..."

# Configurar UFW
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH e portas da aplicação
ufw allow ssh
ufw allow 3000/tcp comment "SamurEye App"
ufw allow 3001/tcp comment "SamurEye Scanner"

# Ativar firewall
ufw --force enable

log "Firewall configurado: SSH (22), App (3000), Scanner (3001)"

# ============================================================================
# 5. FERRAMENTAS DE SEGURANÇA
# ============================================================================

log "🔧 Instalando ferramentas de segurança..."

# Instalar Nmap
apt-get install -y nmap

# Instalar Nuclei
log "Instalando Nuclei..."
cd /tmp
NUCLEI_VERSION="3.2.9"
wget "https://github.com/projectdiscovery/nuclei/releases/download/v${NUCLEI_VERSION}/nuclei_${NUCLEI_VERSION}_linux_amd64.zip"
unzip "nuclei_${NUCLEI_VERSION}_linux_amd64.zip"
mv nuclei /usr/local/bin/
chmod +x /usr/local/bin/nuclei

# Verificar instalações
nmap --version | head -1
nuclei --version

# Atualizar templates do Nuclei
sudo -u "$APP_USER" nuclei -update-templates

# ============================================================================
# 6. CLONAR E CONFIGURAR APLICAÇÃO
# ============================================================================

log "📁 Configurando código da aplicação..."

# Clonar repositório (assumindo que já está disponível)
if [ ! -d "$APP_DIR/SamurEye" ]; then
    # Se não existir, criar estrutura básica
    mkdir -p "$APP_DIR/SamurEye"
    log "Diretório da aplicação criado. Código será copiado posteriormente."
else
    log "Diretório da aplicação já existe"
fi

chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# ============================================================================
# 7. CONFIGURAÇÃO DE AMBIENTE
# ============================================================================

log "⚙️ Configurando variáveis de ambiente..."

# Arquivo de environment
cat > /etc/samureye/.env << 'EOF'
# SamurEye Application - Environment Variables
# Servidor: vlxsam02 (172.24.1.152)

# Application
NODE_ENV=production
PORT=3000
SCANNER_PORT=3001

# Database (vlxsam03)
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod
PGHOST=172.24.1.153
PGPORT=5432
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye_prod

# Redis (vlxsam03)
REDIS_URL=redis://172.24.1.153:6379

# Session
SESSION_SECRET=samureye-super-secret-session-key-2024-change-this

# Authentication
REPL_ID=your_replit_app_id
ISSUER_URL=https://replit.com/oidc
REPLIT_DOMAINS=app.samureye.com.br,api.samureye.com.br

# Delinea Secret Server
DELINEA_API_KEY=your_delinea_api_key_here
DELINEA_BASE_URL=https://gruppenztna.secretservercloud.com
DELINEA_RULE_NAME=SamurEye Integration

# MinIO/Object Storage (vlxsam03)
MINIO_ENDPOINT=172.24.1.153
MINIO_PORT=9000
MINIO_ACCESS_KEY=samureye
MINIO_SECRET_KEY=SamurEye2024!
MINIO_BUCKET_NAME=samureye-storage

# Scanner Service
SCANNER_SERVICE_URL=http://localhost:3001
NMAP_PATH=/usr/bin/nmap
NUCLEI_PATH=/usr/local/bin/nuclei

# Logging
LOG_LEVEL=info
LOG_DIR=/var/log/samureye

# Monitoring
GRAFANA_URL=http://172.24.1.153:3000
FORTISIEM_HOST=your_fortisiem_host
FORTISIEM_PORT=514

# Frontend URL
FRONTEND_URL=https://app.samureye.com.br
API_BASE_URL=https://api.samureye.com.br

# File Upload
UPLOAD_MAX_SIZE=50MB
UPLOAD_DIR=/opt/samureye/uploads

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# CORS
CORS_ORIGINS=https://app.samureye.com.br,https://api.samureye.com.br
EOF

chmod 600 /etc/samureye/.env
chown root:root /etc/samureye/.env

# Link para diretório da aplicação
ln -sf /etc/samureye/.env "$APP_DIR/.env"

# ============================================================================
# 8. CONFIGURAÇÃO PM2
# ============================================================================

log "⚡ Configurando PM2..."

# Configuração PM2 para aplicação SamurEye
cat > "$APP_DIR/ecosystem.config.js" << 'EOF'
module.exports = {
  apps: [
    {
      name: 'samureye-app',
      script: 'server/index.ts',
      interpreter: 'node',
      interpreter_args: '--loader tsx',
      cwd: '/opt/samureye/SamurEye',
      instances: 2,
      exec_mode: 'cluster',
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      },
      env_file: '/etc/samureye/.env',
      log_file: '/var/log/samureye/app.log',
      out_file: '/var/log/samureye/app-out.log',
      error_file: '/var/log/samureye/app-error.log',
      time: true,
      watch: false,
      ignore_watch: ['node_modules', '*.log', '.git'],
      max_restarts: 5,
      restart_delay: 5000
    },
    {
      name: 'samureye-scanner',
      script: 'scanner-service.js',
      cwd: '/opt/samureye',
      instances: 1,
      env: {
        NODE_ENV: 'production',
        PORT: 3001
      },
      env_file: '/etc/samureye/.env',
      log_file: '/var/log/samureye/scanner.log',
      out_file: '/var/log/samureye/scanner-out.log',
      error_file: '/var/log/samureye/scanner-error.log',
      time: true,
      watch: false,
      max_restarts: 5,
      restart_delay: 5000
    }
  ]
};
EOF

chown "$APP_USER:$APP_USER" "$APP_DIR/ecosystem.config.js"

# ============================================================================
# 9. SCANNER SERVICE
# ============================================================================

log "🔍 Configurando Scanner Service..."

cat > "$APP_DIR/scanner-service.js" << 'EOF'
#!/usr/bin/env node

// SamurEye Scanner Service
// Porta: 3001
// Função: Executar ferramentas de segurança (Nmap, Nuclei)

const express = require('express');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.SCANNER_PORT || 3001;

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'samureye-scanner',
    version: '1.0.0'
  });
});

// Executar Nmap
app.post('/scan/nmap', async (req, res) => {
  const { target, options = [] } = req.body;
  
  if (!target) {
    return res.status(400).json({ error: 'Target is required' });
  }

  try {
    const nmapPath = process.env.NMAP_PATH || '/usr/bin/nmap';
    const args = [...options, target];
    
    console.log(`Executing nmap: ${nmapPath} ${args.join(' ')}`);
    
    const nmap = spawn(nmapPath, args);
    let output = '';
    let error = '';

    nmap.stdout.on('data', (data) => {
      output += data.toString();
    });

    nmap.stderr.on('data', (data) => {
      error += data.toString();
    });

    nmap.on('close', (code) => {
      res.json({
        success: code === 0,
        exit_code: code,
        output,
        error,
        target,
        options,
        timestamp: new Date().toISOString()
      });
    });

  } catch (err) {
    console.error('Nmap execution error:', err);
    res.status(500).json({ error: 'Internal scanner error', details: err.message });
  }
});

// Executar Nuclei
app.post('/scan/nuclei', async (req, res) => {
  const { target, templates = [], options = [] } = req.body;
  
  if (!target) {
    return res.status(400).json({ error: 'Target is required' });
  }

  try {
    const nucleiPath = process.env.NUCLEI_PATH || '/usr/local/bin/nuclei';
    const args = ['-target', target, ...options];
    
    if (templates.length > 0) {
      args.push('-t', templates.join(','));
    }
    
    console.log(`Executing nuclei: ${nucleiPath} ${args.join(' ')}`);
    
    const nuclei = spawn(nucleiPath, args);
    let output = '';
    let error = '';

    nuclei.stdout.on('data', (data) => {
      output += data.toString();
    });

    nuclei.stderr.on('data', (data) => {
      error += data.toString();
    });

    nuclei.on('close', (code) => {
      res.json({
        success: code === 0,
        exit_code: code,
        output,
        error,
        target,
        templates,
        options,
        timestamp: new Date().toISOString()
      });
    });

  } catch (err) {
    console.error('Nuclei execution error:', err);
    res.status(500).json({ error: 'Internal scanner error', details: err.message });
  }
});

// Listar templates do Nuclei
app.get('/scan/nuclei/templates', (req, res) => {
  try {
    const templatesDir = path.join(process.env.HOME || '/home/samureye', 'nuclei-templates');
    
    if (!fs.existsSync(templatesDir)) {
      return res.json({ templates: [], message: 'Templates directory not found' });
    }

    // Implementar listagem de templates recursivamente
    const getTemplates = (dir, prefix = '') => {
      const items = fs.readdirSync(dir);
      let templates = [];
      
      for (const item of items) {
        const fullPath = path.join(dir, item);
        const stat = fs.statSync(fullPath);
        
        if (stat.isDirectory()) {
          templates = templates.concat(getTemplates(fullPath, `${prefix}${item}/`));
        } else if (item.endsWith('.yaml') || item.endsWith('.yml')) {
          templates.push(`${prefix}${item}`);
        }
      }
      
      return templates;
    };

    const templates = getTemplates(templatesDir);
    res.json({ templates, count: templates.length });

  } catch (err) {
    console.error('Error listing templates:', err);
    res.status(500).json({ error: 'Error listing templates', details: err.message });
  }
});

// Middleware de erro
app.use((err, req, res, next) => {
  console.error('Scanner service error:', err);
  res.status(500).json({ error: 'Internal scanner error' });
});

// Iniciar servidor
app.listen(PORT, '0.0.0.0', () => {
  console.log(`SamurEye Scanner Service running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});
EOF

chmod +x "$APP_DIR/scanner-service.js"
chown "$APP_USER:$APP_USER" "$APP_DIR/scanner-service.js"

# ============================================================================
# 10. SCRIPTS DE MONITORAMENTO
# ============================================================================

log "📊 Criando scripts de monitoramento..."

mkdir -p "$APP_DIR/scripts"

# Health check principal
cat > "$APP_DIR/scripts/health-check.sh" << 'EOF'
#!/bin/bash

# Health check completo para vlxsam02

echo "=== SAMUREYE APPLICATION HEALTH CHECK ==="
echo "Data: $(date)"
echo "Servidor: vlxsam02 ($(hostname -I | awk '{print $1}'))"
echo ""

# Verificar serviços PM2
echo "⚡ PM2 SERVICES:"
pm2_status=$(sudo -u samureye pm2 jlist 2>/dev/null | jq -r '.[] | "\(.name): \(.pm2_env.status)"' 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "$pm2_status"
else
    echo "❌ PM2 não está rodando ou sem processos"
fi

# Verificar endpoints
echo ""
echo "🌐 ENDPOINTS:"
if curl -f -s http://localhost:3000/api/health >/dev/null 2>&1; then
    echo "✅ App (3000): Respondendo"
else
    echo "❌ App (3000): Não responde"
fi

if curl -f -s http://localhost:3001/health >/dev/null 2>&1; then
    echo "✅ Scanner (3001): Respondendo"
else
    echo "❌ Scanner (3001): Não responde"
fi

# Verificar conectividade com vlxsam03 (database)
echo ""
echo "🗄️ DATABASE CONNECTIVITY:"
if nc -z 172.24.1.153 5432 2>/dev/null; then
    echo "✅ PostgreSQL (vlxsam03:5432): Acessível"
else
    echo "❌ PostgreSQL (vlxsam03:5432): Inacessível"
fi

if nc -z 172.24.1.153 6379 2>/dev/null; then
    echo "✅ Redis (vlxsam03:6379): Acessível"
else
    echo "❌ Redis (vlxsam03:6379): Inacessível"
fi

# Verificar ferramentas de segurança
echo ""
echo "🔧 SECURITY TOOLS:"
if command -v nmap >/dev/null 2>&1; then
    echo "✅ Nmap: $(nmap --version | head -1)"
else
    echo "❌ Nmap: Não instalado"
fi

if command -v nuclei >/dev/null 2>&1; then
    echo "✅ Nuclei: $(nuclei --version 2>/dev/null | head -1)"
else
    echo "❌ Nuclei: Não instalado"
fi

# Recursos do sistema
echo ""
echo "💻 RECURSOS:"
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
mem_usage=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')
disk_usage=$(df -h /opt | awk 'NR==2 {print $5}')

echo "CPU: ${cpu_usage}%"
echo "Memória: $mem_usage"
echo "Disco: $disk_usage"

# Verificar logs recentes
echo ""
echo "📝 LOGS RECENTES (últimas 5 linhas):"
if [ -f /var/log/samureye/app.log ]; then
    echo "App:"
    tail -5 /var/log/samureye/app.log | sed 's/^/  /'
else
    echo "❌ Log da aplicação não encontrado"
fi

echo ""
echo "=== FIM DO HEALTH CHECK ==="
EOF

chmod +x "$APP_DIR/scripts/health-check.sh"

# Script de teste de conectividade
cat > "$APP_DIR/scripts/test-connectivity.sh" << 'EOF'
#!/bin/bash

# Teste de conectividade com outros servidores

echo "🔗 TESTE DE CONECTIVIDADE"
echo "========================"

servers=(
    "vlxsam01:172.24.1.151:443:NGINX Gateway"
    "vlxsam03:172.24.1.153:5432:PostgreSQL"
    "vlxsam03:172.24.1.153:6379:Redis"
    "vlxsam03:172.24.1.153:9000:MinIO"
    "vlxsam04:192.168.100.151:22:Collector SSH"
)

for server_info in "${servers[@]}"; do
    IFS=':' read -r name ip port service <<< "$server_info"
    
    if nc -z "$ip" "$port" 2>/dev/null; then
        echo "✅ $name ($ip:$port) - $service"
    else
        echo "❌ $name ($ip:$port) - $service"
    fi
done

echo ""
echo "🌐 TESTES EXTERNOS:"

# Teste de conectividade externa
if curl -f -s https://app.samureye.com.br/nginx-health >/dev/null 2>&1; then
    echo "✅ HTTPS público (via vlxsam01)"
else
    echo "❌ HTTPS público (via vlxsam01)"
fi

if curl -f -s https://gruppenztna.secretservercloud.com >/dev/null 2>&1; then
    echo "✅ Delinea Secret Server"
else
    echo "❌ Delinea Secret Server"
fi
EOF

chmod +x "$APP_DIR/scripts/test-connectivity.sh"

# Script de instalação de dependências
cat > "$APP_DIR/scripts/install-dependencies.sh" << 'EOF'
#!/bin/bash

# Script para instalar dependências da aplicação SamurEye

set -e

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[$(date '+%H:%M:%S')] ERROR: $1"; exit 1; }

if [ ! -f "package.json" ]; then
    error "Execute este script no diretório que contém package.json"
fi

log "📦 Instalando dependências Node.js..."

# Limpar cache e node_modules
npm cache clean --force
rm -rf node_modules package-lock.json

# Instalar dependências
log "Executando npm install..."
npm install

# Verificar se tsx está disponível globalmente
if ! command -v tsx >/dev/null 2>&1; then
    log "Instalando tsx globalmente..."
    npm install -g tsx
fi

# Build da aplicação (se o script existir)
if npm run build >/dev/null 2>&1; then
    log "Build da aplicação executado"
else
    log "Sem script de build configurado (normal para desenvolvimento)"
fi

log "✅ Dependências instaladas com sucesso!"
EOF

chmod +x "$APP_DIR/scripts/install-dependencies.sh"

chown -R "$APP_USER:$APP_USER" "$APP_DIR/scripts"

# ============================================================================
# 11. SYSTEMD SERVICES
# ============================================================================

log "⚙️ Configurando serviços systemd..."

# Serviço systemd como backup para PM2
cat > /etc/systemd/system/samureye-app.service << 'EOF'
[Unit]
Description=SamurEye Application
After=network.target
Wants=network.target

[Service]
Type=forking
User=samureye
Group=samureye
WorkingDirectory=/opt/samureye
EnvironmentFile=/etc/samureye/.env
ExecStart=/usr/bin/pm2 start ecosystem.config.js
ExecReload=/usr/bin/pm2 reload ecosystem.config.js
ExecStop=/usr/bin/pm2 stop ecosystem.config.js
PIDFile=/home/samureye/.pm2/pm2.pid
Restart=always
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=samureye-app

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/samureye /var/log/samureye /home/samureye

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable samureye-app

# ============================================================================
# 12. LOGROTATE
# ============================================================================

log "📝 Configurando logrotate..."

cat > /etc/logrotate.d/samureye << 'EOF'
/var/log/samureye/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 samureye samureye
    postrotate
        /bin/kill -USR2 $(cat /home/samureye/.pm2/pm2.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOF

# ============================================================================
# 13. CRON JOBS
# ============================================================================

log "⏰ Configurando cron jobs..."

# Health check como usuário samureye
sudo -u "$APP_USER" crontab << 'EOF'
# SamurEye Application - Cron Jobs
# Health check a cada 5 minutos
*/5 * * * * /opt/samureye/scripts/health-check.sh >> /var/log/samureye/health-check.log 2>&1

# Backup diário às 3h
0 3 * * * /opt/samureye/scripts/backup.sh >> /var/log/samureye/backup.log 2>&1

# Limpeza de logs temporários semanalmente
0 2 * * 0 find /var/log/samureye -name "*.log.*" -mtime +7 -delete
EOF

# ============================================================================
# 14. CONFIGURAÇÃO FAIL2BAN
# ============================================================================

log "🛡️ Configurando Fail2Ban..."

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 5

[samureye-app]
enabled = true
port = 3000,3001
logpath = /var/log/samureye/app.log
maxretry = 10
findtime = 600
bantime = 3600
EOF

systemctl enable fail2ban
systemctl start fail2ban

# ============================================================================
# 15. ARQUIVO DE CREDENCIAIS
# ============================================================================

log "📋 Criando arquivo de credenciais..."

cat > "$APP_DIR/CREDENTIALS.txt" << EOF
CREDENCIAIS DO SERVIDOR VLXSAM02
================================

Sistema:
- IP: 172.24.1.152
- Usuário: $APP_USER
- Senha: $APP_PASSWORD
- SSH: ssh $APP_USER@172.24.1.152

Aplicação:
- Diretório: $APP_DIR
- Logs: $LOG_DIR
- Config: /etc/samureye/.env

Serviços:
- App Principal: http://localhost:3000
- Scanner: http://localhost:3001

PM2 Commands:
- Status: pm2 status
- Logs: pm2 logs
- Restart: pm2 restart all
- Monitor: pm2 monit

Scripts Úteis:
- Health Check: $APP_DIR/scripts/health-check.sh
- Conectividade: $APP_DIR/scripts/test-connectivity.sh
- Dependências: $APP_DIR/scripts/install-dependencies.sh

IMPORTANTE:
- Altere as senhas padrão
- Configure variáveis em /etc/samureye/.env
- Instale o código da aplicação em $APP_DIR/SamurEye
EOF

chmod 600 "$APP_DIR/CREDENTIALS.txt"
chown "$APP_USER:$APP_USER" "$APP_DIR/CREDENTIALS.txt"

# ============================================================================
# 16. FINALIZAÇÃO
# ============================================================================

# Ajustar permissões finais
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chown -R "$APP_USER:$APP_USER" "$LOG_DIR"

log "✅ Instalação do vlxsam02 concluída com sucesso!"

echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "=================="
echo ""
echo "1. Configurar variáveis de ambiente:"
echo "   sudo nano /etc/samureye/.env"
echo ""
echo "2. Copiar código da aplicação:"
echo "   git clone <repo> $APP_DIR/SamurEye"
echo "   chown -R $APP_USER:$APP_USER $APP_DIR/SamurEye"
echo ""
echo "3. Instalar dependências da aplicação:"
echo "   cd $APP_DIR/SamurEye"
echo "   sudo -u $APP_USER $APP_DIR/scripts/install-dependencies.sh"
echo ""
echo "4. Executar migrações do banco:"
echo "   sudo -u $APP_USER npm run db:push"
echo ""
echo "5. Iniciar aplicação:"
echo "   sudo -u $APP_USER pm2 start $APP_DIR/ecosystem.config.js"
echo "   sudo -u $APP_USER pm2 save"
echo ""
echo "6. Verificar instalação:"
echo "   $APP_DIR/scripts/health-check.sh"
echo "   $APP_DIR/scripts/test-connectivity.sh"
echo ""
echo "🎯 CREDENCIAIS:"
echo "   Usuário: $APP_USER"
echo "   Senha: $APP_PASSWORD"
echo "   Detalhes: $APP_DIR/CREDENTIALS.txt"
echo ""
echo "🌐 ENDPOINTS LOCAIS:"
echo "   App: http://localhost:3000"
echo "   Scanner: http://localhost:3001"
echo "   Health: http://localhost:3000/api/health"
echo ""
echo "⚠️  IMPORTANTE:"
echo "   - Configure /etc/samureye/.env com dados reais"
echo "   - Instale o código da aplicação"
echo "   - Teste conectividade com vlxsam03 (database)"