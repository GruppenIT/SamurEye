#!/bin/bash

# ============================================================================
# SCRIPT DE DEBUG - COLLECTOR ENROLLMENT STATUS
# Diagnóstico completo para resolver status ENROLLING
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
}

# ============================================================================
# 1. INFORMAÇÕES BÁSICAS
# ============================================================================

log "🔍 DIAGNÓSTICO COLLECTOR ENROLLMENT"
echo "======================================"

# Coletar informações básicas
COLLECTOR_NAME=$(hostname)
COLLECTOR_DIR="/opt/samureye-collector"
CERTS_DIR="$COLLECTOR_DIR/certs"
CONFIG_FILE="/etc/samureye-collector/.env"
LOG_FILE="/var/log/samureye-collector/collector.log"

echo "Collector: $COLLECTOR_NAME"
echo "Data: $(date)"
echo ""

# ============================================================================
# 2. VERIFICAR ARQUIVOS E DIRETÓRIOS
# ============================================================================

log "📁 Verificando estrutura de arquivos..."

echo "• Diretório collector: $([ -d "$COLLECTOR_DIR" ] && echo "✅ Existe" || echo "❌ Não encontrado")"
echo "• Diretório certificados: $([ -d "$CERTS_DIR" ] && echo "✅ Existe" || echo "❌ Não encontrado")"
echo "• Arquivo config: $([ -f "$CONFIG_FILE" ] && echo "✅ Existe" || echo "❌ Não encontrado")"
echo "• Arquivo log: $([ -f "$LOG_FILE" ] && echo "✅ Existe" || echo "❌ Não encontrado")"

# ============================================================================
# 3. VERIFICAR CERTIFICADOS
# ============================================================================

log "🔐 Verificando certificados..."

if [ -d "$CERTS_DIR" ]; then
    echo "Certificados encontrados:"
    ls -la "$CERTS_DIR"
    echo ""
    
    # Verificar certificados específicos
    CERT_FILES=("ca.crt" "collector.crt" "collector.key")
    for cert in "${CERT_FILES[@]}"; do
        cert_path="$CERTS_DIR/$cert"
        if [ -f "$cert_path" ]; then
            echo "• $cert: ✅ Existe ($(stat -c%s "$cert_path") bytes)"
            if [[ "$cert" == *.crt ]]; then
                echo "  Válido até: $(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Erro ao ler")"
            fi
        else
            echo "• $cert: ❌ Não encontrado"
        fi
    done
else
    warn "Diretório de certificados não encontrado"
fi

echo ""

# ============================================================================
# 4. VERIFICAR CONFIGURAÇÃO
# ============================================================================

log "⚙️ Verificando configuração..."

if [ -f "$CONFIG_FILE" ]; then
    echo "Configuração atual:"
    echo "==================="
    # Mostrar config sem senhas
    cat "$CONFIG_FILE" | sed 's/PASSWORD=.*/PASSWORD=***/' | sed 's/TOKEN=.*/TOKEN=***/'
    echo ""
else
    warn "Arquivo de configuração não encontrado"
fi

# ============================================================================
# 5. VERIFICAR SERVIÇO SYSTEMD
# ============================================================================

log "🔄 Verificando serviço systemd..."

SERVICE_NAME="samureye-collector.service"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "• Status: ✅ Ativo"
else
    echo "• Status: ❌ Inativo"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    echo "• Habilitado: ✅ Sim"
else
    echo "• Habilitado: ❌ Não"
fi

echo ""
echo "Status detalhado:"
systemctl status "$SERVICE_NAME" --no-pager -l || true

echo ""

# ============================================================================
# 6. VERIFICAR LOGS
# ============================================================================

log "📋 Verificando logs do collector..."

if [ -f "$LOG_FILE" ]; then
    echo "Últimas 20 linhas do log:"
    echo "========================"
    tail -20 "$LOG_FILE"
    echo ""
    
    # Procurar por erros específicos
    echo "Erros encontrados:"
    echo "=================="
    grep -i "error\|fail\|timeout\|refused" "$LOG_FILE" | tail -10 || echo "Nenhum erro recente encontrado"
else
    warn "Arquivo de log não encontrado"
fi

echo ""

# ============================================================================
# 7. TESTES DE CONECTIVIDADE
# ============================================================================

log "🌐 Testando conectividade..."

# URLs para teste
API_BASE="https://api.samureye.com.br"
ENDPOINTS=("/api/system/settings" "/api/collectors/heartbeat")

# Teste básico de DNS
echo "• DNS api.samureye.com.br: $(nslookup api.samureye.com.br >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Falha")"

# Teste de porta
echo "• Porta 443 acessível: $(timeout 5 bash -c "</dev/tcp/api.samureye.com.br/443" >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Bloqueada")"

# Testes com certificados (se existirem)
if [ -f "$CERTS_DIR/collector.crt" ] && [ -f "$CERTS_DIR/collector.key" ]; then
    echo ""
    echo "Testes com certificado do collector:"
    
    for endpoint in "${ENDPOINTS[@]}"; do
        url="$API_BASE$endpoint"
        echo -n "• $endpoint: "
        
        response=$(curl -k \
            --cert "$CERTS_DIR/collector.crt" \
            --key "$CERTS_DIR/collector.key" \
            --connect-timeout 10 \
            --max-time 30 \
            -w "HTTP_%{http_code}" \
            "$url" 2>/dev/null || echo "TIMEOUT_OR_ERROR")
        
        if [[ "$response" == *"HTTP_200"* ]]; then
            echo "✅ OK"
        elif [[ "$response" == *"HTTP_"* ]]; then
            echo "⚠️ HTTP $(echo "$response" | grep -o "HTTP_[0-9]*" | cut -d_ -f2)"
        else
            echo "❌ Falha de conexão"
        fi
    done
else
    warn "Certificados não encontrados - pulando testes autenticados"
fi

echo ""

# ============================================================================
# 8. VERIFICAR PROCESSOS
# ============================================================================

log "🔧 Verificando processos..."

# Verificar se há processos do collector rodando
COLLECTOR_PROCESSES=$(ps aux | grep -i samureye-collector | grep -v grep || true)

if [ -n "$COLLECTOR_PROCESSES" ]; then
    echo "Processos do collector:"
    echo "$COLLECTOR_PROCESSES"
else
    echo "❌ Nenhum processo do collector encontrado"
fi

echo ""

# ============================================================================
# 9. VERIFICAR RECURSOS DO SISTEMA
# ============================================================================

log "💻 Verificando recursos do sistema..."

echo "• CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d% -f1)% uso"
echo "• RAM: $(free -h | awk 'NR==2{printf "%.1f%% usado", $3*100/$2 }')"
echo "• Disco: $(df -h / | awk 'NR==2{print $5 " usado"}')"
echo "• Load: $(uptime | awk -F'load average:' '{ print $2 }')"

echo ""

# ============================================================================
# 10. SUGESTÕES DE CORREÇÃO
# ============================================================================

log "💡 Sugestões de correção..."

echo "Comandos úteis para debug:"
echo "=========================="
echo "• Reiniciar collector: systemctl restart $SERVICE_NAME"
echo "• Ver logs em tempo real: tail -f $LOG_FILE"
echo "• Reregistrar collector: cd $COLLECTOR_DIR && ./register-collector.sh [tenant] [name]"
echo "• Verificar config: cat $CONFIG_FILE"
echo "• Teste manual API: curl -k --cert $CERTS_DIR/collector.crt --key $CERTS_DIR/collector.key $API_BASE/api/system/settings"

echo ""
log "✅ Diagnóstico concluído!"