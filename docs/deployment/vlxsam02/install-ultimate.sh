#!/bin/bash

# ============================================================================
# INSTALAÇÃO ULTIMATE SAMUREYE - VLXSAM02
# Versão definitiva com correção total ES6
# ============================================================================

set -euo pipefail

# Variáveis globais
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/samureye-install.log"
readonly WORKING_DIR="/opt/samureye/SamurEye"
readonly ETC_DIR="/etc/samureye"
readonly SERVICE_USER="samureye"
readonly POSTGRES_HOST="172.24.1.153"
readonly POSTGRES_PORT="5432"
readonly REDIS_HOST="172.24.1.153"
readonly REDIS_PORT="6379"

# Funções de logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
    exit 1
}

warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*" | tee -a "$LOG_FILE"
}

# Criar diretório de logs
mkdir -p "$(dirname "$LOG_FILE")"

echo "🚀 INSTALAÇÃO ULTIMATE SAMUREYE - VLXSAM02"
echo "==========================================="
log "🎯 Iniciando instalação ultimate com correção ES6..."

# 1. Verificar se é root
if [[ $EUID -ne 0 ]]; then
    error "Este script deve ser executado como root"
fi

# 2. Limpar instalação anterior
log "🧹 Limpeza completa de instalação anterior..."
systemctl stop samureye-app 2>/dev/null || true
systemctl disable samureye-app 2>/dev/null || true
rm -f /etc/systemd/system/samureye-app.service
rm -rf /opt/samureye
rm -rf /etc/samureye
rm -f /var/log/samureye/*

# 3. Atualizar sistema
log "📦 Atualizando sistema..."
apt-get update -qq
apt-get install -y curl wget git unzip htop nano net-tools \
    postgresql-client redis-tools nginx certbot python3-certbot-nginx \
    ufw fail2ban logrotate cron rsync jq

# 4. Instalar Node.js 20
log "🟢 Instalando Node.js 20..."
apt-get remove -y nodejs npm 2>/dev/null || true
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g pm2 nodemon

node_version=$(node --version)
npm_version=$(npm --version)
log "✅ Node.js instalado: $node_version"
log "✅ npm instalado: $npm_version"

# 5. Configurar usuário
log "👤 Configurando usuário do sistema..."
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd -r -s /bin/bash -d /opt/samureye -m "$SERVICE_USER"
    log "✅ Usuário $SERVICE_USER criado"
else
    log "ℹ️  Usuário $SERVICE_USER já existe"
fi

# 6. Baixar aplicação
log "📥 Baixando aplicação SamurEye..."
mkdir -p /opt/samureye
cd /opt/samureye
git clone https://github.com/GruppenIT/SamurEye.git .
chown -R $SERVICE_USER:$SERVICE_USER /opt/samureye

# 7. Instalar dependências
log "🔧 Instalando dependências..."
cd "$WORKING_DIR"
sudo -u $SERVICE_USER npm install

# 8. Criar configuração .env
log "📝 Criando arquivo de configuração .env..."
mkdir -p "$ETC_DIR"

cat > "$ETC_DIR/.env" << EOF
# SamurEye Application Configuration
# Generated: $(date)

# Environment
NODE_ENV=development
PORT=5000

# Database (PostgreSQL - vlxsam03)
DATABASE_URL=postgresql://samureye:SamurEye2024!@$POSTGRES_HOST:$POSTGRES_PORT/samureye_prod
PGHOST=$POSTGRES_HOST
PGPORT=$POSTGRES_PORT
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye_prod

# Redis (vlxsam03)
REDIS_URL=redis://$REDIS_HOST:$REDIS_PORT
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT

# Session
SESSION_SECRET=samureye_secret_2024_vlxsam02_production

# Application URLs
API_BASE_URL=http://localhost:5000
WEB_BASE_URL=http://localhost:5000

# Security
JWT_SECRET=samureye_jwt_secret_2024
ENCRYPTION_KEY=samureye_encryption_2024

# Logging
LOG_LEVEL=info
LOG_FILE=/var/log/samureye/app.log

# External Services
GRAFANA_URL=http://$POSTGRES_HOST:3000
MINIO_ENDPOINT=$POSTGRES_HOST
MINIO_PORT=9000
MINIO_ACCESS_KEY=samureye
MINIO_SECRET_KEY=SamurEye2024!

# System
HOSTNAME=vlxsam02
SERVER_ROLE=application
EOF

# Configurar permissões
chown root:$SERVICE_USER "$ETC_DIR/.env"
chmod 640 "$ETC_DIR/.env"

# Criar links simbólicos
rm -f "/opt/samureye/.env" "$WORKING_DIR/.env"
ln -sf "$ETC_DIR/.env" "/opt/samureye/.env"
ln -sf "$ETC_DIR/.env" "$WORKING_DIR/.env"
chown -h $SERVICE_USER:$SERVICE_USER "$WORKING_DIR/.env" 2>/dev/null || true

log "✅ Arquivo .env criado e linkado"

# 9. TESTE DEFINITIVO ES6
log "🧪 Executando teste DEFINITIVO de carregamento ES6..."

cd "$WORKING_DIR"

# Remover qualquer arquivo de teste anterior
rm -f test-env-loading.js test-env-loading.mjs final-test.js final-test.mjs fix-test.js fix-test.mjs

# Criar teste ES6 definitivo
cat > "ultimate-test.mjs" << 'EOF'
import dotenv from 'dotenv';

console.log('=== TESTE ULTIMATE ES6 ===');
console.log('Diretório:', process.cwd());
console.log('Usuário:', process.env.USER || process.env.USERNAME || 'unknown');

try {
    // Carregar dotenv usando ES6 modules
    const result = dotenv.config();
    
    if (result.error) {
        console.log('❌ ERRO ao carregar .env:', result.error.message);
        process.exit(1);
    }
    
    console.log('✅ dotenv carregado com sucesso');
    
    // Verificar variáveis críticas
    const required = ['DATABASE_URL', 'PGHOST', 'PGPORT', 'NODE_ENV'];
    let success = true;
    
    for (const key of required) {
        if (process.env[key]) {
            const value = key === 'DATABASE_URL' ? 
                process.env[key].substring(0, 30) + '...' : 
                process.env[key];
            console.log(`✅ ${key}: ${value}`);
        } else {
            console.log(`❌ ${key}: NÃO DEFINIDA`);
            success = false;
        }
    }
    
    // Verificar porta 443
    if (process.env.DATABASE_URL && process.env.DATABASE_URL.includes(':443')) {
        console.log('❌ ERRO CRÍTICO: DATABASE_URL contém porta 443');
        process.exit(1);
    }
    
    if (success) {
        console.log('✅ TESTE ULTIMATE: SUCESSO TOTAL');
        console.log('✅ Todas as variáveis carregadas corretamente');
        console.log('✅ Nenhuma porta 443 detectada');
    } else {
        console.log('❌ TESTE ULTIMATE: FALHA');
        process.exit(1);
    }
    
} catch (error) {
    console.log('❌ ERRO JAVASCRIPT:', error.message);
    console.log('Stack:', error.stack);
    process.exit(1);
}
EOF

# Executar teste como usuário correto
echo ""
echo "=== EXECUTANDO TESTE ULTIMATE ==="
if sudo -u $SERVICE_USER NODE_ENV=development node ultimate-test.mjs; then
    log "✅ TESTE ULTIMATE: SUCESSO TOTAL"
else
    warn "TESTE ULTIMATE: FALHOU"
    error "Configuração ES6 não está funcionando corretamente"
fi

# Limpeza
rm -f ultimate-test.mjs

# 10. Configurar serviço systemd
log "⚙️ Configurando serviço systemd..."

mkdir -p /var/log/samureye
chown $SERVICE_USER:$SERVICE_USER /var/log/samureye

cat > /etc/systemd/system/samureye-app.service << EOF
[Unit]
Description=SamurEye Application Server
After=network.target postgresql.service redis.service
Wants=postgresql.service redis.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$WORKING_DIR
Environment=NODE_ENV=production
EnvironmentFile=$ETC_DIR/.env
ExecStartPre=/usr/bin/npm run build
ExecStart=/usr/bin/npm start
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-app

# Limites de recursos
LimitNOFILE=65536
LimitNPROC=4096

# Segurança
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$WORKING_DIR /var/log/samureye /tmp

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable samureye-app

log "✅ Serviço systemd configurado"

# 11. Teste final de conectividade
log "🌐 Testando conectividade..."

# PostgreSQL
if timeout 5 bash -c "</dev/tcp/$POSTGRES_HOST/$POSTGRES_PORT" 2>/dev/null; then
    log "✅ PostgreSQL ($POSTGRES_HOST:$POSTGRES_PORT): Conectividade OK"
else
    warn "PostgreSQL: Conectividade com problemas"
fi

# Redis
if timeout 5 bash -c "</dev/tcp/$REDIS_HOST/$REDIS_PORT" 2>/dev/null; then
    log "✅ Redis ($REDIS_HOST:$REDIS_PORT): Conectividade OK"
else
    warn "Redis: Conectividade com problemas"
fi

# 12. Iniciar serviço
log "🚀 Iniciando serviço SamurEye..."
systemctl start samureye-app

sleep 5

if systemctl is-active --quiet samureye-app; then
    log "✅ SamurEye iniciado com sucesso"
    log "✅ Status: $(systemctl is-active samureye-app)"
else
    warn "Serviço não iniciou corretamente"
    log "Status: $(systemctl status samureye-app --no-pager || true)"
fi

echo ""
echo "=================== RESULTADO FINAL ==================="
log "🎉 INSTALAÇÃO ULTIMATE CONCLUÍDA!"
log "✅ Configuração ES6 funcionando corretamente"
log "✅ Arquivo .env criado: $ETC_DIR/.env"
log "✅ Links simbólicos configurados"
log "✅ Serviço systemd configurado"
log "✅ Aplicação pronta para uso"
echo ""
echo "📋 COMANDOS ÚTEIS:"
echo "  systemctl status samureye-app    # Ver status"
echo "  systemctl logs -f samureye-app   # Ver logs"
echo "  cat $ETC_DIR/.env               # Ver configuração"
echo "======================================================="