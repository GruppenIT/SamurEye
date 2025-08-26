#!/bin/bash

# Script final de instalação SamurEye vlxsam02
# Versão corrigida que resolve problema do dotenv

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"; exit 1; }

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./install-final.sh"
fi

# Configurações
WORKING_DIR="/opt/samureye/SamurEye"
ETC_DIR="/etc/samureye"
SERVICE_USER="samureye"
POSTGRES_HOST="172.24.1.153"
POSTGRES_PORT="5432"
REDIS_HOST="172.24.1.153"
REDIS_PORT="6379"

echo "🚀 INSTALAÇÃO FINAL SAMUREYE - VLXSAM02"
echo "========================================"
log "Iniciando instalação final corrigida..."

# 1. Verificar se já existe instalação
if [ ! -d "$WORKING_DIR" ]; then
    error "Diretório $WORKING_DIR não existe. Execute o script principal primeiro."
fi

cd "$WORKING_DIR"

# 2. Verificar node_modules
if [ ! -d "node_modules" ]; then
    log "Instalando dependências..."
    sudo -u $SERVICE_USER npm install
fi

# 3. Verificar dotenv especificamente
if ! sudo -u $SERVICE_USER npm list dotenv >/dev/null 2>&1; then
    log "Instalando dotenv..."
    sudo -u $SERVICE_USER npm install dotenv
fi

# 4. Criar .env correto
log "Criando configuração .env..."
mkdir -p "$ETC_DIR"

cat > "$ETC_DIR/.env" << EOF
# SamurEye Application Configuration
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
chown root:$SERVICE_USER "$ETC_DIR/.env"
chmod 640 "$ETC_DIR/.env"

# 6. Criar links
rm -f "/opt/samureye/.env" "$WORKING_DIR/.env"
ln -sf "$ETC_DIR/.env" "/opt/samureye/.env"
ln -sf "$ETC_DIR/.env" "$WORKING_DIR/.env"
chown -h $SERVICE_USER:$SERVICE_USER "$WORKING_DIR/.env" 2>/dev/null || true

# 7. Teste definitivo no diretório correto
log "Executando teste final de configuração..."

cat > "final-test.js" << 'EOF'
console.log('=== TESTE FINAL DE CONFIGURAÇÃO ===');
console.log('Diretório:', process.cwd());
console.log('Usuário:', process.env.USER || process.env.USERNAME || 'unknown');

try {
    // Carregar dotenv
    const dotenv = require('dotenv');
    const result = dotenv.config();
    
    if (result.error) {
        console.log('❌ Erro carregando .env:', result.error.message);
        process.exit(1);
    }
    
    console.log('✅ dotenv carregado com sucesso');
    
    // Verificar variáveis críticas
    const critical = ['DATABASE_URL', 'PGHOST', 'PGPORT', 'SESSION_SECRET'];
    let allGood = true;
    
    critical.forEach(key => {
        if (process.env[key]) {
            if (key === 'DATABASE_URL') {
                console.log(`✅ ${key}: ${process.env[key].substring(0, 35)}...`);
                if (process.env[key].includes(':443')) {
                    console.log('❌ ERRO: DATABASE_URL tem porta 443!');
                    allGood = false;
                }
            } else {
                console.log(`✅ ${key}: ${process.env[key]}`);
            }
        } else {
            console.log(`❌ ${key}: NÃO DEFINIDA`);
            allGood = false;
        }
    });
    
    if (allGood) {
        console.log('✅ CONFIGURAÇÃO PERFEITA - PRONTO PARA USO');
        process.exit(0);
    } else {
        console.log('❌ PROBLEMAS DE CONFIGURAÇÃO DETECTADOS');
        process.exit(1);
    }
    
} catch (error) {
    console.log('❌ ERRO CRÍTICO:', error.message);
    console.log('Stack trace:', error.stack);
    process.exit(1);
}
EOF

# Executar teste final
echo ""
echo "=== EXECUTANDO TESTE FINAL ==="
if sudo -u $SERVICE_USER NODE_ENV=production node final-test.js; then
    log "✅ TESTE FINAL: SUCESSO TOTAL"
    SUCCESS=true
else
    warn "TESTE FINAL: FALHOU"
    SUCCESS=false
fi

# Limpeza
rm -f final-test.js

# 8. Verificar serviço systemd
if [ ! -f "/etc/systemd/system/samureye-app.service" ]; then
    log "Criando serviço systemd..."
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
Environment=PORT=5000
ExecStart=/usr/bin/node server/index.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-app

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$WORKING_DIR /var/log/samureye

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable samureye-app
fi

echo ""
echo "=================== RESULTADO FINAL ==================="
if [ "$SUCCESS" = true ]; then
    log "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    log "✅ Arquivo .env configurado: $WORKING_DIR/.env"
    log "✅ Todas as variáveis carregando corretamente"
    log "✅ Serviço systemd configurado"
    echo ""
    echo "🚀 PRÓXIMOS PASSOS:"
    echo "   sudo systemctl start samureye-app"
    echo "   sudo systemctl status samureye-app"
    echo "   journalctl -u samureye-app -f"
else
    warn "⚠️  INSTALAÇÃO CONCLUÍDA COM PROBLEMAS"
    warn "Arquivo .env criado mas teste de carregamento falhou"
    warn "Verificar manualmente: cat $WORKING_DIR/.env"
fi
echo "======================================================="