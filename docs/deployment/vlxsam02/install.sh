#!/bin/bash

# SamurEye vlxsam02 - Application Server Installation
# Servidor: vlxsam02 (172.24.1.152)
# Função: React 18 + Vite + TypeScript + Node.js Express + Scanner Service

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
    sqlite3 \
    postgresql-client \
    wscat

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

# Configurar desenvolvimento com Vite
log "Configurando ambiente de desenvolvimento..."
npm install -g tsx typescript
npm cache clean --force

# Não é mais necessário PM2 - usando systemd service
log "PM2 substituído por systemd service"

# ============================================================================
# 4. CONFIGURAÇÃO DE FIREWALL
# ============================================================================

log "🔥 Configurando firewall UFW..."

# Configurar UFW
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH e porta da aplicação unificada
ufw allow ssh
ufw allow 5000/tcp comment "SamurEye App (Vite)"

# Ativar firewall
ufw --force enable

log "Firewall configurado: SSH (22), App (5000)"

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

# Instalar Masscan
log "Instalando Masscan..."
apt-get install -y masscan

# Verificar instalações
nmap --version | head -1
nuclei --version
masscan --version | head -1

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
# Stack: React 18 + Vite + TypeScript + Node.js Express + Drizzle ORM

# Application (Vite Dev Server)
NODE_ENV=development
PORT=5000

# Database (Neon Database)
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod
PGHOST=172.24.1.153
PGPORT=5432
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye_prod

# Session Management
SESSION_SECRET=samureye-super-secret-session-key-2024-change-this

# Replit Authentication (for regular users)
REPL_ID=your_replit_app_id
ISSUER_URL=https://replit.com/oidc
REPLIT_DOMAINS=app.samureye.com.br,api.samureye.com.br

# Object Storage (Google Cloud Storage Integration)
DEFAULT_OBJECT_STORAGE_BUCKET_ID=repl-default-bucket-your-repl-id
PUBLIC_OBJECT_SEARCH_PATHS=/repl-default-bucket-your-repl-id/public
PRIVATE_OBJECT_DIR=/repl-default-bucket-your-repl-id/.private

# Delinea Secret Server (Optional)
DELINEA_API_KEY=your_delinea_api_key_here
DELINEA_BASE_URL=https://gruppenztna.secretservercloud.com
DELINEA_RULE_NAME=SamurEye Integration

# Scanner Tools (Integrated)
NMAP_PATH=/usr/bin/nmap
NUCLEI_PATH=/usr/local/bin/nuclei
MASSCAN_PATH=/usr/bin/masscan

# Logging
LOG_LEVEL=info
LOG_DIR=/var/log/samureye

# Multi-tenant Configuration
TENANT_ISOLATION=true
DEFAULT_TENANT_SLUG=default

# Admin Authentication (Local System)
ADMIN_EMAIL=admin@samureye.com.br
ADMIN_PASSWORD=SamurEye2024!

# Frontend URLs
FRONTEND_URL=https://app.samureye.com.br
API_BASE_URL=https://api.samureye.com.br

# File Upload & Object Storage
UPLOAD_MAX_SIZE=100MB
UPLOAD_DIR=/opt/samureye/uploads

# Monitoring & Integration
GRAFANA_URL=http://172.24.1.153:3000
FORTISIEM_HOST=your_fortisiem_host
FORTISIEM_PORT=514

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# CORS
CORS_ORIGINS=https://app.samureye.com.br,https://api.samureye.com.br

# Development (Vite specific)
VITE_API_BASE_URL=https://api.samureye.com.br
VITE_APP_NAME=SamurEye
EOF

chmod 600 /etc/samureye/.env
chown root:root /etc/samureye/.env

# Link para diretório da aplicação
ln -sf /etc/samureye/.env "$APP_DIR/.env"

# ============================================================================
# 8. CONFIGURAÇÃO SYSTEMD SERVICE
# ============================================================================

log "⚡ Configurando systemd service..."

# Systemd service para aplicação SamurEye unificada
cat > /etc/systemd/system/samureye-app.service << 'EOF'
[Unit]
Description=SamurEye Application (React 18 + Vite + Node.js)
After=network.target
Wants=network.target

[Service]
# Usuário e diretório
User=samureye
Group=samureye
WorkingDirectory=/opt/samureye

# Comando de execução (Vite dev server)
ExecStart=/usr/bin/npm run dev

# Environment
EnvironmentFile=/etc/samureye/.env
Environment=NODE_ENV=development
Environment=PORT=5000

# Restart policy
Restart=always
RestartSec=10
StartLimitInterval=60s
StartLimitBurst=3

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-app

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/samureye /var/log/samureye /tmp

# Limits
LimitNOFILE=65535
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd
systemctl daemon-reload

# Habilitar serviço para iniciar no boot
systemctl enable samureye-app

log "Systemd service configurado e habilitado"

# ============================================================================
# 9. CONFIGURAÇÃO APLICAÇÃO E DEPENDÊNCIAS
# ============================================================================

log "📦 Configurando aplicação SamurEye..."

# Criar package.json básico para instalação
cat > "$APP_DIR/package.json" << 'EOF'
{
  "name": "samureye-platform",
  "version": "1.0.0",
  "description": "SamurEye Breach & Attack Simulation Platform",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "typecheck": "tsc --noEmit",
    "db:push": "drizzle-kit push",
    "db:studio": "drizzle-kit studio"
  },
  "dependencies": {
    "@google-cloud/storage": "^7.7.0",
    "@hookform/resolvers": "^3.3.2",
    "@neondatabase/serverless": "^0.9.0",
    "@radix-ui/react-accordion": "^1.1.2",
    "@radix-ui/react-alert-dialog": "^1.0.5",
    "@radix-ui/react-avatar": "^1.0.4",
    "@radix-ui/react-checkbox": "^1.0.4",
    "@radix-ui/react-dialog": "^1.0.5",
    "@radix-ui/react-dropdown-menu": "^2.0.6",
    "@radix-ui/react-hover-card": "^1.0.7",
    "@radix-ui/react-label": "^2.0.2",
    "@radix-ui/react-popover": "^1.0.7",
    "@radix-ui/react-progress": "^1.0.3",
    "@radix-ui/react-select": "^2.0.0",
    "@radix-ui/react-separator": "^1.0.3",
    "@radix-ui/react-slot": "^1.0.2",
    "@radix-ui/react-switch": "^1.0.3",
    "@radix-ui/react-tabs": "^1.0.4",
    "@radix-ui/react-toast": "^1.1.5",
    "@radix-ui/react-tooltip": "^1.0.7",
    "@tanstack/react-query": "^5.17.0",
    "@types/express": "^4.17.21",
    "@types/express-session": "^1.17.10",
    "@types/node": "^20.10.6",
    "@types/react": "^18.2.46",
    "@types/react-dom": "^18.2.18",
    "@types/ws": "^8.5.10",
    "@vitejs/plugin-react": "^4.2.1",
    "axios": "^1.6.2",
    "class-variance-authority": "^0.7.0",
    "clsx": "^2.0.0",
    "cmdk": "^0.2.0",
    "connect-pg-simple": "^9.0.1",
    "date-fns": "^3.0.6",
    "drizzle-kit": "^0.20.7",
    "drizzle-orm": "^0.29.1",
    "drizzle-zod": "^0.5.1",
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "lucide-react": "^0.303.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-hook-form": "^7.48.2",
    "tailwind-merge": "^2.2.0",
    "tailwindcss": "^3.4.0",
    "tailwindcss-animate": "^1.0.7",
    "tsx": "^4.6.2",
    "typescript": "^5.3.3",
    "vite": "^5.0.10",
    "wouter": "^3.0.0",
    "ws": "^8.16.0",
    "zod": "^3.22.4"
  },
  "devDependencies": {
    "@types/connect-pg-simple": "^7.0.3",
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.32"
  }
}
EOF

chown "$APP_USER:$APP_USER" "$APP_DIR/package.json"

# Instalar dependências quando o código estiver disponível
log "Nota: dependências serão instaladas após clonagem do código fonte"

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

# Verificar serviço systemd
echo "⚡ SYSTEMD SERVICES:"
if systemctl is-active --quiet samureye-app; then
    echo "✅ samureye-app: $(systemctl is-active samureye-app)"
else
    echo "❌ samureye-app: $(systemctl is-active samureye-app)"
fi

# Verificar endpoints
echo ""
echo "🌐 ENDPOINTS:"
if curl -f -s http://localhost:5000/api/admin/stats >/dev/null 2>&1; then
    echo "✅ App (5000): Respondendo"
else
    echo "❌ App (5000): Não responde"
fi

if curl -f -s http://localhost:5000/api/system/settings >/dev/null 2>&1; then
    echo "✅ System API (5000): Respondendo"
else
    echo "❌ System API (5000): Não responde"
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

# Verificar se é possível executar o dev server
if npm run dev --version >/dev/null 2>&1; then
    log "Vite dev server configurado"
else
    log "Vite dev server não configurado ainda (normal antes da clonagem do código)"
fi

log "✅ Dependências instaladas com sucesso!"
EOF

chmod +x "$APP_DIR/scripts/install-dependencies.sh"

chown -R "$APP_USER:$APP_USER" "$APP_DIR/scripts"

# ============================================================================
# 11. FINALIZAÇÃO DA INSTALAÇÃO
# ============================================================================

log "⚙️ Finalizando instalação..."

# Criar arquivos de configuração básicos para desenvolvimento
cat > "$APP_DIR/vite.config.ts" << 'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 5000,
    proxy: {
      '/api': {
        target: 'http://localhost:5000',
        changeOrigin: true
      },
      '/ws': {
        target: 'ws://localhost:5000',
        ws: true
      }
    }
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './client/src'),
      '@shared': path.resolve(__dirname, './shared'),
      '@assets': path.resolve(__dirname, './attached_assets')
    }
  }
})
EOF

chown "$APP_USER:$APP_USER" "$APP_DIR/vite.config.ts"

log "Systemd service configurado"

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
port = 5000
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
- App Unificado: http://localhost:5000

Systemd Commands:
- Status: systemctl status samureye-app
- Logs: journalctl -u samureye-app -f
- Restart: systemctl restart samureye-app
- Stop: systemctl stop samureye-app

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
echo "   systemctl start samureye-app"
echo "   systemctl status samureye-app"
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
echo "   App Unificado: http://localhost:5000"
echo "   API: http://localhost:5000/api"
echo "   Health: http://localhost:5000/api/health"
echo ""
echo "⚠️  IMPORTANTE:"
echo "   - Configure /etc/samureye/.env com dados reais"
echo "   - Instale o código da aplicação"
echo "   - Teste conectividade com vlxsam03 (database)"