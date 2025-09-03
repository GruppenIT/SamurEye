#!/bin/bash

# ============================================================================
# SCRIPT DIAGNÓSTICO - COLLECTOR 401 UNAUTHORIZED vlxsam04  
# ============================================================================
# Investiga problema de collector não conseguir voltar ONLINE
# Erro: 401 Unauthorized no auto-registro
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

echo ""
echo "🔍 DIAGNÓSTICO - COLLECTOR 401 UNAUTHORIZED"
echo "==========================================="
echo "Sistema: vlxsam04 ($(hostname))"
echo "Problema: Collector não consegue voltar ONLINE após restart"
echo ""

# ============================================================================
# 1. STATUS BÁSICO DO COLLECTOR
# ============================================================================

log "📊 Verificando status do collector..."

# Verificar se serviço está rodando
if systemctl is-active --quiet samureye-collector 2>/dev/null; then
    log "✅ Serviço samureye-collector está ATIVO"
else
    error "❌ Serviço samureye-collector está INATIVO"
    echo "   • Execute: systemctl start samureye-collector"
fi

# Verificar status do serviço
STATUS_OUTPUT=$(systemctl status samureye-collector --no-pager -l 2>/dev/null || true)
if echo "$STATUS_OUTPUT" | grep -q "activating.*auto-restart"; then
    warn "⚠️ Serviço está em loop de restart automático"
    echo "   • Indica falha repetida no processo principal"
elif echo "$STATUS_OUTPUT" | grep -q "Active: active"; then
    log "✅ Serviço ativo e rodando"
else
    error "❌ Status anômalo do serviço"
fi

# ============================================================================
# 2. VERIFICAÇÃO DE ARQUIVOS DE CONFIGURAÇÃO
# ============================================================================

log "📋 Verificando arquivos de configuração..."

# Diretórios e arquivos importantes
COLLECTOR_DIR="/opt/samureye/collector"
ENV_FILE="/etc/samureye-collector/.env"
LOG_FILE="/var/log/samureye-collector/collector.log"
CONFIG_FILE="/opt/samureye/collector/config.json"

# Verificar diretório principal
if [ -d "$COLLECTOR_DIR" ]; then
    log "✅ Diretório collector existe: $COLLECTOR_DIR"
else
    error "❌ Diretório collector não existe: $COLLECTOR_DIR"
    echo "   • Execute reinstalação do sistema base"
    exit 1
fi

# Verificar arquivo .env
if [ -f "$ENV_FILE" ]; then
    log "✅ Arquivo .env existe: $ENV_FILE"
    
    # Verificar variáveis críticas
    CRITICAL_VARS=("COLLECTOR_ID" "API_SERVER" "COLLECTOR_TOKEN")
    
    for var in "${CRITICAL_VARS[@]}"; do
        if grep -q "^$var=" "$ENV_FILE"; then
            if [ "$var" = "COLLECTOR_TOKEN" ]; then
                TOKEN_VALUE=$(grep "^$var=" "$ENV_FILE" | cut -d'=' -f2-)
                if [ -n "$TOKEN_VALUE" ] && [ "$TOKEN_VALUE" != "" ]; then
                    log "   ✅ Variável '$var' definida e não-vazia"
                else
                    error "   ❌ Variável '$var' vazia"
                fi
            else
                log "   ✅ Variável '$var' definida"
            fi
        else
            error "   ❌ Variável '$var' AUSENTE"
        fi
    done
    
    # Mostrar valores (sanitizados)
    info "Configuração atual:"
    COLLECTOR_ID=$(grep "^COLLECTOR_ID=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "NÃO DEFINIDO")
    API_SERVER=$(grep "^API_SERVER=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "NÃO DEFINIDO")
    TOKEN_PREVIEW=""
    if grep -q "^COLLECTOR_TOKEN=" "$ENV_FILE"; then
        TOKEN_FULL=$(grep "^COLLECTOR_TOKEN=" "$ENV_FILE" | cut -d'=' -f2-)
        if [ -n "$TOKEN_FULL" ] && [ ${#TOKEN_FULL} -gt 8 ]; then
            TOKEN_PREVIEW="${TOKEN_FULL:0:8}..."
        elif [ -n "$TOKEN_FULL" ]; then
            TOKEN_PREVIEW="***"
        else
            TOKEN_PREVIEW="VAZIO"
        fi
    else
        TOKEN_PREVIEW="NÃO DEFINIDO"
    fi
    
    echo "   • COLLECTOR_ID: $COLLECTOR_ID"
    echo "   • API_SERVER: $API_SERVER"
    echo "   • COLLECTOR_TOKEN: $TOKEN_PREVIEW"
    
else
    error "❌ Arquivo .env não existe: $ENV_FILE"
    echo "   • Collector não foi registrado corretamente"
fi

# ============================================================================
# 3. VERIFICAÇÃO DE CONECTIVIDADE
# ============================================================================

log "🌐 Verificando conectividade com API..."

API_SERVER=$(grep "^API_SERVER=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "https://api.samureye.com.br")

# Teste 1: Conectividade básica
if curl -s --connect-timeout 10 --max-time 30 "$API_SERVER/health" >/dev/null 2>&1; then
    log "✅ API acessível: $API_SERVER"
else
    error "❌ API inacessível: $API_SERVER"
    echo "   • Verifique conectividade de rede"
    echo "   • Verifique firewall/proxy"
fi

# Teste 2: Endpoint específico de heartbeat
HEARTBEAT_URL="$API_SERVER/collector-api/heartbeat"
if curl -s --connect-timeout 10 --max-time 30 "$HEARTBEAT_URL" >/dev/null 2>&1; then
    log "✅ Endpoint heartbeat acessível"
else
    warn "⚠️ Endpoint heartbeat pode estar inacessível"
    echo "   • URL: $HEARTBEAT_URL"
fi

# ============================================================================
# 4. ANÁLISE DE LOGS ESPECÍFICA
# ============================================================================

log "📝 Analisando logs do collector..."

if [ -f "$LOG_FILE" ]; then
    log "✅ Log file existe: $LOG_FILE"
    
    # Buscar erros 401 recentes
    info "Últimos erros 401:"
    grep "401.*Unauthorized" "$LOG_FILE" | tail -5 || echo "   • Nenhum erro 401 encontrado"
    
    # Buscar tentativas de registro
    info "Últimas tentativas de registro:"
    grep "Registrando collector" "$LOG_FILE" | tail -3 || echo "   • Nenhuma tentativa de registro encontrada"
    
    # Verificar se nome do collector está vazio
    info "Verificando configuração carregada:"
    RECENT_CONFIG=$(grep "Configuração carregada" "$LOG_FILE" | tail -1 || echo "")
    if [ -n "$RECENT_CONFIG" ]; then
        echo "   • $RECENT_CONFIG"
        if echo "$RECENT_CONFIG" | grep -q "Nome:$"; then
            warn "⚠️ Nome do collector está vazio"
        fi
    fi
    
    # Verificar tokens
    info "Status do token nos logs:"
    if grep -q "Token não encontrado" "$LOG_FILE"; then
        error "❌ Collector não encontra token válido"
    elif grep -q "Token encontrado" "$LOG_FILE"; then
        log "✅ Token encontrado em algum momento"
    fi
    
else
    error "❌ Log file não existe: $LOG_FILE"
fi

# ============================================================================
# 5. TESTE MANUAL DE AUTENTICAÇÃO
# ============================================================================

log "🧪 Testando autenticação manual..."

if [ -f "$ENV_FILE" ]; then
    COLLECTOR_TOKEN=$(grep "^COLLECTOR_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "")
    
    if [ -n "$COLLECTOR_TOKEN" ] && [ "$COLLECTOR_TOKEN" != "" ]; then
        info "Testando token existente..."
        
        # Tentar heartbeat com token atual
        TEST_RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $COLLECTOR_TOKEN" \
            -X POST \
            --data '{"hostname":"vlxsam04","status":"online","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"}' \
            "$HEARTBEAT_URL" \
            --connect-timeout 10 \
            --max-time 30 2>&1)
        
        HTTP_STATUS=$(echo $TEST_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
        RESPONSE_BODY=$(echo $TEST_RESPONSE | sed -e 's/HTTPSTATUS:.*//g')
        
        if [ "$HTTP_STATUS" = "200" ]; then
            log "✅ Token atual é válido - heartbeat funcionou"
            echo "   • Response: $RESPONSE_BODY"
        elif [ "$HTTP_STATUS" = "401" ]; then
            error "❌ Token atual inválido ou expirado"
            echo "   • Response: $RESPONSE_BODY"
        else
            warn "⚠️ Resposta inesperada do heartbeat"
            echo "   • Status: $HTTP_STATUS"
            echo "   • Response: $RESPONSE_BODY"
        fi
    else
        error "❌ Token não encontrado ou vazio no arquivo .env"
    fi
else
    error "❌ Não foi possível testar - arquivo .env não existe"
fi

# ============================================================================
# 6. VERIFICAR STATUS NO BACKEND
# ============================================================================

log "🔍 Verificando status do collector no backend..."

COLLECTOR_ID=$(grep "^COLLECTOR_ID=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "")

if [ -n "$COLLECTOR_ID" ] && [ "$COLLECTOR_ID" != "" ]; then
    info "Tentando buscar informações do collector ID: $COLLECTOR_ID"
    
    # Tentar buscar collector via API pública (se existir)
    COLLECTOR_INFO=$(curl -s --connect-timeout 10 --max-time 30 \
        "$API_SERVER/api/collectors/$COLLECTOR_ID" 2>/dev/null || echo "")
    
    if [ -n "$COLLECTOR_INFO" ] && ! echo "$COLLECTOR_INFO" | grep -q "error\|Error\|404"; then
        log "✅ Collector encontrado no backend"
        echo "$COLLECTOR_INFO" | head -5
    else
        warn "⚠️ Collector pode não estar registrado no backend"
    fi
else
    warn "⚠️ COLLECTOR_ID não encontrado - impossível verificar backend"
fi

# ============================================================================
# 7. RECOMENDAÇÕES DE CORREÇÃO
# ============================================================================

echo ""
log "🔧 RECOMENDAÇÕES DE CORREÇÃO:"
echo ""

error "PROBLEMA IDENTIFICADO: Collector perdeu autenticação válida"
echo ""

echo "🔍 POSSÍVEIS CAUSAS:"
echo "   1. Token de autenticação expirado"
echo "   2. Collector foi removido do backend"
echo "   3. Token corrompido no arquivo .env"
echo "   4. Problemas de conectividade intermitente"
echo ""

echo "🔧 CORREÇÕES SUGERIDAS:"
if [ -z "$COLLECTOR_TOKEN" ] || [ "$COLLECTOR_TOKEN" = "" ]; then
    echo "   • Token ausente - necessário registro manual"
    echo "   • Execute: register-collector.sh com novo token"
elif grep -q "401.*Unauthorized" "$LOG_FILE" 2>/dev/null; then
    echo "   • Token inválido - necessário novo registro"
    echo "   • Execute: register-collector.sh com token válido"
else
    echo "   • Verificar logs detalhados"
    echo "   • Pode necessitar re-registro"
fi

echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "   1. Crie novo collector na interface admin"
echo "   2. Copie o token de enrollment"
echo "   3. Execute script de registro:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- <tenant-slug> <enrollment-token>"
echo ""

log "✅ DIAGNÓSTICO CONCLUÍDO"
echo ""

# Mostrar status final
if systemctl is-active --quiet samureye-collector 2>/dev/null; then
    warn "⚠️ Serviço ativo mas com problemas de autenticação"
else
    error "❌ Serviço inativo"
fi

echo "🔧 CORREÇÃO DISPONÍVEL:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/fix-collector-401-issue.sh | bash"
echo ""

exit 0