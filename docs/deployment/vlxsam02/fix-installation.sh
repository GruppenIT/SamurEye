#!/bin/bash

# Script de correção rápida para problemas de instalação do vlxsam02
# Resolve os problemas identificados no log de instalação

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"; exit 1; }

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-installation.sh"
fi

log "🔧 Iniciando correção de problemas na instalação vlxsam02..."

APP_DIR="/opt/samureye"
APP_USER="samureye"

# ============================================================================
# 1. CORRIGIR CONFIGURAÇÃO DO SYSTEMD
# ============================================================================

log "⚡ Corrigindo configuração do systemd..."

# Parar serviço se estiver executando
systemctl stop samureye-app 2>/dev/null || true

# Recriar configuração do systemd com PATH correto
cat > /etc/systemd/system/samureye-app.service << 'EOF'
[Unit]
Description=SamurEye Application (React 18 + Vite + Node.js)
After=network.target
Wants=network.target

[Service]
# Usuário e diretório
User=samureye
Group=samureye
WorkingDirectory=/opt/samureye/SamurEye

# Comando de execução com PATH completo
ExecStart=/usr/bin/env bash -c 'source /etc/samureye/.env && npm run dev'

# Environment
EnvironmentFile=/etc/samureye/.env
Environment=NODE_ENV=development
Environment=PORT=5000
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/opt/samureye/SamurEye/node_modules/.bin

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

systemctl daemon-reload
log "✅ Configuração systemd corrigida"

# ============================================================================
# 2. CORRIGIR CONFIGURAÇÃO DE VARIÁVEIS DE AMBIENTE
# ============================================================================

log "🔧 Corrigindo variáveis de ambiente..."

# Verificar se o arquivo .env existe
if [ ! -f "/etc/samureye/.env" ]; then
    log "Criando arquivo .env básico..."
    cat > /etc/samureye/.env << 'EOF'
# PostgreSQL (vlxsam03)
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod
PGHOST=172.24.1.153
PGPORT=5432
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye_prod

# Redis (vlxsam03)
REDIS_URL=redis://172.24.1.153:6379
REDIS_HOST=172.24.1.153
REDIS_PORT=6379

# MinIO (vlxsam03)
MINIO_ENDPOINT=http://172.24.1.153:9000
MINIO_ACCESS_KEY=samureye
MINIO_SECRET_KEY=SamurEye2024!
MINIO_BUCKET=samureye-storage

# Session
SESSION_SECRET=SamurEye_Secret_2024_vlxsam02_session_key

# Development
NODE_ENV=development
PORT=5000
VITE_API_BASE_URL=http://localhost:5000
VITE_APP_NAME=SamurEye
EOF
    
    chmod 600 /etc/samureye/.env
    chown root:root /etc/samureye/.env
fi

# Link para diretório da aplicação
rm -f "$APP_DIR/.env"
ln -sf /etc/samureye/.env "$APP_DIR/.env"

# Link para diretório SamurEye se existir
if [ -d "$APP_DIR/SamurEye" ]; then
    rm -f "$APP_DIR/SamurEye/.env"
    ln -sf /etc/samureye/.env "$APP_DIR/SamurEye/.env"
fi

log "✅ Variáveis de ambiente configuradas"

# ============================================================================
# 3. CORRIGIR INSTALAÇÃO DA APLICAÇÃO
# ============================================================================

log "📦 Verificando instalação da aplicação..."

# Verificar se o código da aplicação existe
if [ ! -d "$APP_DIR/SamurEye" ]; then
    log "Clonando código da aplicação..."
    cd "$APP_DIR"
    git clone https://github.com/GruppenIT/SamurEye.git SamurEye
    chown -R "$APP_USER:$APP_USER" SamurEye
fi

cd "$APP_DIR/SamurEye"

# Verificar se package.json existe
if [ ! -f "package.json" ]; then
    error "package.json não encontrado em $APP_DIR/SamurEye"
fi

# Reinstalar dependências se necessário
if [ ! -d "node_modules" ]; then
    log "Instalando dependências..."
    sudo -u "$APP_USER" npm install
fi

log "✅ Aplicação verificada"

# ============================================================================
# 4. EXECUTAR MIGRAÇÃO DO BANCO COM VARIÁVEIS CORRETAS
# ============================================================================

log "🗄️ Executando migração do banco de dados..."

# Testar conectividade primeiro
export PGPASSWORD=SamurEye2024!
if psql -h 172.24.1.153 -U samureye -d samureye_prod -c "SELECT 1;" >/dev/null 2>&1; then
    log "✅ Conectividade PostgreSQL OK"
    
    # Executar migração com variáveis de ambiente carregadas
    sudo -u "$APP_USER" bash -c "cd $APP_DIR/SamurEye && source /etc/samureye/.env && npm run db:push" || {
        log "⚠️ Tentando forçar migração..."
        sudo -u "$APP_USER" bash -c "cd $APP_DIR/SamurEye && source /etc/samureye/.env && npm run db:push --force" || {
            log "❌ Falha na migração - verifique configuração do banco vlxsam03"
        }
    }
else
    log "❌ Falha na conectividade PostgreSQL - verifique se vlxsam03 está funcionando"
fi

# ============================================================================
# 5. INICIAR E TESTAR SERVIÇO
# ============================================================================

log "🚀 Iniciando serviço..."

# Habilitar e iniciar serviço
systemctl enable samureye-app
systemctl start samureye-app

# Aguardar inicialização
sleep 10

# Verificar status
if systemctl is-active --quiet samureye-app; then
    log "✅ Serviço iniciado com sucesso"
else
    log "❌ Serviço falhou ao iniciar"
    echo ""
    echo "Status do serviço:"
    systemctl status samureye-app --no-pager -l
    echo ""
    echo "Logs recentes:"
    journalctl -u samureye-app --no-pager -l -n 20
fi

# ============================================================================
# 6. CORRIGIR CONFIGURAÇÕES DE URL
# ============================================================================

log "🔧 Corrigindo configurações de URL..."

# Corrigir URLs que estão causando erro de conexão HTTPS
if [ -f "/etc/samureye/.env" ]; then
    # Backup do arquivo original
    cp /etc/samureye/.env /etc/samureye/.env.backup.$(date +%s)
    
    # Corrigir URLs para desenvolvimento local
    sed -i 's|FRONTEND_URL=https://app.samureye.com.br|FRONTEND_URL=http://172.24.1.152:5000|g' /etc/samureye/.env
    sed -i 's|API_BASE_URL=https://api.samureye.com.br|API_BASE_URL=http://172.24.1.152:5000|g' /etc/samureye/.env
    sed -i 's|VITE_API_BASE_URL=https://api.samureye.com.br|VITE_API_BASE_URL=http://172.24.1.152:5000|g' /etc/samureye/.env
    sed -i 's|CORS_ORIGINS=https://app.samureye.com.br,https://api.samureye.com.br|CORS_ORIGINS=http://172.24.1.152:5000,http://localhost:5000|g' /etc/samureye/.env
    
    # Corrigir permissões do arquivo .env
    chown samureye:samureye /etc/samureye/.env
    chmod 644 /etc/samureye/.env
    
    log "✅ URLs corrigidas para desenvolvimento local"
    log "✅ Permissões do arquivo .env corrigidas"
else
    log "⚠️ Arquivo .env não encontrado"
fi

# ============================================================================
# 7. CORRIGIR INSTALAÇÃO DO NUCLEI
# ============================================================================

log "🔧 Corrigindo instalação do Nuclei..."

cd /tmp
NUCLEI_VERSION="3.2.9"
NUCLEI_ZIP="nuclei_${NUCLEI_VERSION}_linux_amd64.zip"

# Remover instalação anterior
rm -f nuclei /usr/local/bin/nuclei "$NUCLEI_ZIP" 2>/dev/null

if wget -q "https://github.com/projectdiscovery/nuclei/releases/download/v${NUCLEI_VERSION}/$NUCLEI_ZIP"; then
    # Extrair de forma não-interativa
    if unzip -o -q "$NUCLEI_ZIP" 2>/dev/null; then
        if [ -f "nuclei" ]; then
            mv nuclei /usr/local/bin/
            chmod +x /usr/local/bin/nuclei
            if /usr/local/bin/nuclei -version >/dev/null 2>&1; then
                log "✅ Nuclei corrigido com sucesso"
            else
                log "⚠️ Nuclei instalado mas com problemas"
            fi
        fi
        # Limpar arquivos
        rm -f "$NUCLEI_ZIP" README*.md LICENSE.md 2>/dev/null
    else
        log "⚠️ Problema na extração do Nuclei (não crítico)"
    fi
else
    log "⚠️ Falha ao baixar Nuclei (não crítico)"
fi

# ============================================================================
# 8. EXECUTAR TESTES
# ============================================================================

log "🧪 Executando testes finais..."

# Health check
if [ -f "$APP_DIR/scripts/health-check.sh" ]; then
    "$APP_DIR/scripts/health-check.sh"
fi

# Teste de conectividade
if [ -f "$APP_DIR/scripts/test-connectivity.sh" ]; then
    "$APP_DIR/scripts/test-connectivity.sh"
fi

echo ""
echo "🎯 CORREÇÃO CONCLUÍDA!"
echo "====================="
echo ""
echo "Comandos úteis:"
echo "- Status: systemctl status samureye-app"
echo "- Logs: journalctl -u samureye-app -f"
echo "- Health: $APP_DIR/scripts/health-check.sh"
echo "- App: http://localhost:5000"
echo ""