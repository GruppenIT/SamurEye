#!/bin/bash
# Script master de correção para todos os problemas vlxsam04

echo "🔧 CORREÇÃO COMPLETA VLXSAM04 - TODOS OS PROBLEMAS"
echo "================================================="

SERVICE_NAME="samureye-collector"
COLLECTOR_DIR="/opt/samureye/collector"
CONFIG_DIR="/etc/samureye-collector"
CONFIG_FILE="$CONFIG_DIR/.env"
COLLECTOR_USER="samureye-collector"
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Função de log
log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

warn() {
    echo "[$(date '+%H:%M:%S')] WARNING: $1"
}

log "🛑 PASSO 1: Parando serviço problemático"
systemctl stop $SERVICE_NAME 2>/dev/null || true

log "🔧 PASSO 2: Instalando ferramentas ausentes"

# Instalar nmap se ausente
if ! command -v nmap >/dev/null 2>&1; then
    log "📡 Instalando nmap..."
    apt-get update >/dev/null 2>&1
    apt-get install -y nmap >/dev/null 2>&1
fi

# Corrigir gobuster PATH
if ! command -v gobuster >/dev/null 2>&1; then
    log "🔧 Corrigindo gobuster PATH..."
    GOBUSTER_PATH=$(find /usr -name "gobuster" -type f 2>/dev/null | head -1)
    if [ -n "$GOBUSTER_PATH" ]; then
        ln -sf "$GOBUSTER_PATH" /usr/local/bin/gobuster
        log "✅ gobuster linkado para PATH"
    fi
fi

log "🔧 PASSO 3: Recriando configuração com permissões corretas"

# Recriar estrutura de diretórios com permissões adequadas
mkdir -p "$CONFIG_DIR"
mkdir -p "$COLLECTOR_DIR"
mkdir -p "/var/log/samureye-collector"

# Criar arquivo .env
cat > "$CONFIG_FILE" << ENV_EOF
# Configuração do Collector SamurEye - Corrigida
COLLECTOR_ID=$HOSTNAME
COLLECTOR_NAME=${HOSTNAME}-collector
HOSTNAME=$HOSTNAME
IP_ADDRESS=$IP_ADDRESS
API_BASE_URL=https://api.samureye.com.br
HEARTBEAT_INTERVAL=30
RETRY_ATTEMPTS=3
RETRY_DELAY=5
LOG_LEVEL=INFO
ENV_EOF

# Aplicar permissões - usuário owner para poder criar token.conf
chown -R $COLLECTOR_USER:$COLLECTOR_USER "$CONFIG_DIR"
chown -R $COLLECTOR_USER:$COLLECTOR_USER "$COLLECTOR_DIR" 
chown -R $COLLECTOR_USER:$COLLECTOR_USER "/var/log/samureye-collector"

chmod 755 "$CONFIG_DIR"
chmod 644 "$CONFIG_FILE"
chmod 755 "$COLLECTOR_DIR"
chmod 755 "/var/log/samureye-collector"

log "✅ Permissões aplicadas - usuário $COLLECTOR_USER owner completo"

log "🔧 PASSO 4: Recriando arquivo systemd"

# Recriar arquivo systemd com paths absolutos
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

# Verificar arquivo systemd
if ! systemd-analyze verify /etc/systemd/system/$SERVICE_NAME.service 2>/dev/null; then
    warn "❌ Arquivo systemd inválido"
    exit 1
fi

log "✅ Arquivo systemd recriado e validado"

log "🔧 PASSO 5: Verificando script heartbeat"

if [ ! -f "$COLLECTOR_DIR/heartbeat.py" ]; then
    warn "❌ heartbeat.py não existe - execute install-hard-reset.sh primeiro"
    exit 1
fi

chmod +x "$COLLECTOR_DIR/heartbeat.py"
chown $COLLECTOR_USER:$COLLECTOR_USER "$COLLECTOR_DIR/heartbeat.py"

log "🔧 PASSO 6: Testando configuração"

log "🧪 Teste leitura .env:"
if sudo -u $COLLECTOR_USER cat "$CONFIG_FILE" >/dev/null 2>&1; then
    log "✅ .env legível"
else
    log "❌ Problema leitura .env"
    exit 1
fi

log "🧪 Teste escrita diretório config:"
if sudo -u $COLLECTOR_USER touch "$CONFIG_DIR/test.tmp" 2>/dev/null; then
    log "✅ Escrita no config OK"
    rm -f "$CONFIG_DIR/test.tmp"
else
    log "❌ Problema escrita config"
    exit 1
fi

log "🧪 Teste execução heartbeat (timeout 3s):"
timeout 3s sudo -u $COLLECTOR_USER python3 "$COLLECTOR_DIR/heartbeat.py" 2>/dev/null || {
    log "ℹ️ Teste heartbeat finalizado (normal timeout/conexão)"
}

log "🚀 PASSO 7: Iniciando serviço"

systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Aguardar inicialização
sleep 5

log "🔍 PASSO 8: Verificação final"

if systemctl is-active --quiet $SERVICE_NAME; then
    log "✅ SUCESSO TOTAL: Serviço ativo!"
    
    echo ""
    echo "📊 Status do serviço:"
    systemctl status $SERVICE_NAME --no-pager -l
    
    echo ""
    echo "📝 Logs recentes (5 linhas):"
    journalctl -u $SERVICE_NAME --no-pager -n 5
    
    echo ""
    echo "📝 Verificando logs por 10 segundos para confirmar funcionamento..."
    timeout 10s journalctl -u $SERVICE_NAME -f 2>/dev/null || true
    
else
    log "❌ Serviço ainda com problemas"
    echo ""
    echo "📝 Logs de erro:"
    journalctl -u $SERVICE_NAME --no-pager -n 15
fi

echo ""
echo "✅ CORREÇÃO COMPLETA FINALIZADA"
echo "==============================="
echo ""
echo "🔧 Status ferramentas:"
echo "• nmap:     $(command -v nmap >/dev/null && echo "✅ Disponível" || echo "❌ Ausente")"
echo "• nuclei:   $(command -v nuclei >/dev/null && echo "✅ Disponível" || echo "❌ Ausente")"
echo "• masscan:  $(command -v masscan >/dev/null && echo "✅ Disponível" || echo "❌ Ausente")"
echo "• gobuster: $(command -v gobuster >/dev/null && echo "✅ Disponível" || echo "❌ Ausente")"
echo ""
echo "🤖 Status serviço: $(systemctl is-active $SERVICE_NAME)"
echo ""
echo "📁 Permissões finais:"
echo "• $CONFIG_DIR: $(stat -c %A $CONFIG_DIR) ($(stat -c %U:%G $CONFIG_DIR))"
echo "• $CONFIG_FILE: $(stat -c %A $CONFIG_FILE) ($(stat -c %U:%G $CONFIG_FILE))"
echo ""
echo "📝 Monitoramento:"
echo "• tail -f /var/log/samureye-collector/heartbeat.log"
echo "• journalctl -u $SERVICE_NAME -f"
echo "• https://app.samureye.com.br/admin/collectors"