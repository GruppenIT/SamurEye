#!/bin/bash

# Script simplificado de instalação do SamurEye vlxsam02
# Foca especificamente nos problemas de configuração .env

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"; exit 1; }

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./install-simple.sh"
fi

# Configurações
WORKING_DIR="/opt/samureye/SamurEye"
ETC_DIR="/etc/samureye"
SERVICE_USER="samureye"
POSTGRES_HOST="172.24.1.153"
POSTGRES_PORT="5432"
REDIS_HOST="172.24.1.153"
REDIS_PORT="6379"

log "🔧 INSTALAÇÃO SIMPLIFICADA - CORREÇÃO .ENV"

# 1. Verificar estrutura
if [ ! -d "$WORKING_DIR" ]; then
    error "Diretório $WORKING_DIR não existe. Execute o script principal primeiro."
fi

if [ ! -f "$WORKING_DIR/package.json" ]; then
    error "package.json não encontrado. Execute o script principal primeiro."
fi

cd "$WORKING_DIR"

# 2. Verificar e instalar dotenv
log "Verificando dotenv..."
if ! sudo -u $SERVICE_USER npm list dotenv >/dev/null 2>&1; then
    log "Instalando dotenv..."
    sudo -u $SERVICE_USER npm install dotenv
fi

# 3. Criar diretório de configuração
log "Criando diretório de configuração..."
mkdir -p "$ETC_DIR"

# 4. Criar arquivo .env principal
log "Criando arquivo .env..."
cat > "$ETC_DIR/.env" << EOF
# SamurEye Application Configuration
# Generated: $(date)

# Environment
NODE_ENV=production
PORT=5000

# Database (PostgreSQL vlxsam03)
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

# 5. Configurar permissões
log "Configurando permissões..."
chown root:$SERVICE_USER "$ETC_DIR/.env"
chmod 640 "$ETC_DIR/.env"

# 6. Criar links simbólicos
log "Criando links simbólicos..."
rm -f "/opt/samureye/.env" "$WORKING_DIR/.env"
ln -sf "$ETC_DIR/.env" "/opt/samureye/.env"
ln -sf "$ETC_DIR/.env" "$WORKING_DIR/.env"

# Configurar owner dos links
chown -h $SERVICE_USER:$SERVICE_USER "$WORKING_DIR/.env" 2>/dev/null || true

# 7. Verificar se arquivo existe
if [ -f "$WORKING_DIR/.env" ]; then
    log "✅ Arquivo .env criado: $WORKING_DIR/.env"
    log "Tamanho: $(stat -c%s $WORKING_DIR/.env) bytes"
    log "Link para: $(readlink $WORKING_DIR/.env)"
else
    error "Falha ao criar arquivo .env"
fi

# 8. Teste de carregamento
log "Testando carregamento de variáveis..."

cat > "$WORKING_DIR/test-simple.js" << 'EOF'
try {
    console.log('Carregando .env do diretório atual');
    require('dotenv').config();
    
    const required = ['DATABASE_URL', 'PGHOST', 'PGPORT'];
    let success = true;
    
    for (const key of required) {
        if (process.env[key]) {
            console.log(`✅ ${key}: ${key === 'DATABASE_URL' ? process.env[key].substring(0, 30) + '...' : process.env[key]}`);
        } else {
            console.log(`❌ ${key}: NÃO DEFINIDA`);
            success = false;
        }
    }
    
    if (process.env.DATABASE_URL && process.env.DATABASE_URL.includes(':443')) {
        console.log('❌ ERRO: DATABASE_URL contém porta 443');
        process.exit(1);
    }
    
    if (success) {
        console.log('✅ Teste de carregamento: SUCESSO');
    } else {
        console.log('❌ Teste de carregamento: FALHA');
        process.exit(1);
    }
} catch (error) {
    console.log('❌ Erro no teste:', error.message);
    process.exit(1);
}
EOF

cd "$WORKING_DIR"
if sudo -u $SERVICE_USER node test-simple.js; then
    log "✅ Configuração .env funcionando corretamente"
else
    warn "Teste de carregamento falhou, mas arquivo foi criado"
fi

rm -f "$WORKING_DIR/test-simple.js"

log "✅ INSTALAÇÃO SIMPLIFICADA CONCLUÍDA"
log "Arquivo .env disponível em: $WORKING_DIR/.env"
log "Próximo passo: sudo systemctl start samureye-app"