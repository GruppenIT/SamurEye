#!/bin/bash

# Script para limpar collectors duplicados no banco
# Remove todas as entradas e força re-registro limpo

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./clean-duplicate-collectors.sh"
fi

echo "🧹 LIMPEZA DE COLLECTORS DUPLICADOS"
echo "=================================="
echo "Este script irá:"
echo "1. Limpar todas as entradas de collectors no banco"
echo "2. Reiniciar collector vlxsam04 para re-registro"
echo "3. Verificar se apenas 1 collector existe"
echo ""

# Detectar IP do PostgreSQL
POSTGRES_IP=""
if ping -c 1 vlxsam03 >/dev/null 2>&1; then
    POSTGRES_IP=$(ping -c 1 vlxsam03 | grep -oP '(?<=\()\d+\.\d+\.\d+\.\d+(?=\))' | head -1)
elif ping -c 1 172.24.1.153 >/dev/null 2>&1; then
    POSTGRES_IP="172.24.1.153"
else
    error "PostgreSQL vlxsam03 não acessível"
fi

log "📍 PostgreSQL encontrado em: $POSTGRES_IP"

# URLs de teste
DATABASE_URLS=(
    "postgresql://samureye:SamurEye2024!@$POSTGRES_IP:5432/samureye_prod"
    "postgresql://samureye:SamurEye2024!@$POSTGRES_IP:5432/samureye"
    "postgresql://postgres:SamurEye2024!@$POSTGRES_IP:5432/samureye_prod"
    "postgresql://postgres:SamurEye2024!@$POSTGRES_IP:5432/samureye"
)

WORKING_URL=""
for url in "${DATABASE_URLS[@]}"; do
    if echo "SELECT 1;" | psql "$url" >/dev/null 2>&1; then
        WORKING_URL="$url"
        break
    fi
done

if [ -z "$WORKING_URL" ]; then
    error "Nenhuma URL PostgreSQL funcionou"
fi

log "✅ Conectado ao banco: ${WORKING_URL%%:*}://.../${WORKING_URL##*/}"

# Mostrar collectors atuais
log "📊 Collectors atuais no banco:"
psql "$WORKING_URL" -c "SELECT id, name, hostname, ip_address, status, created_at FROM collectors ORDER BY created_at;" || {
    error "Erro ao consultar tabela collectors"
}

# Contar total
TOTAL_COLLECTORS=$(psql "$WORKING_URL" -t -c "SELECT COUNT(*) FROM collectors;" | tr -d ' ')
log "📈 Total de collectors: $TOTAL_COLLECTORS"

if [ "$TOTAL_COLLECTORS" -le 1 ]; then
    log "✅ Apenas $TOTAL_COLLECTORS collector encontrado - nenhuma limpeza necessária"
    exit 0
fi

echo ""
warn "⚠️ ATENÇÃO: $TOTAL_COLLECTORS collectors encontrados (esperado: 1)"
echo ""
read -p "Confirma limpeza completa? (digite 'SIM' para confirmar): " confirmacao

if [ "$confirmacao" != "SIM" ]; then
    log "Operação cancelada pelo usuário"
    exit 0
fi

# Limpeza completa da tabela collectors
log "🗑️ Limpando tabela collectors..."

psql "$WORKING_URL" -c "DELETE FROM collectors;" || {
    error "Erro ao limpar tabela collectors"
}

log "✅ Tabela collectors limpa"

# Verificar limpeza
REMAINING=$(psql "$WORKING_URL" -t -c "SELECT COUNT(*) FROM collectors;" | tr -d ' ')
if [ "$REMAINING" -eq 0 ]; then
    log "✅ Limpeza confirmada - 0 collectors no banco"
else
    error "Limpeza falhou - ainda há $REMAINING collectors"
fi

# Reiniciar collector vlxsam04 para re-registro
log "🔄 Reiniciando collector vlxsam04 via SSH..."

if ssh -o ConnectTimeout=5 vlxsam04 "systemctl restart samureye-collector" 2>/dev/null; then
    log "✅ Collector vlxsam04 reiniciado via SSH"
else
    warn "SSH falhou - instrução manual:"
    echo ""
    echo "Execute no vlxsam04:"
    echo "sudo systemctl restart samureye-collector"
    echo ""
fi

# Aguardar re-registro
log "⏱️ Aguardando re-registro (60 segundos)..."
sleep 60

# Verificar se o collector se registrou
NEW_COUNT=$(psql "$WORKING_URL" -t -c "SELECT COUNT(*) FROM collectors;" | tr -d ' ')
log "📊 Collectors após re-registro: $NEW_COUNT"

if [ "$NEW_COUNT" -eq 1 ]; then
    log "✅ Perfeito! Exatamente 1 collector registrado"
    
    # Mostrar detalhes do collector
    log "📋 Detalhes do collector registrado:"
    psql "$WORKING_URL" -c "SELECT id, name, hostname, ip_address, status, created_at FROM collectors;"
    
elif [ "$NEW_COUNT" -eq 0 ]; then
    warn "⚠️ Nenhum collector registrado ainda"
    echo ""
    echo "Verificar logs no vlxsam04:"
    echo "ssh vlxsam04 'journalctl -u samureye-collector -f'"
    
else
    error "❌ Problema: $NEW_COUNT collectors (esperado: 1)"
fi

echo ""
log "✅ Limpeza de collectors concluída!"
echo ""
echo "🔗 Verificar interface:"
echo "   https://app.samureye.com.br/admin/collectors"
echo ""
echo "📝 Monitorar vlxsam04:"
echo "   ssh vlxsam04 'journalctl -u samureye-collector -f'"

exit 0