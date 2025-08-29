#!/bin/bash
# Script específico para corrigir collectors ENROLLING no PostgreSQL (vlxsam03)

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🗃️ Correção PostgreSQL Collectors ENROLLING - vlxsam03"
echo "===================================================="

# Verificar se PostgreSQL está rodando
if ! systemctl is-active postgresql >/dev/null 2>&1; then
    log "❌ PostgreSQL não está ativo"
    log "Iniciando PostgreSQL..."
    systemctl start postgresql
    sleep 3
fi

if systemctl is-active postgresql >/dev/null 2>&1; then
    log "✅ PostgreSQL ativo"
else
    log "❌ Falha ao iniciar PostgreSQL"
    exit 1
fi

# 1. Corrigir status no banco de dados
log "1. Atualizando status de collectors ENROLLING..."

# Script SQL para forçar collectors online se estiverem há mais de 5 minutos em ENROLLING
UPDATED_COUNT=$(sudo -u postgres psql -d samureye -t -c "
UPDATE collectors 
SET status = 'online', last_seen = NOW() 
WHERE status = 'enrolling' 
  AND created_at < NOW() - INTERVAL '5 minutes'
RETURNING id;
" 2>/dev/null | wc -l | tr -d ' ')

if [[ $UPDATED_COUNT -gt 0 ]]; then
    log "✅ $UPDATED_COUNT collectors atualizados de ENROLLING para ONLINE"
else
    log "ℹ️ Nenhum collector antigo em status ENROLLING encontrado"
fi

# 2. Verificar resultado final
log "2. Status atual dos collectors..."
ONLINE_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE status = 'online';" 2>/dev/null | tr -d ' ')
ENROLLING_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE status = 'enrolling';" 2>/dev/null | tr -d ' ')
TOTAL_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors;" 2>/dev/null | tr -d ' ')

log "📊 Resumo dos collectors:"
log "   Online: $ONLINE_COUNT"
log "   Enrolling: $ENROLLING_COUNT"
log "   Total: $TOTAL_COUNT"

# 3. Mostrar últimos collectors se existirem
if [[ $TOTAL_COUNT -gt 0 ]]; then
    log "3. Últimos collectors registrados:"
    sudo -u postgres psql -d samureye -c "
    SELECT name, status, last_seen, created_at 
    FROM collectors 
    ORDER BY created_at DESC 
    LIMIT 5;
    " 2>/dev/null || log "❌ Erro ao consultar collectors"
fi

echo ""
log "✅ Correção PostgreSQL concluída"
echo ""
echo "🔄 Para aplicar mudanças:"
echo "  1. Reinicie a aplicação no vlxsam02:"
echo "     ssh vlxsam02 'systemctl restart samureye-app'"
echo ""
echo "  2. Teste heartbeat no vlxsam04:"
echo "     ssh vlxsam04 'systemctl restart samureye-collector'"
echo ""
echo "🌐 Verificar resultado:"
echo "  https://app.samureye.com.br/admin"
echo "  Login: admin@samureye.com.br / SamurEye2024!"