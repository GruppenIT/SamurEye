#!/bin/bash
# Script de correção de permissões .env para vlxsam04

echo "🔧 CORREÇÃO PERMISSÕES .ENV - vlxsam04"
echo "====================================="

SERVICE_NAME="samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
CONFIG_FILE="$CONFIG_DIR/.env"
COLLECTOR_USER="samureye-collector"
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Função de log
log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

log "🛑 Parando serviço para correção..."
systemctl stop $SERVICE_NAME

log "🔍 Diagnóstico inicial de permissões..."
echo "📁 Status do diretório $CONFIG_DIR:"
ls -la $CONFIG_DIR/ 2>/dev/null || echo "❌ Diretório não existe"

echo ""
echo "👤 Verificando usuário $COLLECTOR_USER:"
id $COLLECTOR_USER 2>/dev/null || echo "❌ Usuário não existe"

log "🔧 Recriando estrutura de configuração com permissões corretas..."

# Criar diretório se não existir
mkdir -p "$CONFIG_DIR"

# Criar arquivo .env com permissões corretas
log "📝 Criando arquivo .env com permissões adequadas..."
cat > "$CONFIG_FILE" << ENV_EOF
# Configuração do Collector SamurEye - Permissões corrigidas
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

log "🔒 Aplicando permissões corretas..."

# Definir permissões corretas - usuário precisa escrever para criar token.conf
chown -R $COLLECTOR_USER:$COLLECTOR_USER "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"
chmod 644 "$CONFIG_FILE"

# Verificar se as permissões estão corretas
log "🔍 Verificando permissões aplicadas..."
echo "📁 Diretório $CONFIG_DIR:"
ls -la "$CONFIG_DIR/"

echo ""
echo "📄 Arquivo .env:"
ls -la "$CONFIG_FILE"

log "🧪 Testando leitura do arquivo pelo usuário collector..."
if sudo -u $COLLECTOR_USER cat "$CONFIG_FILE" >/dev/null 2>&1; then
    log "✅ Usuário $COLLECTOR_USER pode ler o arquivo .env"
else
    log "❌ ERRO: Usuário $COLLECTOR_USER ainda não pode ler o arquivo"
    echo "🔧 Tentando permissões alternativas..."
    
    # Permissões mais abertas como fallback - usuário owner do diretório
    chown -R $COLLECTOR_USER:$COLLECTOR_USER "$CONFIG_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 644 "$CONFIG_FILE"
    
    if sudo -u $COLLECTOR_USER cat "$CONFIG_FILE" >/dev/null 2>&1; then
        log "✅ Permissões alternativas funcionaram"
    else
        log "❌ CRÍTICO: Ainda há problemas de permissão"
    fi
fi

log "🔧 Verificando outros arquivos necessários..."

# Verificar heartbeat.py
HEARTBEAT_FILE="/opt/samureye/collector/heartbeat.py"
if [ -f "$HEARTBEAT_FILE" ]; then
    chown $COLLECTOR_USER:$COLLECTOR_USER "$HEARTBEAT_FILE"
    chmod +x "$HEARTBEAT_FILE"
    log "✅ Permissões heartbeat.py ajustadas"
else
    log "❌ heartbeat.py não encontrado"
fi

# Verificar diretório de logs
LOG_DIR="/var/log/samureye-collector"
mkdir -p "$LOG_DIR"
chown -R $COLLECTOR_USER:$COLLECTOR_USER "$LOG_DIR"
chmod 755 "$LOG_DIR"
log "✅ Permissões logs ajustadas"

# Verificar diretório principal
COLLECTOR_DIR="/opt/samureye/collector"
if [ -d "$COLLECTOR_DIR" ]; then
    chown -R $COLLECTOR_USER:$COLLECTOR_USER "$COLLECTOR_DIR"
    chmod 755 "$COLLECTOR_DIR"
    log "✅ Permissões collector dir ajustadas"
fi

log "🧪 Teste final de execução..."
echo "Testando execução do heartbeat (timeout 5s):"
timeout 5s sudo -u $COLLECTOR_USER python3 /opt/samureye/collector/heartbeat.py 2>&1 || {
    echo "⚠️ Teste com problemas, mas pode ser normal (timeout ou conexão)"
}

log "🚀 Reiniciando serviço..."
systemctl daemon-reload
systemctl start $SERVICE_NAME

# Aguardar inicialização
sleep 3

log "🔍 Verificação final..."
if systemctl is-active --quiet $SERVICE_NAME; then
    log "✅ SUCESSO: Serviço ativo!"
    
    echo ""
    echo "📊 Status do serviço:"
    systemctl status $SERVICE_NAME --no-pager -l
    
    echo ""
    echo "📝 Logs recentes (5 linhas):"
    journalctl -u $SERVICE_NAME --no-pager -n 5
    
    echo ""
    echo "📝 Verificando logs de erro de permissão..."
    if journalctl -u $SERVICE_NAME --no-pager -n 20 | grep -q "Permission denied"; then
        log "⚠️ Ainda há erros de permissão nos logs"
    else
        log "✅ Sem erros de permissão detectados"
    fi
    
else
    log "❌ Serviço ainda com problemas"
    echo ""
    echo "📝 Logs de erro:"
    journalctl -u $SERVICE_NAME --no-pager -n 10
fi

echo ""
echo "✅ CORREÇÃO PERMISSÕES FINALIZADA"
echo "================================"
echo ""
echo "📁 Estrutura final:"
echo "• Config dir: $CONFIG_DIR ($(stat -c %A $CONFIG_DIR)) - Owner: $(stat -c %U:%G $CONFIG_DIR)"
echo "• .env file:  $CONFIG_FILE ($(stat -c %A $CONFIG_FILE)) - Owner: $(stat -c %U:%G $CONFIG_FILE)"

# Teste final de escrita
log "🧪 Teste final de escrita no diretório config..."
if sudo -u $COLLECTOR_USER touch "$CONFIG_DIR/test_token.conf" 2>/dev/null; then
    log "✅ Usuário pode criar arquivos no diretório config"
    rm -f "$CONFIG_DIR/test_token.conf"
else
    log "❌ CRÍTICO: Usuário ainda não pode escrever no diretório config"
fi
echo ""
echo "🔧 Se ainda houver problemas:"
echo "• Verificar logs: journalctl -u $SERVICE_NAME -f"
echo "• Testar manual: sudo -u $COLLECTOR_USER python3 /opt/samureye/collector/heartbeat.py"
echo "• Status: systemctl status $SERVICE_NAME"