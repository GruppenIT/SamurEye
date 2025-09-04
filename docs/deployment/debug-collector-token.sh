#!/bin/bash

echo "🔍 DIAGNÓSTICO TOKEN COLLECTOR - SamurEye"
echo "========================================"

# Função para log
log() { echo "[$(date +'%H:%M:%S')] $1"; }
error() { echo "[$(date +'%H:%M:%S')] ❌ $1"; }
success() { echo "[$(date +'%H:%M:%S')] ✅ $1"; }

# Configurações
CONFIG_FILE="/etc/samureye-collector/.env"
API_BASE="https://api.samureye.com.br"

log "📋 Verificando configurações do collector..."

# Verificar se arquivo .env existe
if [ ! -f "$CONFIG_FILE" ]; then
    error "Arquivo de configuração não encontrado: $CONFIG_FILE"
    exit 1
fi

# Carregar configurações
source "$CONFIG_FILE"

log "🔍 Configurações encontradas:"
echo "   • COLLECTOR_ID: $COLLECTOR_ID"
echo "   • COLLECTOR_TOKEN: ${COLLECTOR_TOKEN:0:8}...${COLLECTOR_TOKEN: -8}"
echo "   • API_SERVER: $API_SERVER"

# Testar conectividade básica
log "🌐 Testando conectividade com API..."
if curl -s --max-time 10 "$API_BASE/api/health" > /dev/null 2>&1; then
    success "Conectividade com API OK"
else
    error "Falha na conectividade com API"
    exit 1
fi

# Testar endpoint de heartbeat
log "💓 Testando endpoint heartbeat..."
HEARTBEAT_RESPONSE=$(curl -s -w "%{http_code}" \
    -X POST "$API_BASE/collector-api/heartbeat" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $COLLECTOR_TOKEN" \
    -H "X-Collector-Token: $COLLECTOR_TOKEN" \
    -d '{
        "collector_id": "'"$COLLECTOR_ID"'",
        "token": "'"$COLLECTOR_TOKEN"'",
        "telemetry": {
            "cpu_usage": 10.5,
            "memory_usage": 45.2,
            "disk_usage": 30.1,
            "network_rx": 1024,
            "network_tx": 2048,
            "processes": 125
        },
        "status": "online"
    }' 2>/dev/null)

HTTP_CODE="${HEARTBEAT_RESPONSE: -3}"
HEARTBEAT_BODY="${HEARTBEAT_RESPONSE%???}"

echo "   • HTTP Code: $HTTP_CODE"
echo "   • Response: $HEARTBEAT_BODY"

if [ "$HTTP_CODE" = "200" ]; then
    success "Heartbeat funcionando"
else
    error "Heartbeat falhando - Code: $HTTP_CODE"
fi

# Testar endpoint de jornadas pendentes (PRINCIPAL PROBLEMA)
log "🎯 Testando endpoint journeys/pending..."
PENDING_RESPONSE=$(curl -s -w "%{http_code}" \
    -X GET "$API_BASE/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_TOKEN" \
    -H "Authorization: Bearer $COLLECTOR_TOKEN" \
    2>/dev/null)

HTTP_CODE_PENDING="${PENDING_RESPONSE: -3}"
PENDING_BODY="${PENDING_RESPONSE%???}"

echo "   • HTTP Code: $HTTP_CODE_PENDING"
echo "   • Response: $PENDING_BODY"

if [ "$HTTP_CODE_PENDING" = "200" ]; then
    success "Endpoint journeys/pending funcionando"
    echo "   • Jornadas encontradas: $PENDING_BODY"
elif [ "$HTTP_CODE_PENDING" = "401" ]; then
    error "PROBLEMA ENCONTRADO - Token sendo rejeitado (401 Unauthorized)"
    echo "   • Error: $PENDING_BODY"
    
    # Diagnóstico adicional
    log "🔍 Diagnóstico detalhado do token..."
    
    # Verificar se token existe no banco de dados
    log "📊 Consultando banco de dados..."
    PGPASSWORD="SamurEye2024!" psql -h 192.168.100.153 -U samureye -d samureye -t -c \
        "SELECT id, name, status, enrollment_token, enrollment_token_expires FROM collectors WHERE enrollment_token = '$COLLECTOR_TOKEN';" 2>/dev/null || error "Falha ao consultar banco"
        
else
    error "Endpoint falhando - Code: $HTTP_CODE_PENDING"
fi

# Verificar logs do servidor se possível
log "📋 Verificando logs do servidor de aplicação..."
ssh -o ConnectTimeout=5 root@192.168.100.152 "tail -20 /var/log/samureye/app.log 2>/dev/null | grep -i 'collector\|token\|401'" 2>/dev/null || log "⚠️ Não foi possível acessar logs do servidor"

log "🎯 DIAGNÓSTICO CONCLUÍDO"

echo ""
echo "📋 RESUMO:"
if [ "$HTTP_CODE_PENDING" = "401" ]; then
    echo "   ❌ PROBLEMA: Token rejeitado pela API"
    echo "   💡 POSSÍVEIS CAUSAS:"
    echo "      • Token expirado no banco de dados"
    echo "      • Correções não aplicadas no servidor vlxsam02"  
    echo "      • Problema na lógica de verificação dupla"
    echo ""
    echo "   🔧 PRÓXIMOS PASSOS:"
    echo "      1. Verificar se vlxsam02 foi atualizado com as correções"
    echo "      2. Verificar logs do servidor de aplicação"
    echo "      3. Re-aplicar correções se necessário"
elif [ "$HTTP_CODE_PENDING" = "200" ]; then
    echo "   ✅ SUCESSO: Token funcionando corretamente"
else
    echo "   ⚠️ PROBLEMA: Erro inesperado (Code: $HTTP_CODE_PENDING)"
fi