#!/bin/bash

# Script de correção para problema de permissão de log e token não salvo
# vlxsam04 - SamurEye Collector

echo "🔧 CORREÇÃO: Permissões Log + Token Não Salvo"
echo "=============================================="

HOSTNAME=$(hostname)
CONFIG_FILE="/etc/samureye-collector/.env"
LOG_DIR="/var/log/samureye-collector"
LOG_FILE="$LOG_DIR/heartbeat.log"
SERVICE_NAME="samureye-collector"
COLLECTOR_USER="samureye-collector"
SCRIPTS_DIR="/opt/samureye/collector/scripts"

# Função de log
log() { echo "[$(date +'%H:%M:%S')] $1"; }
warn() { echo "[$(date +'%H:%M:%S')] WARNING: $1"; }
error() { echo "[$(date +'%H:%M:%S')] ERROR: $1"; exit 1; }

log "🔧 Iniciando correção para vlxsam04..."

echo ""
echo "🔍 1. CORRIGINDO PERMISSÕES DO DIRETÓRIO DE LOGS:"
echo "================================================="

log "📁 Verificando diretório: $LOG_DIR"

# Criar diretório se não existir
if [ ! -d "$LOG_DIR" ]; then
    log "📁 Criando diretório de logs..."
    mkdir -p "$LOG_DIR"
fi

# Corrigir permissões do diretório
log "🔒 Aplicando permissões corretas..."
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$LOG_DIR"
chmod 755 "$LOG_DIR"

# Criar arquivo de log se não existir
if [ ! -f "$LOG_FILE" ]; then
    log "📄 Criando arquivo de log..."
    touch "$LOG_FILE"
fi

# Corrigir permissões do arquivo
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Testar escrita
log "🧪 Testando permissões de escrita..."
if sudo -u "$COLLECTOR_USER" touch "$LOG_DIR/test_write" 2>/dev/null; then
    log "✅ Usuário $COLLECTOR_USER pode escrever no diretório"
    rm -f "$LOG_DIR/test_write"
else
    warn "❌ Ainda não é possível escrever - aplicando correção adicional"
    # Fallback mais permissivo
    chmod 777 "$LOG_DIR"
    chmod 666 "$LOG_FILE"
    
    if sudo -u "$COLLECTOR_USER" touch "$LOG_DIR/test_write" 2>/dev/null; then
        log "✅ Correção adicional aplicada com sucesso"
        rm -f "$LOG_DIR/test_write"
    else
        error "❌ Falha crítica - não é possível corrigir permissões de log"
    fi
fi

echo ""
echo "🔍 2. VERIFICANDO E CORRIGINDO SALVAMENTO DE TOKEN:"
echo "=================================================="

# Verificar se arquivo de configuração existe
if [ ! -f "$CONFIG_FILE" ]; then
    warn "⚠️ Arquivo de configuração não encontrado - criando..."
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << CONFIG_EOF
# Configuração do Collector SamurEye
COLLECTOR_ID=$HOSTNAME
COLLECTOR_NAME=
HOSTNAME=$HOSTNAME
IP_ADDRESS=
API_BASE_URL=https://api.samureye.com.br
HEARTBEAT_INTERVAL=30
RETRY_ATTEMPTS=3
RETRY_DELAY=5
LOG_LEVEL=INFO

# Tokens de autenticação
COLLECTOR_TOKEN=
ENROLLMENT_TOKEN=

# Status do collector
STATUS=offline
CONFIG_EOF
    
    # Aplicar permissões corretas
    chown root:"$COLLECTOR_USER" "$CONFIG_FILE"
    chmod 640 "$CONFIG_FILE"
fi

# Verificar se o register-collector.sh está funcionando corretamente
REGISTER_SCRIPT="$SCRIPTS_DIR/register-collector.sh"
if [ -f "$REGISTER_SCRIPT" ]; then
    log "🔍 Verificando script de registro..."
    
    # Verificar se tem função de salvamento
    if ! grep -q "save_token_to_file\|COLLECTOR_TOKEN=" "$REGISTER_SCRIPT"; then
        warn "⚠️ Script de registro não salva tokens - corrigindo..."
        
        # Backup do script atual
        cp "$REGISTER_SCRIPT" "$REGISTER_SCRIPT.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Baixar versão corrigida
        log "📥 Baixando versão corrigida do register-collector.sh..."
        curl -fsSL "https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh" > "$REGISTER_SCRIPT"
        chmod +x "$REGISTER_SCRIPT"
        log "✅ Script de registro atualizado"
    else
        log "✅ Script de registro parece correto"
    fi
else
    warn "⚠️ Script de registro não encontrado - baixando..."
    mkdir -p "$SCRIPTS_DIR"
    curl -fsSL "https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh" > "$REGISTER_SCRIPT"
    chmod +x "$REGISTER_SCRIPT"
    log "✅ Script de registro instalado"
fi

echo ""
echo "🔍 3. CORRIGINDO SCRIPT HEARTBEAT (SE NECESSÁRIO):"
echo "=================================================="

HEARTBEAT_SCRIPT="/opt/samureye/collector/heartbeat.py"
if [ -f "$HEARTBEAT_SCRIPT" ]; then
    log "🐍 Verificando script heartbeat.py..."
    
    # Verificar se o heartbeat tenta escrever no log correto
    if grep -q "/var/log/samureye-collector/heartbeat.log" "$HEARTBEAT_SCRIPT"; then
        log "✅ Heartbeat configurado para log correto"
    else
        warn "⚠️ Heartbeat pode ter configuração de log incorreta"
    fi
    
    # Garantir que o heartbeat.py é executável
    chown "$COLLECTOR_USER:$COLLECTOR_USER" "$HEARTBEAT_SCRIPT"
    chmod +x "$HEARTBEAT_SCRIPT"
else
    warn "⚠️ Script heartbeat.py não encontrado"
fi

echo ""
echo "🔍 4. REINICIANDO SERVIÇO PARA APLICAR CORREÇÕES:"
echo "================================================="

log "🔄 Recarregando configuração systemd..."
systemctl daemon-reload

log "🛑 Parando serviço atual..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# Aguardar um momento para garantir parada completa
sleep 2

log "🚀 Iniciando serviço..."
systemctl start "$SERVICE_NAME"

# Aguardar inicialização
sleep 3

log "🔍 Verificando status do serviço..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Serviço está rodando"
else
    warn "⚠️ Serviço pode ainda ter problemas - verificando logs..."
    journalctl -u "$SERVICE_NAME" --no-pager -n 5
fi

echo ""
echo "🔍 5. VALIDANDO CORREÇÕES:"
echo "========================="

# Validar permissões de log
log "🧪 Testando escrita no log novamente..."
if sudo -u "$COLLECTOR_USER" touch "$LOG_DIR/test_final" 2>/dev/null; then
    log "✅ Permissões de log: CORRIGIDAS"
    rm -f "$LOG_DIR/test_final"
else
    warn "❌ Permissões de log: AINDA COM PROBLEMA"
fi

# Validar arquivo de configuração
log "🧪 Testando leitura do arquivo de configuração..."
if sudo -u "$COLLECTOR_USER" cat "$CONFIG_FILE" >/dev/null 2>&1; then
    log "✅ Leitura arquivo config: OK"
else
    warn "❌ Leitura arquivo config: PROBLEMA"
fi

# Verificar se o arquivo de log está sendo criado
log "🧪 Verificando se logs estão sendo gerados..."
sleep 5

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    log "✅ Logs sendo gerados: OK"
    echo "   Últimas linhas:"
    tail -3 "$LOG_FILE" | sed 's/^/   /'
else
    warn "⚠️ Logs ainda não sendo gerados - pode precisar de mais tempo"
fi

echo ""
echo "🎯 CORREÇÃO FINALIZADA!"
echo "======================="

echo ""
echo "✅ CORREÇÕES APLICADAS:"
echo "   🔒 Permissões de log corrigidas"
echo "   📄 Arquivo de configuração verificado"
echo "   🔧 Script de registro atualizado"
echo "   🐍 Script heartbeat verificado"
echo "   🤖 Serviço reiniciado"

echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "   1. Aguardar 1-2 minutos para estabilização"
echo "   2. Verificar status: systemctl status $SERVICE_NAME"
echo "   3. Monitorar logs: tail -f $LOG_FILE"
echo "   4. Se ainda houver problemas com token, execute novo registro"

echo ""
echo "🔧 COMANDOS ÚTEIS:"
echo "   • Status: systemctl status $SERVICE_NAME"
echo "   • Logs: tail -f $LOG_FILE"
echo "   • Diagnostico: /opt/samureye/collector/scripts/check-status.sh"

echo ""
log "✅ Correção concluída para vlxsam04"