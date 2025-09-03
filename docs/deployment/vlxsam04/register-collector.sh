#!/bin/bash

# ============================================================================
# SCRIPT DE REGISTRO COLLECTOR SamurEye - vlxsam04
# ============================================================================
# Script para registrar collector usando tenant-slug e enrollment-token
# Utiliza o endpoint /collector-api/register da aplicação SamurEye
#
# Uso: 
#   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- <tenant-slug> <enrollment-token>
#
# Exemplos:
#   bash register-collector.sh gruppen-it abc123-def456-ghi789
#   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- gruppen-it abc123-def456-ghi789
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

# Configurações
API_SERVER="https://api.samureye.com.br"
WORKING_DIR="/opt/samureye-collector"

echo ""
echo "🔧 REGISTRO COLLECTOR SAMUREYE"
echo "=============================="
echo ""

# ============================================================================
# 1. VALIDAÇÃO DE PARÂMETROS
# ============================================================================

# Verificar se os parâmetros foram fornecidos
if [ $# -ne 2 ]; then
    error "❌ Parâmetros incorretos!"
    echo ""
    echo "📋 USO CORRETO:"
    echo "   bash register-collector.sh <tenant-slug> <enrollment-token>"
    echo ""
    echo "📝 EXEMPLO:"
    echo "   bash register-collector.sh gruppen-it abc123-def456-ghi789"
    echo ""
    echo "💡 OU VIA CURL:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- gruppen-it abc123-def456-ghi789"
    echo ""
    exit 1
fi

TENANT_SLUG="$1"
ENROLLMENT_TOKEN="$2"

log "🔍 Parâmetros recebidos:"
echo "   • Tenant Slug: $TENANT_SLUG"
echo "   • Token: ${ENROLLMENT_TOKEN:0:8}...${ENROLLMENT_TOKEN: -8}"

# ============================================================================
# 2. VERIFICAÇÃO DE PREREQUISITOS
# ============================================================================

log "🔍 Verificando prerequisitos..."

# Verificar se collector base está instalado
if [ ! -d "$WORKING_DIR" ]; then
    error "❌ Collector base não encontrado em $WORKING_DIR"
    echo ""
    echo "💡 EXECUTE PRIMEIRO:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/install-hard-reset.sh | bash"
    echo ""
    exit 1
fi

# Verificar se curl está disponível
if ! command -v curl >/dev/null 2>&1; then
    error "❌ curl não está instalado"
    echo "   • Ubuntu/Debian: sudo apt-get install curl"
    echo "   • CentOS/RHEL: sudo yum install curl"
    exit 1
fi

# Verificar se jq está disponível
if ! command -v jq >/dev/null 2>&1; then
    warn "⚠️ jq não encontrado, instalando..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq
    else
        error "❌ Não foi possível instalar jq automaticamente"
        exit 1
    fi
fi

log "✅ Prerequisitos verificados"

# ============================================================================
# 3. COLETA DE INFORMAÇÕES DO SISTEMA
# ============================================================================

log "🔍 Coletando informações do sistema..."

# Hostname do sistema
HOSTNAME=$(hostname)
log "   • Hostname: $HOSTNAME"

# IP Address primário
IP_ADDRESS=""
if command -v ip >/dev/null 2>&1; then
    # Método preferido com 'ip'
    IP_ADDRESS=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
elif command -v ifconfig >/dev/null 2>&1; then
    # Fallback com ifconfig
    IP_ADDRESS=$(ifconfig | grep -Eo 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
fi

if [ -z "$IP_ADDRESS" ]; then
    warn "⚠️ Não foi possível detectar IP automaticamente, usando localhost"
    IP_ADDRESS="127.0.0.1"
fi

log "   • IP Address: $IP_ADDRESS"

# ============================================================================
# 4. TESTE DE CONECTIVIDADE
# ============================================================================

log "🌐 Testando conectividade com API..."

# Testar conectividade básica
if ! curl -s --connect-timeout 10 "$API_SERVER/api/health" >/dev/null; then
    error "❌ Não foi possível conectar ao servidor API"
    echo "   • Verifique a conectividade de rede"
    echo "   • Verifique se $API_SERVER está acessível"
    echo ""
    
    # Teste diagnóstico
    info "🔍 Diagnóstico de conectividade:"
    echo "   • Testando DNS..."
    if nslookup api.samureye.com.br >/dev/null 2>&1; then
        echo "     ✅ DNS OK"
    else
        echo "     ❌ DNS falhou"
    fi
    
    echo "   • Testando ping..."
    if ping -c 1 api.samureye.com.br >/dev/null 2>&1; then
        echo "     ✅ Ping OK"
    else
        echo "     ❌ Ping falhou"
    fi
    
    exit 1
fi

log "✅ Conectividade OK"

# ============================================================================
# 5. REGISTRO DO COLLECTOR
# ============================================================================

log "🔧 Registrando collector..."

# Preparar payload JSON
PAYLOAD=$(cat <<EOF
{
    "tenantSlug": "$TENANT_SLUG",
    "enrollmentToken": "$ENROLLMENT_TOKEN",
    "hostname": "$HOSTNAME",
    "ipAddress": "$IP_ADDRESS"
}
EOF
)

log "📤 Enviando registro para API..."

# Fazer requisição de registro
RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "$PAYLOAD" \
    "$API_SERVER/collector-api/register" \
    --connect-timeout 30 \
    --max-time 60)

# Separar response body e HTTP status
HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

# ============================================================================
# 6. PROCESSAMENTO DA RESPOSTA
# ============================================================================

log "📥 Processando resposta da API..."

if [ "$HTTP_STATUS" = "200" ]; then
    log "🎉 COLLECTOR REGISTRADO COM SUCESSO!"
    echo ""
    
    # Extrair informações da resposta
    COLLECTOR_NAME=$(echo "$RESPONSE_BODY" | jq -r '.collector.name // "N/A"')
    TENANT_NAME=$(echo "$RESPONSE_BODY" | jq -r '.collector.tenantName // "N/A"')
    COLLECTOR_STATUS=$(echo "$RESPONSE_BODY" | jq -r '.collector.status // "N/A"')
    
    log "📋 DETALHES DO REGISTRO:"
    echo "   • Nome do Collector: $COLLECTOR_NAME"
    echo "   • Tenant: $TENANT_NAME"
    echo "   • Status: $COLLECTOR_STATUS"
    echo "   • Hostname: $HOSTNAME"
    echo "   • IP: $IP_ADDRESS"
    echo ""
    
    log "✅ Collector está online e enviando telemetria"
    echo ""
    
elif [ "$HTTP_STATUS" = "404" ]; then
    error "❌ REGISTRO FALHOU - Collector ou token não encontrado"
    echo ""
    echo "🔍 POSSÍVEIS CAUSAS:"
    echo "   • Token de enrollment inválido ou expirado"
    echo "   • Collector não existe no tenant especificado"
    echo "   • Tenant slug incorreto"
    echo ""
    echo "💡 SOLUÇÕES:"
    echo "   1. Verifique se o collector foi criado na interface admin"
    echo "   2. Regenere o token se tiver expirado (15 minutos)"
    echo "   3. Confirme o tenant slug correto"
    echo ""
    
    # Mostrar detalhes do erro se disponível
    if [ -n "$RESPONSE_BODY" ]; then
        ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.message // ""')
        if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
            echo "📝 DETALHES DO ERRO:"
            echo "   $ERROR_MSG"
            echo ""
        fi
    fi
    
    exit 1
    
elif [ "$HTTP_STATUS" = "400" ]; then
    error "❌ REGISTRO FALHOU - Token expirado"
    echo ""
    echo "⏰ O token de enrollment expirou (validade: 15 minutos)"
    echo ""
    echo "💡 SOLUÇÃO:"
    echo "   1. Acesse a interface de administração"
    echo "   2. Vá para Gestão de Coletores"
    echo "   3. Clique em 'Regenerar Token' no collector desejado"
    echo "   4. Execute novamente este script com o novo token"
    echo ""
    
    # Mostrar detalhes do erro se disponível
    if [ -n "$RESPONSE_BODY" ]; then
        ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.message // ""')
        if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
            echo "📝 DETALHES DO ERRO:"
            echo "   $ERROR_MSG"
            echo ""
        fi
    fi
    
    exit 1
    
else
    error "❌ ERRO DE COMUNICAÇÃO (HTTP $HTTP_STATUS)"
    echo ""
    echo "🔍 RESPOSTA DO SERVIDOR:"
    echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
    echo ""
    echo "💡 VERIFIQUE:"
    echo "   • Conectividade de rede"
    echo "   • Status do servidor API"
    echo "   • Parâmetros fornecidos"
    echo ""
    exit 1
fi

# ============================================================================
# 7. FINALIZAÇÃO
# ============================================================================

log "🎯 REGISTRO CONCLUÍDO COM SUCESSO!"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "   • O collector já está enviando telemetria automaticamente"
echo "   • Verifique o status na interface de administração"
echo "   • O collector aparecerá como 'ONLINE' na gestão de coletores"
echo ""

log "✅ Script de registro finalizado"

exit 0