#!/bin/bash

# ============================================================================
# CORREÇÃO SERVIÇO SYSTEMD - SAMUREYE VLXSAM02
# Script para diagnosticar e corrigir problemas do serviço
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

echo "🔧 DIAGNÓSTICO SERVIÇO SYSTEMD - SAMUREYE"
echo "======================================="
log "🎯 Diagnosticando problemas do serviço systemd..."

# 1. Verificar se é root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script deve ser executado como root"
    exit 1
fi

# 2. Verificar estrutura
log "📁 Verificando estrutura de arquivos..."
if [ ! -d "$WORKING_DIR" ]; then
    echo "❌ Diretório $WORKING_DIR não encontrado"
    exit 1
fi

if [ ! -f "$WORKING_DIR/package.json" ]; then
    echo "❌ package.json não encontrado"
    exit 1
fi

echo "✅ Estrutura básica OK"

# 3. Verificar usuário
log "👤 Verificando usuário $SERVICE_USER..."
if id "$SERVICE_USER" >/dev/null 2>&1; then
    echo "✅ Usuário $SERVICE_USER existe"
else
    echo "❌ Usuário $SERVICE_USER não existe"
    exit 1
fi

# 4. Verificar permissões
log "🔐 Verificando permissões..."
cd "$WORKING_DIR"
owner=$(stat -c '%U' .)
if [ "$owner" = "$SERVICE_USER" ]; then
    echo "✅ Permissões corretas: $owner"
else
    echo "⚠️ Corrigindo permissões..."
    chown -R $SERVICE_USER:$SERVICE_USER "$WORKING_DIR"
    echo "✅ Permissões corrigidas"
fi

# 5. Verificar .env
log "📄 Verificando arquivo .env..."
if [ -f "$WORKING_DIR/.env" ]; then
    echo "✅ Arquivo .env encontrado: $(ls -la $WORKING_DIR/.env)"
else
    echo "❌ Arquivo .env não encontrado"
    exit 1
fi

# 6. Verificar scripts npm
log "📝 Verificando scripts package.json..."
cd "$WORKING_DIR"

if grep -q '"build"' package.json; then
    echo "✅ Script build encontrado"
else
    echo "❌ Script build não encontrado"
    echo "Conteúdo scripts atual:"
    cat package.json | jq .scripts 2>/dev/null || grep -A 10 '"scripts"' package.json
fi

if grep -q '"start"' package.json; then
    echo "✅ Script start encontrado"
else
    echo "❌ Script start não encontrado"
fi

# 7. Testar build
log "🔨 Testando build da aplicação..."
cd "$WORKING_DIR"

echo "Executando: sudo -u $SERVICE_USER npm run build"
if sudo -u $SERVICE_USER npm run build; then
    echo "✅ Build executado com sucesso"
else
    echo "❌ Build falhou"
    echo "Vamos verificar o que há disponível..."
    echo "Scripts disponíveis:"
    sudo -u $SERVICE_USER npm run 2>&1 | grep -A 20 "available via" || true
fi

# 8. Verificar status atual do serviço
log "⚙️ Verificando status do serviço..."
echo ""
echo "=== STATUS SYSTEMD ==="
systemctl status samureye-app --no-pager || true
echo ""
echo "=== LOGS RECENTES ==="
journalctl -u samureye-app --no-pager -n 20 || true

# 9. Tentar correção do serviço
log "🔧 Corrigindo arquivo de serviço..."

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
ExecStart=/usr/bin/npm run dev
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

[Install]
WantedBy=multi-user.target
EOF

# 10. Recarregar e tentar iniciar
log "🔄 Recarregando configuração systemd..."
systemctl daemon-reload

log "🚀 Tentando iniciar serviço..."
systemctl stop samureye-app 2>/dev/null || true
systemctl start samureye-app

sleep 3

# 11. Verificar resultado
echo ""
echo "=== RESULTADO FINAL ==="
if systemctl is-active --quiet samureye-app; then
    log "✅ SERVIÇO INICIADO COM SUCESSO!"
    echo "✅ Status: $(systemctl is-active samureye-app)"
    echo ""
    echo "📋 COMANDOS ÚTEIS:"
    echo "  systemctl status samureye-app     # Ver status"
    echo "  journalctl -u samureye-app -f     # Ver logs em tempo real"
    echo "  systemctl restart samureye-app    # Reiniciar"
else
    log "❌ SERVIÇO AINDA COM PROBLEMAS"
    echo ""
    echo "=== STATUS ATUAL ==="
    systemctl status samureye-app --no-pager || true
    echo ""
    echo "=== LOGS DE ERRO ==="
    journalctl -u samureye-app --no-pager -n 10 || true
fi

echo ""
echo "================== RESUMO =================="
log "🔧 Diagnóstico do serviço concluído"
log "📁 Diretório: $WORKING_DIR"
log "👤 Usuário: $SERVICE_USER"
log "📄 Arquivo .env: OK"
log "🎯 Próximo passo: Verificar logs se não funcionou"
echo "============================================="