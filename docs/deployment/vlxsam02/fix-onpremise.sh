#!/bin/bash
# Script de correção para vlxsam02 (Application Server) - SamurEye On-Premise

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔧 Correção Application Server vlxsam02 - SamurEye"
echo "================================================"

# 1. Atualizar script de instalação
log "1. Atualizando script de instalação..."
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/install.sh > /tmp/install-vlxsam02.sh
chmod +x /tmp/install-vlxsam02.sh

# 2. Verificar aplicação SamurEye
log "2. Verificando aplicação SamurEye..."
if systemctl is-active samureye-app >/dev/null 2>&1; then
    log "✅ samureye-app ativo"
    
    # Verificar se está respondendo na porta 5000
    if curl -s http://localhost:5000/api/system/settings >/dev/null 2>&1; then
        log "✅ API respondendo na porta 5000"
    else
        log "⚠️ API não responde - reiniciando aplicação..."
        systemctl restart samureye-app
        sleep 5
    fi
else
    log "❌ samureye-app inativo"
    log "  Execute: systemctl start samureye-app"
fi

# 3. Verificar banco de dados PostgreSQL
log "3. Verificando PostgreSQL..."
if systemctl is-active postgresql >/dev/null 2>&1; then
    log "✅ PostgreSQL ativo"
    
    # Testar conexão
    if sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
        log "✅ PostgreSQL acessível"
    else
        log "⚠️ Problema de conexão PostgreSQL"
    fi
else
    log "❌ PostgreSQL inativo"
    systemctl restart postgresql
fi

# 4. Verificar endpoints críticos da API
log "4. Testando endpoints da API..."

API_ENDPOINTS=(
    "http://localhost:5000/api/system/settings"
    "http://localhost:5000/collector-api/heartbeat"
)

for endpoint in "${API_ENDPOINTS[@]}"; do
    if curl -s "$endpoint" >/dev/null 2>&1; then
        log "✅ Endpoint funcionando: $endpoint"
    else
        log "⚠️ Endpoint com problema: $endpoint"
    fi
done

# 5. Verificar logs da aplicação
log "5. Verificando logs recentes..."
if [[ -f /var/log/samureye/app.log ]]; then
    ERRORS=$(tail -50 /var/log/samureye/app.log | grep -i "error\|failed\|exception" | wc -l)
    if [[ $ERRORS -gt 0 ]]; then
        log "⚠️ $ERRORS erros encontrados nos logs"
        echo "  Últimos erros:"
        tail -20 /var/log/samureye/app.log | grep -i "error\|failed\|exception" | tail -3 | sed 's/^/    /'
    else
        log "✅ Logs sem erros críticos"
    fi
else
    log "⚠️ Arquivo de log não encontrado"
fi

# 6. Verificar conectividade com vlxsam01 (Gateway)
log "6. Testando conectividade com Gateway..."
if curl -k -s https://api.samureye.com.br/api/system/settings >/dev/null 2>&1; then
    log "✅ Gateway respondendo corretamente"
else
    log "⚠️ Problema na conectividade com Gateway"
fi

# 7. Status dos collectors registrados
log "7. Verificando collectors no banco..."
COLLECTORS_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors;" 2>/dev/null || echo "0")
log "Collectors registrados: $COLLECTORS_COUNT"

if [[ $COLLECTORS_COUNT -gt 0 ]]; then
    echo "  Status dos collectors:"
    sudo -u postgres psql -d samureye -t -c "SELECT name, status, last_seen FROM collectors ORDER BY last_seen DESC LIMIT 3;" 2>/dev/null | while read line; do
        echo "    $line"
    done
fi

# 8. Status final
log "8. Status dos serviços:"
echo "  samureye-app: $(systemctl is-active samureye-app)"
echo "  postgresql: $(systemctl is-active postgresql)"
echo "  redis: $(systemctl is-active redis 2>/dev/null || echo 'not-installed')"

echo ""
log "✅ Verificação do Application Server concluída"
echo ""
echo "🔍 Para executar correção completa:"
echo "  bash /tmp/install-vlxsam02.sh"
echo ""
echo "🔍 Logs importantes:"
echo "  journalctl -u samureye-app -f"
echo "  tail -f /var/log/samureye/app.log"
echo "  sudo -u postgres psql -d samureye"