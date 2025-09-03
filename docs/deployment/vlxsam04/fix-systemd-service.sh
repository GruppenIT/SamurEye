#!/bin/bash
# Script de correção específica para erro systemd vlxsam04

echo "🔧 CORREÇÃO SYSTEMD SERVICE - vlxsam04"
echo "======================================"

SERVICE_NAME="samureye-collector"
COLLECTOR_DIR="/opt/samureye/collector"
COLLECTOR_USER="samureye-collector"

# Função de log
log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

log "🛑 Parando serviço com problemas..."
systemctl stop $SERVICE_NAME 2>/dev/null || true
systemctl disable $SERVICE_NAME 2>/dev/null || true

log "🔧 Recriando arquivo systemd com paths absolutos..."

# Criar arquivo systemd correto com paths absolutos
cat > /etc/systemd/system/$SERVICE_NAME.service << 'SYSTEMD_EOF'
[Unit]
Description=SamurEye Collector Agent
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=10
User=samureye-collector
Group=samureye-collector
WorkingDirectory=/opt/samureye/collector
ExecStart=/usr/bin/python3 /opt/samureye/collector/heartbeat.py
StandardOutput=append:/var/log/samureye-collector/collector.log
StandardError=append:/var/log/samureye-collector/collector.log
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

log "✅ Arquivo systemd recriado com paths absolutos"

log "🔧 Verificando integridade do arquivo systemd..."
if systemd-analyze verify /etc/systemd/system/$SERVICE_NAME.service; then
    log "✅ Arquivo systemd válido"
else
    log "❌ ERRO: Arquivo systemd ainda inválido"
    cat /etc/systemd/system/$SERVICE_NAME.service
    exit 1
fi

log "🔄 Recarregando systemd daemon..."
systemctl daemon-reload

log "🔧 Verificando se heartbeat.py existe e é executável..."
if [ ! -f "$COLLECTOR_DIR/heartbeat.py" ]; then
    log "❌ CRÍTICO: heartbeat.py não existe!"
    log "   Execute o install-hard-reset.sh completo primeiro"
    exit 1
fi

# Garantir permissões corretas
chmod +x "$COLLECTOR_DIR/heartbeat.py"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/heartbeat.py"

log "🔧 Verificando usuário e diretórios..."
if ! id "$COLLECTOR_USER" >/dev/null 2>&1; then
    log "❌ CRÍTICO: Usuário $COLLECTOR_USER não existe!"
    exit 1
fi

if [ ! -d "$COLLECTOR_DIR" ]; then
    log "❌ CRÍTICO: Diretório $COLLECTOR_DIR não existe!"
    exit 1
fi

log "🔧 Testando execução manual do heartbeat..."
echo "Teste execução (timeout 5s):"
timeout 5s sudo -u "$COLLECTOR_USER" python3 "$COLLECTOR_DIR/heartbeat.py" 2>&1 || {
    echo "⚠️ Teste execução teve problemas, mas continuando..."
}

log "🚀 Habilitando e iniciando serviço..."
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Aguardar inicialização
sleep 3

log "🔍 Verificação final..."
if systemctl is-active --quiet $SERVICE_NAME; then
    log "✅ SUCESSO: Serviço ativo!"
    echo ""
    echo "📊 Status:"
    systemctl status $SERVICE_NAME --no-pager -l
    
    echo ""
    echo "📝 Logs recentes:"
    journalctl -u $SERVICE_NAME --no-pager -n 5
    
else
    log "❌ Serviço ainda com problemas"
    echo ""
    echo "📊 Status detalhado:"
    systemctl status $SERVICE_NAME --no-pager -l
    
    echo ""
    echo "📝 Logs de erro:"
    journalctl -u $SERVICE_NAME --no-pager -n 10
fi

echo ""
echo "✅ CORREÇÃO SYSTEMD FINALIZADA"
echo "=============================="
echo ""
echo "🔧 Comandos úteis:"
echo "• systemctl status $SERVICE_NAME"
echo "• journalctl -u $SERVICE_NAME -f"
echo "• tail -f /var/log/samureye-collector/heartbeat.log"
echo ""
echo "🔍 Se ainda houver problemas:"
echo "• Verificar se nmap está instalado: apt install nmap -y"
echo "• Testar manualmente: sudo -u $COLLECTOR_USER python3 $COLLECTOR_DIR/heartbeat.py"
echo "• Execute diagnóstico completo com o script diagnose-service-failed.sh"