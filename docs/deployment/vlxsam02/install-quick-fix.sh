#!/bin/bash

# ============================================================================
# CORREÇÃO RÁPIDA - RECRIAR DIRETÓRIO SAMUREYE
# Script para recriar apenas o diretório que foi deletado
# ============================================================================

set -euo pipefail

# Variáveis
readonly WORKING_DIR="/opt/samureye/SamurEye"
readonly ETC_DIR="/etc/samureye"
readonly SERVICE_USER="samureye"

# Função de logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

echo "🔧 CORREÇÃO RÁPIDA - DIRETÓRIO SAMUREYE"
echo "====================================="
log "🎯 Recriando diretório /opt/samureye/SamurEye..."

# 1. Verificar se é root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script deve ser executado como root"
    exit 1
fi

# 2. Verificar se usuário existe
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "❌ Usuário $SERVICE_USER não existe"
    log "Criando usuário $SERVICE_USER..."
    useradd -r -s /bin/bash -d /opt/samureye -m "$SERVICE_USER"
    echo "✅ Usuário criado"
fi

# 3. Criar estrutura de diretórios
log "📁 Criando estrutura de diretórios..."
mkdir -p /opt/samureye
mkdir -p "$WORKING_DIR"
mkdir -p "$ETC_DIR"

# 4. Configurar permissões
log "🔐 Configurando permissões..."
chown -R $SERVICE_USER:$SERVICE_USER /opt/samureye
chmod 755 /opt/samureye
chmod 755 "$WORKING_DIR"

# 5. Verificar se arquivo .env existe
if [ ! -f "$ETC_DIR/.env" ]; then
    log "📝 Criando arquivo .env..."
    cat > "$ETC_DIR/.env" << EOF
# Configuração SamurEye - vlxsam02
NODE_ENV=development
PORT=5000

# Configuração do banco PostgreSQL (vlxsam03)
PGHOST=172.24.1.153
PGPORT=5432
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye

# Configuração Redis (vlxsam03)
REDIS_HOST=172.24.1.153
REDIS_PORT=6379

# Configuração de sessão
SESSION_SECRET=SamurEye_Session_Secret_2024_vlxsam02

# Configuração do servidor
FRONTEND_URL=https://samureye.com.br
API_BASE_URL=https://api.samureye.com.br

# Configuração de upload
MAX_FILE_SIZE=10485760
UPLOAD_PATH=/opt/samureye/uploads

# Configuração de logs
LOG_LEVEL=info
LOG_FILE=/var/log/samureye/app.log

# Certificados e SSL
SSL_CERT_PATH=/etc/ssl/certs/samureye.pem
SSL_KEY_PATH=/etc/ssl/private/samureye.key

# Configuração mTLS para coletores
MTLS_CA_PATH=/opt/samureye/ssl/ca.pem
MTLS_CERT_PATH=/opt/samureye/ssl/server.pem
MTLS_KEY_PATH=/opt/samureye/ssl/server-key.pem

# Configuração de auditoria
AUDIT_LOG_ENABLED=true
AUDIT_LOG_PATH=/var/log/samureye/audit.log
EOF
    chown $SERVICE_USER:$SERVICE_USER "$ETC_DIR/.env"
    chmod 600 "$ETC_DIR/.env"
    echo "✅ Arquivo .env criado"
fi

# 6. Criar links simbólicos para .env
log "🔗 Criando links simbólicos..."
if [ ! -L "/opt/samureye/.env" ]; then
    ln -sf "$ETC_DIR/.env" "/opt/samureye/.env"
    echo "✅ Link criado: /opt/samureye/.env"
fi

if [ ! -L "$WORKING_DIR/.env" ]; then
    ln -sf "$ETC_DIR/.env" "$WORKING_DIR/.env"
    echo "✅ Link criado: $WORKING_DIR/.env"
fi

# 7. Download da aplicação
log "📥 Baixando aplicação SamurEye..."
cd "$WORKING_DIR"

# Verificar se já existe código
if [ -f "package.json" ]; then
    log "ℹ️ Aplicação já existe, atualizando..."
    sudo -u $SERVICE_USER git pull origin main || log "⚠️ Git pull falhou, continuando..."
else
    log "📦 Fazendo download inicial..."
    
    # Limpar diretório se necessário
    rm -rf * .* 2>/dev/null || true
    
    # Clone do repositório
    if ! sudo -u $SERVICE_USER git clone https://github.com/GruppenIT/SamurEye.git .; then
        log "❌ Falha no clone. Tentando download direto..."
        
        # Fallback: download direto
        cd /tmp
        wget -O samureye.zip https://github.com/GruppenIT/SamurEye/archive/refs/heads/main.zip
        unzip -q samureye.zip
        cp -r SamurEye-main/* "$WORKING_DIR/"
        chown -R $SERVICE_USER:$SERVICE_USER "$WORKING_DIR"
        rm -rf samureye.zip SamurEye-main
        cd "$WORKING_DIR"
    fi
fi

# 8. Instalar dependências
if [ -f "package.json" ]; then
    log "📦 Instalando dependências..."
    sudo -u $SERVICE_USER npm install
    echo "✅ Dependências instaladas"
else
    echo "❌ package.json não encontrado após download"
    exit 1
fi

# 9. Verificar server/index.ts
log "🔧 Verificando server/index.ts..."
if [ -f "server/index.ts" ]; then
    # Verificar se dotenv já está importado
    if ! grep -q "import.*dotenv" server/index.ts; then
        log "Adicionando import dotenv..."
        # Backup
        cp server/index.ts server/index.ts.backup
        # Adicionar import no início
        echo 'import "dotenv/config";' > server/index.ts.tmp
        cat server/index.ts >> server/index.ts.tmp
        mv server/index.ts.tmp server/index.ts
        chown $SERVICE_USER:$SERVICE_USER server/index.ts
    fi
    echo "✅ server/index.ts configurado"
else
    echo "❌ server/index.ts não encontrado"
fi

# 10. Criar serviço systemd
log "⚙️ Configurando serviço systemd..."
cat > /etc/systemd/system/samureye-app.service << EOF
[Unit]
Description=SamurEye Application Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$WORKING_DIR
Environment=NODE_ENV=development
EnvironmentFile=$ETC_DIR/.env
ExecStart=/usr/bin/npm run dev
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-app

[Install]
WantedBy=multi-user.target
EOF

# 11. Ativar e iniciar serviço
log "🚀 Ativando serviço..."
systemctl daemon-reload
systemctl enable samureye-app

# 12. Teste final
log "🧪 Testando estrutura final..."
echo ""
echo "=== VERIFICAÇÃO FINAL ==="

if [ -d "$WORKING_DIR" ]; then
    echo "✅ Diretório: $WORKING_DIR"
else
    echo "❌ Diretório: $WORKING_DIR (não existe)"
fi

if [ -f "$WORKING_DIR/package.json" ]; then
    echo "✅ Arquivo: package.json"
else
    echo "❌ Arquivo: package.json (não existe)"
fi

if [ -f "$WORKING_DIR/.env" ]; then
    echo "✅ Arquivo: .env ($(readlink -f $WORKING_DIR/.env))"
else
    echo "❌ Arquivo: .env (não existe)"
fi

if [ -f "$WORKING_DIR/server/index.ts" ]; then
    echo "✅ Arquivo: server/index.ts"
else
    echo "❌ Arquivo: server/index.ts (não existe)"
fi

# Verificar permissões
owner=$(stat -c '%U' "$WORKING_DIR")
echo "✅ Proprietário: $owner"

echo ""
log "✅ CORREÇÃO RÁPIDA CONCLUÍDA!"
log "🎯 Diretório $WORKING_DIR recriado"
log "📁 Estrutura de arquivos restaurada"
log "🔧 Para iniciar: systemctl start samureye-app"
log "📋 Para logs: journalctl -u samureye-app -f"

echo ""
echo "================== PRÓXIMOS PASSOS =================="
echo "1. systemctl start samureye-app    # Iniciar serviço"
echo "2. systemctl status samureye-app   # Verificar status"
echo "3. journalctl -u samureye-app -f   # Ver logs"
echo "=================================================="