#!/bin/bash

# Script de instalação para vlxsam02 - Frontend + Backend Node.js
# Servidor: vlxsam02 (172.24.1.152)

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Verificar se está no diretório correto
if [ ! -f "package.json" ]; then
    error "Execute este script no diretório que contém package.json (/opt/samureye/SamurEye)"
fi

log "🚀 Iniciando instalação da aplicação SamurEye no vlxsam02..."

# 1. Verificar Node.js e npm
info "Verificando Node.js e npm..."
node --version || error "Node.js não encontrado"
npm --version || error "npm não encontrado"

# 2. Instalar dependências
log "📦 Instalando dependências Node.js..."
npm install

# 3. Verificar variáveis de ambiente necessárias
log "🔧 Verificando variáveis de ambiente..."

# Arquivo de ambiente
ENV_FILE="/opt/samureye/.env"
if [ ! -f "$ENV_FILE" ]; then
    log "Criando arquivo de ambiente..."
    cat > "$ENV_FILE" << 'EOF'
# SamurEye - Variáveis de Ambiente
NODE_ENV=production
PORT=3000

# Database (vlxsam03)
DATABASE_URL="postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod"

# Redis (vlxsam03)  
REDIS_URL="redis://172.24.1.153:6379"

# MinIO (vlxsam03)
MINIO_ENDPOINT="172.24.1.153"
MINIO_PORT="9000"
MINIO_ACCESS_KEY="samureye"
MINIO_SECRET_KEY="SamurEye2024!"

# Delinea Secret Server
DELINEA_BASE_URL="https://gruppenztna.secretservercloud.com"
DELINEA_RULE_NAME="SamurEye Integration"

# Scanner Service
SCANNER_SERVICE_URL="http://localhost:8080"

# Session
SESSION_SECRET="samureye-super-secret-key-2024"

# NGINX Frontend URL
FRONTEND_URL="https://app.samureye.com.br"
EOF
    chmod 600 "$ENV_FILE"
    log "Arquivo .env criado em $ENV_FILE"
fi

# 4. Criar links simbólicos para o arquivo .env
ln -sf "$ENV_FILE" .env 2>/dev/null || true
log "Link simbólico para .env criado"

# 5. Build da aplicação
log "🔨 Fazendo build da aplicação..."
npm run build 2>/dev/null || warn "Build falhou - pode ser normal em desenvolvimento"

# 6. Executar migrações do banco
log "🗃️ Executando migrações do banco de dados..."
npm run db:push || warn "Migrações falharam - verificar conexão com vlxsam03"

# 7. Criar estrutura de diretórios
log "📁 Criando estrutura de diretórios..."
mkdir -p /opt/samureye/logs
mkdir -p /opt/samureye/temp
mkdir -p /opt/samureye/uploads
chown -R samureye:samureye /opt/samureye

# 8. Criar serviço systemd
log "⚙️ Criando serviço systemd..."
cat > /etc/systemd/system/samureye-app.service << EOF
[Unit]
Description=SamurEye BAS Platform - Node.js Application
After=network.target
Requires=network.target

[Service]
Type=simple
User=samureye
Group=samureye
WorkingDirectory=/opt/samureye/SamurEye
EnvironmentFile=/opt/samureye/.env
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=samureye-app

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/samureye

[Install]
WantedBy=multi-user.target
EOF

# 9. Criar script de start para npm
log "📜 Criando script de start..."
cat > package-start.json << 'EOF'
{
  "scripts": {
    "start": "NODE_ENV=production node server/index.js",
    "dev": "NODE_ENV=development tsx server/index.ts"
  }
}
EOF

# Adicionar script start ao package.json se não existir
if ! grep -q '"start"' package.json; then
    log "Adicionando script start ao package.json..."
    npm pkg set scripts.start="NODE_ENV=production tsx server/index.ts"
fi

# 10. Habilitar e iniciar serviço
systemctl daemon-reload
systemctl enable samureye-app
log "Serviço samureye-app habilitado"

# 11. Configurar firewall
log "🔥 Configurando firewall..."
ufw allow 3000/tcp comment "SamurEye App"
ufw --force enable

# 12. Verificar dependências do sistema
log "🔍 Verificando dependências do sistema..."
command -v curl >/dev/null || (apt-get update && apt-get install -y curl)
command -v git >/dev/null || apt-get install -y git

# 13. Criar script de status
cat > /opt/samureye/check-app-status.sh << 'EOF'
#!/bin/bash
echo "=== STATUS APLICAÇÃO SAMUREYE ==="
echo "Data: $(date)"
echo ""

echo "🔧 SERVIÇO:"
systemctl is-active samureye-app && echo "✅ Rodando" || echo "❌ Parado"

echo ""
echo "🌐 CONECTIVIDADE:"
curl -s http://localhost:3000/api/health 2>/dev/null && echo "✅ API respondendo" || echo "❌ API não responde"

echo ""
echo "📊 RECURSOS:"
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "RAM: $(free -h | awk 'NR==2{printf "%.1f%%", $3/$2*100}')"
echo "Disco: $(df -h /opt | awk 'NR==2 {print $5}')"

echo ""
echo "📝 LOGS (últimas 5 linhas):"
journalctl -u samureye-app -n 5 --no-pager
EOF

chmod +x /opt/samureye/check-app-status.sh

log "✅ Instalação concluída!"

echo ""
echo "🎯 PRÓXIMOS PASSOS:"
echo ""
echo "1. Verificar variáveis de ambiente:"
echo "   nano /opt/samureye/.env"
echo ""
echo "2. Iniciar aplicação:"
echo "   sudo systemctl start samureye-app"
echo ""
echo "3. Verificar status:"
echo "   sudo /opt/samureye/check-app-status.sh"
echo ""
echo "4. Ver logs em tempo real:"
echo "   sudo journalctl -u samureye-app -f"
echo ""
echo "5. Testar API:"
echo "   curl http://localhost:3000/api/health"
echo ""
echo "📍 A aplicação ficará disponível em:"
echo "   - Local: http://localhost:3000"
echo "   - Externa: https://app.samureye.com.br (via NGINX)"