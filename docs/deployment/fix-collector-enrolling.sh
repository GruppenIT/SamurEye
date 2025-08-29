#!/bin/bash
# Script específico para corrigir collectors presos em status ENROLLING

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔧 Correção para Collectors ENROLLING - SamurEye"
echo "==============================================="

HOSTNAME=$(hostname)

case $HOSTNAME in
    "vlxsam02")
        log "Executando correção no Application Server (vlxsam02)..."
        
        # 1. Corrigir status no banco de dados
        log "1. Atualizando status no banco de dados..."
        sudo -u postgres psql -d samureye -c "
        UPDATE collectors 
        SET status = 'online', last_seen = NOW() 
        WHERE status = 'enrolling';" 2>/dev/null && log "✅ Status atualizado no banco" || log "❌ Falha ao atualizar banco"
        
        # 2. Verificar resultado
        ONLINE_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE status = 'online';" 2>/dev/null | tr -d ' ')
        log "📊 Collectors online após correção: $ONLINE_COUNT"
        
        # 3. Reiniciar aplicação para limpar cache
        log "2. Reiniciando aplicação SamurEye..."
        systemctl restart samureye-app
        sleep 5
        
        if systemctl is-active samureye-app >/dev/null 2>&1; then
            log "✅ Aplicação reiniciada com sucesso"
        else
            log "❌ Falha ao reiniciar aplicação"
        fi
        ;;
        
    "vlxsam04")
        log "Executando correção no Collector (vlxsam04)..."
        
        # 1. Verificar e corrigir endpoint
        COLLECTOR_DIR="/opt/samureye-collector"
        if [[ -f "$COLLECTOR_DIR/collector_agent.py" ]]; then
            if grep -q "/api/collectors/heartbeat" "$COLLECTOR_DIR/collector_agent.py" 2>/dev/null; then
                log "1. Corrigindo endpoint antigo..."
                sed -i 's|/api/collectors/heartbeat|/collector-api/heartbeat|g' "$COLLECTOR_DIR/collector_agent.py"
                log "✅ Endpoint atualizado"
            else
                log "1. Endpoint já está correto"
            fi
        fi
        
        # 2. Forçar heartbeat
        log "2. Enviando heartbeat forçado..."
        source /etc/samureye-collector/.env 2>/dev/null || echo "Arquivo .env não encontrado"
        
        if [[ -n "$COLLECTOR_NAME" ]]; then
            HEARTBEAT_DATA=$(cat <<EOF
{
    "collector_id": "$COLLECTOR_NAME",
    "status": "online",
    "timestamp": "$(date -Iseconds)",
    "telemetry": {
        "cpu_percent": $(awk '{print $1}' /proc/loadavg | awk '{printf "%.1f", $1*100/4}' 2>/dev/null || echo "15.0"),
        "memory_percent": $(free | awk 'NR==2{printf "%.1f", $3*100/$2}' 2>/dev/null || echo "45.0"),
        "disk_percent": $(df / | awk 'NR==2{sub(/%/,"",$5); print $5}' 2>/dev/null || echo "25"),
        "processes": $(ps aux 2>/dev/null | wc -l || echo "125")
    },
    "capabilities": ["nmap", "nuclei", "masscan"]
}
EOF
)

            RESPONSE=$(curl -k -s -w "HTTP:%{http_code}" -X POST \
                -H "Content-Type: application/json" \
                -d "$HEARTBEAT_DATA" \
                --cert "$COLLECTOR_DIR/certs/collector.crt" \
                --key "$COLLECTOR_DIR/certs/collector.key" \
                "https://api.samureye.com.br/collector-api/heartbeat" 2>/dev/null || echo "HTTP:000")
                
            HTTP_CODE=$(echo "$RESPONSE" | grep -o "HTTP:[0-9]*" | cut -d: -f2)
            if [[ "$HTTP_CODE" == "200" ]]; then
                log "✅ Heartbeat enviado com sucesso (HTTP $HTTP_CODE)"
            else
                log "❌ Falha no heartbeat (HTTP $HTTP_CODE)"
            fi
        fi
        
        # 3. Reiniciar serviço collector
        log "3. Reiniciando serviço collector..."
        systemctl restart samureye-collector
        sleep 3
        
        if systemctl is-active samureye-collector >/dev/null 2>&1; then
            log "✅ Collector reiniciado com sucesso"
        else
            log "❌ Falha ao reiniciar collector"
        fi
        ;;
        
    *)
        echo "Servidor não reconhecido: $HOSTNAME"
        echo ""
        echo "Para corrigir o problema ENROLLING:"
        echo ""
        echo "1. No vlxsam02 (Application Server):"
        echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/fix-collector-enrolling.sh | sudo bash"
        echo ""
        echo "2. No vlxsam04 (Collector):"
        echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/fix-collector-enrolling.sh | sudo bash"
        echo ""
        echo "3. Aguardar alguns minutos e verificar interface web"
        exit 1
        ;;
esac

echo ""
log "✅ Correção concluída"
echo ""
echo "🔍 Para verificar resultado:"
case $HOSTNAME in
    "vlxsam02")
        echo "  sudo -u postgres psql -d samureye -c \"SELECT name, status, last_seen FROM collectors;\""
        echo "  curl -s http://localhost:5000/api/system/settings | head -5"
        ;;
    "vlxsam04")
        echo "  journalctl -u samureye-collector -f"
        echo "  systemctl status samureye-collector"
        ;;
esac
echo ""
echo "🌐 Verificar interface web:"
echo "  1. Acesse: https://app.samureye.com.br/admin"
echo "  2. Login: admin@samureye.com.br / SamurEye2024!"
echo "  3. Navegue para: Gestão de Coletores"
echo "  4. Verifique se vlxsam04 aparece como 'ONLINE'"