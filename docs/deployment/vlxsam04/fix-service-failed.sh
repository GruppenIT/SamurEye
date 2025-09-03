#!/bin/bash
# Script de correção para vlxsam04 Service Failed - integrado no install-hard-reset.sh

echo "🔧 CORREÇÃO AUTOMÁTICA - vlxsam04 Service Failed"
echo "==============================================="

HOSTNAME=$(hostname)
SERVICE_NAME="samureye-collector"
COLLECTOR_DIR="/opt/samureye/collector"
CONFIG_DIR="/etc/samureye-collector"
LOG_DIR="/var/log/samureye-collector"

# Função de log
log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

warn() {
    echo "[$(date '+%H:%M:%S')] WARNING: $1"
}

echo "📋 Sistema: $HOSTNAME"
echo "📅 Data: $(date)"
echo ""

log "🔍 PASSO 1: Diagnóstico inicial"

# Parar serviço se estiver rodando
if systemctl is-active --quiet $SERVICE_NAME; then
    log "🛑 Parando serviço ativo..."
    systemctl stop $SERVICE_NAME
fi

log "🔧 PASSO 2: Corrigindo ferramentas ausentes"

# Instalar nmap se ausente
if ! command -v nmap >/dev/null 2>&1; then
    log "🔄 Instalando nmap..."
    apt-get update >/dev/null 2>&1
    apt-get install -y nmap >/dev/null 2>&1
    
    if command -v nmap >/dev/null 2>&1; then
        log "✅ nmap instalado"
    else
        warn "❌ Falha instalação nmap"
    fi
else
    log "✅ nmap já disponível"
fi

# Verificar gobuster
if ! command -v gobuster >/dev/null 2>&1; then
    log "🔄 Corrigindo gobuster..."
    
    # Verificar se está instalado mas não no PATH
    if dpkg -l | grep -q gobuster; then
        log "ℹ️ gobuster instalado via apt, verificando PATH..."
        
        # Encontrar binário
        GOBUSTER_PATH=$(find /usr -name "gobuster" -type f 2>/dev/null | head -1)
        if [ -n "$GOBUSTER_PATH" ]; then
            ln -sf "$GOBUSTER_PATH" /usr/local/bin/gobuster
            log "✅ gobuster linkado para PATH"
        fi
    else
        log "🔄 Reinstalando gobuster..."
        apt-get install -y gobuster >/dev/null 2>&1
    fi
    
    if command -v gobuster >/dev/null 2>&1; then
        log "✅ gobuster disponível"
    else
        warn "❌ gobuster ainda não disponível"
    fi
else
    log "✅ gobuster já disponível"
fi

log "🔧 PASSO 3: Recriando configuração"

# Criar configuração .env se ausente
if [ ! -f "$CONFIG_DIR/.env" ]; then
    log "📝 Criando configuração .env..."
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/.env" << 'ENV_EOF'
# Configuração do Collector SamurEye - Auto-gerada
COLLECTOR_ID=%HOSTNAME%
COLLECTOR_NAME=%HOSTNAME%-collector
HOSTNAME=%HOSTNAME%
IP_ADDRESS=%IP_ADDRESS%
API_BASE_URL=https://api.samureye.com.br
HEARTBEAT_INTERVAL=30
RETRY_ATTEMPTS=3
RETRY_DELAY=5
LOG_LEVEL=INFO
ENV_EOF

    # Substituir variáveis
    sed -i "s/%HOSTNAME%/$(hostname)/g" "$CONFIG_DIR/.env"
    sed -i "s/%IP_ADDRESS%/$(hostname -I | awk '{print $1}')/g" "$CONFIG_DIR/.env"
    
    chmod 640 "$CONFIG_DIR/.env"
    chown samureye-collector:samureye-collector "$CONFIG_DIR/.env"
    
    log "✅ Configuração .env criada"
else
    log "✅ Configuração .env já existe"
fi

log "🔧 PASSO 4: Verificando script heartbeat"

# Verificar se heartbeat.py existe e está executável
if [ ! -f "$COLLECTOR_DIR/heartbeat.py" ]; then
    warn "❌ heartbeat.py não encontrado - execute install-hard-reset.sh completo"
    exit 1
fi

# Verificar permissões
chmod +x "$COLLECTOR_DIR/heartbeat.py"
chown samureye-collector:samureye-collector "$COLLECTOR_DIR/heartbeat.py"

log "🔧 PASSO 5: Testando execução Python"

# Teste básico Python
python3 -c "
try:
    import os, sys, json, time, socket, requests, logging, psutil
    from pathlib import Path
    print('✅ Importações Python OK')
except ImportError as e:
    print(f'❌ Erro importação: {e}')
    exit(1)
"

if [ $? -ne 0 ]; then
    warn "❌ Problema dependências Python - reinstalando..."
    apt-get install -y python3-psutil python3-requests >/dev/null 2>&1
fi

log "🔧 PASSO 6: Reiniciando serviço"

# Recarregar systemd e reiniciar
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME

# Aguardar inicialização
sleep 5

log "🔍 PASSO 7: Verificação final"

if systemctl is-active --quiet $SERVICE_NAME; then
    log "✅ Serviço ativo!"
    
    # Mostrar logs recentes
    echo ""
    echo "📝 Logs recentes:"
    journalctl -u $SERVICE_NAME --no-pager -n 10
    
else
    warn "❌ Serviço ainda com problemas"
    echo ""
    echo "📝 Logs de erro:"
    journalctl -u $SERVICE_NAME --no-pager -n 20
    echo ""
    echo "🔧 Comandos para debug manual:"
    echo "• journalctl -u $SERVICE_NAME -f"
    echo "• sudo -u samureye-collector python3 $COLLECTOR_DIR/heartbeat.py"
    echo "• $COLLECTOR_DIR/scripts/check-status.sh"
fi

echo ""
echo "✅ CORREÇÃO FINALIZADA"
echo "====================="
echo ""
echo "🔧 Status ferramentas:"
echo "• nmap:     $(command -v nmap >/dev/null && echo "✅" || echo "❌")"
echo "• nuclei:   $(command -v nuclei >/dev/null && echo "✅" || echo "❌")"  
echo "• masscan:  $(command -v masscan >/dev/null && echo "✅" || echo "❌")"
echo "• gobuster: $(command -v gobuster >/dev/null && echo "✅" || echo "❌")"
echo ""
echo "🤖 Status serviço: $(systemctl is-active $SERVICE_NAME)"
echo ""
echo "📝 Monitoramento:"
echo "• tail -f $LOG_DIR/heartbeat.log"
echo "• systemctl status $SERVICE_NAME"
echo "• https://app.samureye.com.br/admin/collectors"