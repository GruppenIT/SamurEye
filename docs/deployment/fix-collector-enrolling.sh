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
        
        # 1. Verificar API de collectors
        log "1. Verificando API de collectors..."
        
        API_RESULT=$(curl -s -w "HTTP:%{http_code}" -X GET "http://localhost:5000/api/admin/collectors" 2>/dev/null || echo "HTTP:000")
        HTTP_CODE=$(echo "$API_RESULT" | grep -o "HTTP:[0-9]*" | cut -d: -f2)
        
        if [[ "$HTTP_CODE" == "200" ]]; then
            log "✅ API funcionando"
            
            # Verificar quantos collectors existem
            COLLECTORS_JSON=$(echo "$API_RESULT" | sed 's/HTTP:[0-9]*$//')
            ONLINE_COUNT=$(echo "$COLLECTORS_JSON" | grep -o '"status":"online"' | wc -l 2>/dev/null || echo "0")
            ENROLLING_COUNT=$(echo "$COLLECTORS_JSON" | grep -o '"status":"enrolling"' | wc -l 2>/dev/null || echo "0")
            
            log "📊 Status atual: $ONLINE_COUNT online, $ENROLLING_COUNT enrolling"
        else
            log "❌ API não está respondendo (HTTP $HTTP_CODE)"
        fi
        
        # 2. PostgreSQL está no vlxsam03 - não podemos corrigir SQL daqui
        log "2. PostgreSQL está no vlxsam03 - aplicação deve processar heartbeats automaticamente"
        
        # 3. Reiniciar aplicação para processar novos heartbeats
        log "3. Reiniciando aplicação SamurEye..."
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
        
    "vlxsam03")
        log "Executando correção no Database Server (vlxsam03)..."
        
        # Verificar se PostgreSQL está rodando
        if ! systemctl is-active postgresql >/dev/null 2>&1; then
            log "Iniciando PostgreSQL..."
            systemctl start postgresql
            sleep 3
        fi

        if systemctl is-active postgresql >/dev/null 2>&1; then
            log "✅ PostgreSQL ativo"
            
            # Corrigir status no banco de dados
            log "1. Atualizando status de collectors ENROLLING para ONLINE..."
            
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

            # Verificar resultado final
            ONLINE_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE status = 'online';" 2>/dev/null | tr -d ' ')
            ENROLLING_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE status = 'enrolling';" 2>/dev/null | tr -d ' ')
            
            log "📊 Status atual: $ONLINE_COUNT online, $ENROLLING_COUNT enrolling"
        else
            log "❌ Falha ao iniciar PostgreSQL"
        fi
        ;;
        
    *)
        echo "Servidor não reconhecido: $HOSTNAME"
        echo ""
        echo "Para corrigir o problema ENROLLING, execute em cada servidor:"
        echo ""
        echo "1. vlxsam02 (Application Server):"
        echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/fix-collector-enrolling.sh | sudo bash"
        echo ""
        echo "2. vlxsam03 (Database Server):"
        echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/fix-collector-enrolling.sh | sudo bash"
        echo ""
        echo "3. vlxsam04 (Collector):"
        echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/fix-collector-enrolling.sh | sudo bash"
        echo ""
        echo "4. Aguardar alguns minutos e verificar interface web"
        exit 1
        ;;
esac

echo ""
log "✅ Correção concluída"
echo ""
echo "🔍 Para verificar resultado:"
case $HOSTNAME in
    "vlxsam02")
        echo "  curl -s http://localhost:5000/api/admin/collectors | head -5"
        echo "  curl -s http://localhost:5000/api/system/settings | head -5"
        echo "  🗃️ PostgreSQL está no vlxsam03, não no vlxsam02"
        ;;
    "vlxsam04")
        echo "  journalctl -u samureye-collector -f"
        echo "  systemctl status samureye-collector"
        ;;
    "vlxsam03")
        echo "  sudo -u postgres psql -d samureye -c \"SELECT name, status, last_seen FROM collectors;\""
        echo "  systemctl status postgresql"
        ;;
esac
echo ""
echo "🌐 Verificar interface web:"
echo "  1. Acesse: https://app.samureye.com.br/admin"
echo "  2. Login: admin@samureye.com.br / SamurEye2024!"
echo "  3. No Dashboard Admin, procure seção de Collectors"
echo "  4. Verifique se vlxsam04 aparece como 'ONLINE'"
echo ""
echo "⚠️  IMPORTANTE: Se ainda aparecer ENROLLING, execute:"
echo "   1. No vlxsam03: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam03/fix-collector-enrolling.sh | sudo bash"
echo "   2. Aguarde 2-3 minutos para o próximo heartbeat"