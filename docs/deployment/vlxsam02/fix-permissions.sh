#!/bin/bash

# Script para corrigir problema de permissões no arquivo .env que está causando falha do serviço

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "🔧 Corrigindo problema de permissões do arquivo .env..."

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    echo "Execute como root: sudo ./fix-permissions.sh"
    exit 1
fi

# Parar o serviço que está falhando
log "🛑 Parando serviço samureye-app..."
systemctl stop samureye-app 2>/dev/null || true

# Verificar se arquivo .env existe
if [ ! -f "/etc/samureye/.env" ]; then
    log "❌ Arquivo .env não encontrado em /etc/samureye/.env"
    exit 1
fi

# Verificar se usuário samureye existe
if ! id "samureye" >/dev/null 2>&1; then
    log "❌ Usuário samureye não existe"
    exit 1
fi

# Mostrar permissões atuais
log "📋 Permissões atuais do arquivo .env:"
ls -la /etc/samureye/.env

# Corrigir permissões
log "🔧 Corrigindo permissões..."
chown samureye:samureye /etc/samureye/.env
chmod 644 /etc/samureye/.env

# Verificar se o link simbólico existe e está correto
if [ -d "/opt/samureye/SamurEye" ]; then
    log "🔗 Verificando link simbólico..."
    if [ -L "/opt/samureye/SamurEye/.env" ]; then
        log "Link simbólico já existe"
    else
        log "Criando link simbólico..."
        ln -sf /etc/samureye/.env /opt/samureye/SamurEye/.env
        chown -h samureye:samureye /opt/samureye/SamurEye/.env
    fi
fi

# Verificar permissões após correção
log "✅ Permissões corrigidas:"
ls -la /etc/samureye/.env

# Verificar se systemd service existe
if [ ! -f "/etc/systemd/system/samureye-app.service" ]; then
    log "❌ Arquivo do serviço systemd não encontrado"
    exit 1
fi

# Recarregar daemon do systemd
log "🔄 Recarregando daemon do systemd..."
systemctl daemon-reload

# Reiniciar serviço
log "🚀 Iniciando serviço samureye-app..."
systemctl start samureye-app

# Aguardar alguns segundos
sleep 5

# Verificar status do serviço
log "📊 Verificando status do serviço..."
if systemctl is-active --quiet samureye-app; then
    log "✅ SUCESSO! Serviço samureye-app está funcionando!"
    
    # Testar API
    sleep 5
    log "🧪 Testando API..."
    if curl -s http://localhost:5000/api/user | grep -q "autenticado"; then
        log "✅ API está respondendo corretamente!"
    else
        log "⚠️  API ainda com problemas, mas serviço está rodando"
    fi
else
    log "❌ Serviço ainda com problemas:"
    systemctl status samureye-app --no-pager -l
    log "Ver logs: journalctl -u samureye-app -f"
fi

log "🎉 Correção de permissões concluída!"