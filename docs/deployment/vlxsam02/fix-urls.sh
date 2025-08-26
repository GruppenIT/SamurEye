#!/bin/bash

# Script específico para corrigir URLs que estão causando erro de conexão HTTPS

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "🔧 Corrigindo URLs que estão causando erro ECONNREFUSED na porta 443..."

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    echo "Execute como root: sudo ./fix-urls.sh"
    exit 1
fi

# Verificar se arquivo .env existe
if [ ! -f "/etc/samureye/.env" ]; then
    log "❌ Arquivo .env não encontrado em /etc/samureye/.env"
    exit 1
fi

# Backup do arquivo original
BACKUP_FILE="/etc/samureye/.env.backup.$(date +%s)"
cp /etc/samureye/.env "$BACKUP_FILE"
log "📋 Backup criado em: $BACKUP_FILE"

# Mostrar URLs problemáticas antes da correção
log "URLs atuais que estão causando erro:"
grep -E "(FRONTEND_URL|API_BASE_URL|VITE_API_BASE_URL|CORS_ORIGINS)" /etc/samureye/.env || true

# Corrigir URLs para desenvolvimento local (sem HTTPS)
sed -i 's|FRONTEND_URL=https://app.samureye.com.br|FRONTEND_URL=http://172.24.1.152:5000|g' /etc/samureye/.env
sed -i 's|API_BASE_URL=https://api.samureye.com.br|API_BASE_URL=http://172.24.1.152:5000|g' /etc/samureye/.env
sed -i 's|VITE_API_BASE_URL=https://api.samureye.com.br|VITE_API_BASE_URL=http://172.24.1.152:5000|g' /etc/samureye/.env
sed -i 's|CORS_ORIGINS=https://app.samureye.com.br,https://api.samureye.com.br|CORS_ORIGINS=http://172.24.1.152:5000,http://localhost:5000|g' /etc/samureye/.env

# Mostrar URLs após correção
log "✅ URLs corrigidas:"
grep -E "(FRONTEND_URL|API_BASE_URL|VITE_API_BASE_URL|CORS_ORIGINS)" /etc/samureye/.env

# Reiniciar aplicação para aplicar as mudanças
log "🔄 Reiniciando aplicação para aplicar as mudanças..."
systemctl restart samureye-app

# Aguardar alguns segundos para a aplicação iniciar
sleep 5

# Testar se correção funcionou
log "🧪 Testando se correção funcionou..."
if curl -s http://localhost:5000/api/system/settings | grep -q "systemName"; then
    log "✅ SUCESSO! A API /api/system/settings agora está funcionando!"
else
    log "⚠️  API ainda com problemas, verificar logs:"
    journalctl -u samureye-app --no-pager -n 10
fi

log "🎉 Correção de URLs concluída!"
log "Para monitorar: journalctl -u samureye-app -f"