#!/bin/bash

# ============================================================================
# SCRIPT DE CORREÇÃO - COLLECTOR HEARTBEAT
# Corrige problemas de heartbeat do collector vlxsam04
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função de log
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# ============================================================================
# EXECUTAR APENAS NO vlxsam04
# ============================================================================

HOSTNAME=$(hostname)
if [ "$HOSTNAME" != "vlxsam04" ]; then
    error "Este script deve ser executado apenas no vlxsam04, não no $HOSTNAME"
fi

log "🔧 CORREÇÃO HEARTBEAT COLLECTOR vlxsam04"
echo "======================================="

# ============================================================================
# 1. VERIFICAR CONFIGURAÇÃO ATUAL
# ============================================================================

log "🔍 Verificando configuração atual..."

COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_FILE="/etc/samureye-collector/.env"
LOG_FILE="/var/log/samureye-collector/collector.log"
SERVICE_NAME="samureye-collector.service"

# Verificar se serviço existe
if ! systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    error "Serviço $SERVICE_NAME não encontrado"
fi

# Parar serviço se estiver rodando
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "⏹️ Parando serviço $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME"
fi

# ============================================================================
# 2. VERIFICAR E CORRIGIR CONFIGURAÇÃO
# ============================================================================

log "⚙️ Verificando configuração..."

if [ ! -f "$CONFIG_FILE" ]; then
    error "Arquivo de configuração $CONFIG_FILE não encontrado"
fi

# Mostrar configuração atual (sem senhas)
echo "Configuração atual:"
cat "$CONFIG_FILE" | sed 's/PASSWORD=.*/PASSWORD=***/' | sed 's/TOKEN=.*/TOKEN=***/'
echo ""

# Verificar se API_BASE está correto
if ! grep -q "API_BASE.*https://api.samureye.com.br" "$CONFIG_FILE"; then
    warn "Corrigindo API_BASE..."
    sed -i 's|API_BASE=.*|API_BASE=https://api.samureye.com.br|' "$CONFIG_FILE"
fi

# Verificar HEARTBEAT_INTERVAL (deve ser em segundos, não muito baixo)
if ! grep -q "HEARTBEAT_INTERVAL" "$CONFIG_FILE"; then
    echo "HEARTBEAT_INTERVAL=30" >> "$CONFIG_FILE"
    log "✅ HEARTBEAT_INTERVAL adicionado (30 segundos)"
fi

# ============================================================================
# 3. VERIFICAR CERTIFICADOS
# ============================================================================

log "🔐 Verificando certificados..."

CERTS_DIR="$COLLECTOR_DIR/certs"
REQUIRED_CERTS=("ca.crt" "collector.crt" "collector.key")

for cert in "${REQUIRED_CERTS[@]}"; do
    cert_path="$CERTS_DIR/$cert"
    if [ ! -f "$cert_path" ]; then
        error "Certificado $cert não encontrado: $cert_path"
    else
        echo "✅ $cert existe ($(stat -c%s "$cert_path") bytes)"
    fi
done

# Testar certificado
if openssl x509 -in "$CERTS_DIR/collector.crt" -noout -checkend 86400 >/dev/null 2>&1; then
    log "✅ Certificado collector válido"
else
    warn "⚠️ Certificado collector pode estar expirado"
fi

# ============================================================================
# 4. TESTAR CONECTIVIDADE
# ============================================================================

log "🌐 Testando conectividade..."

API_BASE="https://api.samureye.com.br"

# Teste DNS
if nslookup api.samureye.com.br >/dev/null 2>&1; then
    echo "✅ DNS api.samureye.com.br"
else
    error "❌ DNS api.samureye.com.br falhou"
fi

# Teste porta
if timeout 5 bash -c "</dev/tcp/api.samureye.com.br/443" >/dev/null 2>&1; then
    echo "✅ Porta 443 acessível"
else
    error "❌ Porta 443 bloqueada"
fi

# Teste API com certificados
echo "🔧 Testando API com certificados..."

HEARTBEAT_TEST=$(curl -k \
    --cert "$CERTS_DIR/collector.crt" \
    --key "$CERTS_DIR/collector.key" \
    --connect-timeout 10 \
    --max-time 30 \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "collector_id": "vlxsam04",
        "status": "online",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "telemetry": {
            "cpu_percent": 15.2,
            "memory_percent": 45.8,
            "disk_percent": 32.1,
            "processes": 98
        },
        "capabilities": ["nmap", "nuclei", "masscan"],
        "version": "1.0.0"
    }' \
    "$API_BASE/collector-api/heartbeat" 2>/dev/null || echo "ERROR")

if [[ "$HEARTBEAT_TEST" == *"Heartbeat received"* ]]; then
    log "✅ Teste de heartbeat manual: SUCESSO"
    echo "Resposta: $HEARTBEAT_TEST"
else
    error "❌ Teste de heartbeat manual falhou: $HEARTBEAT_TEST"
fi

# ============================================================================
# 5. REINICIAR E MONITORAR SERVIÇO
# ============================================================================

log "🔄 Reiniciando serviço..."

# Recarregar configuração systemd
systemctl daemon-reload

# Iniciar serviço
systemctl start "$SERVICE_NAME"
sleep 5

# Verificar se está ativo
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Serviço $SERVICE_NAME iniciado"
else
    error "❌ Falha ao iniciar serviço $SERVICE_NAME"
fi

# ============================================================================
# 6. MONITORAR LOGS
# ============================================================================

log "📋 Monitorando logs por 30 segundos..."

if [ -f "$LOG_FILE" ]; then
    echo "Últimas linhas do log:"
    echo "====================="
    timeout 30 tail -f "$LOG_FILE" &
    TAIL_PID=$!
    sleep 30
    kill $TAIL_PID 2>/dev/null || true
    echo ""
else
    warn "Arquivo de log não encontrado: $LOG_FILE"
fi

# ============================================================================
# 7. STATUS FINAL
# ============================================================================

log "📊 Status final..."

echo "• Serviço ativo: $(systemctl is-active "$SERVICE_NAME")"
echo "• Serviço habilitado: $(systemctl is-enabled "$SERVICE_NAME")"

if [ -f "$LOG_FILE" ]; then
    echo "• Últimas 3 linhas do log:"
    tail -3 "$LOG_FILE" | sed 's/^/  /'
fi

echo ""
log "✅ Correção concluída!"
echo ""
echo "🔧 Comandos úteis:"
echo "• Ver status: systemctl status $SERVICE_NAME"
echo "• Ver logs: tail -f $LOG_FILE"
echo "• Reiniciar: systemctl restart $SERVICE_NAME"
echo "• Testar heartbeat: curl -X POST $API_BASE/collector-api/heartbeat -d '{...}'"