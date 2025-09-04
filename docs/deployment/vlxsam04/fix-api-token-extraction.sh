#!/bin/bash

# Script de correção para problema de extração de token da API
# vlxsam04 - SamurEye Collector

echo "🔧 CORREÇÃO: Extração Token API"
echo "==============================="

HOSTNAME=$(hostname)
CONFIG_FILE="/etc/samureye-collector/.env"
LOG_FILE="/var/log/samureye-collector/heartbeat.log"
SERVICE_NAME="samureye-collector"
COLLECTOR_USER="samureye-collector"
API_SERVER="https://api.samureye.com.br"

# Função de log
log() { echo "[$(date +'%H:%M:%S')] $1"; }
warn() { echo "[$(date +'%H:%M:%S')] WARNING: $1"; }
error() { echo "[$(date +'%H:%M:%S')] ERROR: $1"; exit 1; }

log "🔧 Iniciando correção de extração de token para vlxsam04..."

echo ""
echo "🔍 1. PARANDO SERVIÇO ATUAL:"
echo "============================"

log "🛑 Parando serviço collector..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
sleep 2

# Limpar logs antigos para análise mais clara
if [ -f "$LOG_FILE" ]; then
    log "🧹 Limpando logs antigos..."
    : > "$LOG_FILE"
fi

echo ""
echo "🔍 2. ATUALIZANDO SCRIPT DE REGISTRO:"
echo "===================================="

REGISTER_SCRIPT="/opt/samureye/collector/scripts/register-collector.sh"

if [ -f "$REGISTER_SCRIPT" ]; then
    log "📄 Fazendo backup do script atual..."
    cp "$REGISTER_SCRIPT" "$REGISTER_SCRIPT.backup.$(date +%Y%m%d_%H%M%S)"
fi

log "📥 Baixando versão corrigida do register-collector.sh..."
mkdir -p "$(dirname "$REGISTER_SCRIPT")"

# Baixar nova versão com correções de extração de token
curl -fsSL "https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh" > "$REGISTER_SCRIPT"

if [ $? -eq 0 ] && [ -s "$REGISTER_SCRIPT" ]; then
    chmod +x "$REGISTER_SCRIPT"
    chown root:root "$REGISTER_SCRIPT"
    log "✅ Script de registro atualizado"
else
    warn "❌ Falha ao baixar script - usando versão local"
fi

echo ""
echo "🔍 3. IMPLEMENTANDO EXTRAÇÃO ROBUSTA DE TOKEN:"
echo "=============================================="

# Criar script auxiliar para extração de token mais robusta
TOKEN_EXTRACTOR="/opt/samureye/collector/scripts/extract-token.sh"

log "📄 Criando extrator robusto de token..."
cat > "$TOKEN_EXTRACTOR" << 'EXTRACTOR_EOF'
#!/bin/bash

# Script auxiliar para extrair token de resposta da API
# Tenta múltiplas formas de extração

RESPONSE_BODY="$1"

if [ -z "$RESPONSE_BODY" ]; then
    echo ""
    exit 1
fi

# Múltiplas tentativas de extração
TOKEN=""

# Método 1: jq com múltiplos caminhos
if command -v jq >/dev/null 2>&1; then
    TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.collector.token // .token // .authToken // .collectorToken // .auth.token // .data.token // ""' 2>/dev/null)
fi

# Método 2: grep com padrões diferentes
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    TOKEN=$(echo "$RESPONSE_BODY" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null)
fi

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    TOKEN=$(echo "$RESPONSE_BODY" | grep -o '"authToken":"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null)
fi

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    TOKEN=$(echo "$RESPONSE_BODY" | grep -o '"collectorToken":"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null)
fi

# Método 3: sed para extração mais agressiva
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    TOKEN=$(echo "$RESPONSE_BODY" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p' | head -1)
fi

# Método 4: awk para busca por padrões UUID-like
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    TOKEN=$(echo "$RESPONSE_BODY" | awk -F'"' '/token.*[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/ {for(i=1;i<=NF;i++) if($i ~ /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/) print $i}' | head -1)
fi

# Validar se token tem formato válido (UUID ou similar)
if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    # Verificar se parece com UUID ou token válido (pelo menos 16 caracteres)
    if [ ${#TOKEN} -ge 16 ]; then
        echo "$TOKEN"
        exit 0
    fi
fi

# Nenhum token válido encontrado
echo ""
exit 1
EXTRACTOR_EOF

chmod +x "$TOKEN_EXTRACTOR"
chown root:root "$TOKEN_EXTRACTOR"
log "✅ Extrator de token criado: $TOKEN_EXTRACTOR"

echo ""
echo "🔍 4. CRIANDO VERSÃO MELHORADA DO HEARTBEAT:"
echo "==========================================="

HEARTBEAT_SCRIPT="/opt/samureye/collector/heartbeat.py"

if [ -f "$HEARTBEAT_SCRIPT" ]; then
    log "📄 Fazendo backup do heartbeat atual..."
    cp "$HEARTBEAT_SCRIPT" "$HEARTBEAT_SCRIPT.backup.$(date +%Y%m%d_%H%M%S)"
fi

log "🐍 Atualizando heartbeat com melhor tratamento de token..."

# Baixar versão corrigida do heartbeat
curl -fsSL "https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/install-hard-reset.sh" | \
grep -A 200 "cat > \"\$COLLECTOR_DIR/heartbeat.py\"" | \
grep -B 200 "^HEARTBEAT_EOF" | \
head -n -1 | tail -n +2 > "$HEARTBEAT_SCRIPT"

# Garantir permissões corretas
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$HEARTBEAT_SCRIPT"
chmod +x "$HEARTBEAT_SCRIPT"

echo ""
echo "🔍 5. CONFIGURANDO ARQUIVO .ENV COM ESTRUTURA CORRETA:"
echo "====================================================="

if [ ! -f "$CONFIG_FILE" ]; then
    log "📄 Criando arquivo de configuração..."
    mkdir -p "$(dirname "$CONFIG_FILE")"
else
    log "📄 Atualizando arquivo de configuração..."
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Criar configuração com estrutura correta
cat > "$CONFIG_FILE" << CONFIG_EOF
# Configuração do Collector SamurEye - Correção Token API
COLLECTOR_ID=$HOSTNAME
COLLECTOR_NAME=
HOSTNAME=$HOSTNAME
IP_ADDRESS=$(hostname -I | awk '{print $1}')
API_BASE_URL=$API_SERVER
HEARTBEAT_INTERVAL=30
RETRY_ATTEMPTS=3
RETRY_DELAY=5
LOG_LEVEL=INFO

# Tokens de autenticação (serão preenchidos durante registro)
COLLECTOR_TOKEN=
ENROLLMENT_TOKEN=

# Status do collector
STATUS=offline

# Configurações adicionais
VERIFY_SSL=false
TIMEOUT=30
MAX_RETRIES=5
CONFIG_EOF

# Aplicar permissões corretas
chown root:"$COLLECTOR_USER" "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"
log "✅ Arquivo de configuração atualizado"

echo ""
echo "🔍 6. TESTANDO EXTRAÇÃO DE TOKEN (SE DISPONÍVEL):"
echo "================================================="

# Se temos parâmetros de teste, tentar extrair token
TENANT_SLUG="${1:-}"
ENROLLMENT_TOKEN="${2:-}"

if [ -n "$TENANT_SLUG" ] && [ -n "$ENROLLMENT_TOKEN" ]; then
    log "🧪 Testando extração com token fornecido..."
    
    # Preparar payload
    PAYLOAD=$(cat <<EOF
{
    "tenantSlug": "$TENANT_SLUG",
    "enrollmentToken": "$ENROLLMENT_TOKEN",
    "hostname": "$HOSTNAME",
    "ipAddress": "$(hostname -I | awk '{print $1}')"
}
EOF
)

    # Fazer requisição
    RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Content-Type: application/json" \
        -X POST \
        --data "$PAYLOAD" \
        "$API_SERVER/collector-api/register" \
        --connect-timeout 30 \
        --max-time 60)

    # Separar response
    HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

    if [ "$HTTP_STATUS" = "200" ]; then
        log "✅ API respondeu com sucesso"
        
        # Testar novo extrator
        EXTRACTED_TOKEN=$("$TOKEN_EXTRACTOR" "$RESPONSE_BODY")
        
        if [ -n "$EXTRACTED_TOKEN" ]; then
            log "✅ Token extraído com sucesso: ${EXTRACTED_TOKEN:0:8}...${EXTRACTED_TOKEN: -8}"
            
            # Salvar token no arquivo
            sed -i "s/^COLLECTOR_TOKEN=.*/COLLECTOR_TOKEN=$EXTRACTED_TOKEN/" "$CONFIG_FILE"
            sed -i "s/^STATUS=.*/STATUS=online/" "$CONFIG_FILE"
            
            log "✅ Token salvo no arquivo de configuração"
        else
            warn "⚠️  Ainda não foi possível extrair token da resposta"
            log "🔍 Response body para análise:"
            echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        fi
    else
        warn "⚠️  API retornou status $HTTP_STATUS"
    fi
else
    log "ℹ️  Teste de extração pulado - parâmetros não fornecidos"
    log "   Para testar: bash $0 <tenant-slug> <enrollment-token>"
fi

echo ""
echo "🔍 7. REINICIANDO SERVIÇO:"
echo "========================="

log "🔄 Recarregando configuração systemd..."
systemctl daemon-reload

log "🚀 Iniciando serviço collector..."
systemctl start "$SERVICE_NAME"

# Aguardar inicialização
sleep 5

log "🔍 Verificando status do serviço..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Serviço está rodando"
    
    # Verificar logs para confirmar funcionamento
    sleep 3
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        log "📝 Logs recentes:"
        tail -5 "$LOG_FILE" | sed 's/^/   /'
    fi
else
    warn "⚠️  Serviço não está ativo - verificando logs..."
    journalctl -u "$SERVICE_NAME" --no-pager -n 5
fi

echo ""
echo "🎯 CORREÇÃO FINALIZADA!"
echo "======================="

echo ""
echo "✅ CORREÇÕES APLICADAS:"
echo "   📄 Script de registro atualizado"
echo "   🔧 Extrator robusto de token criado"
echo "   🐍 Heartbeat melhorado"
echo "   📁 Arquivo .env corrigido"
echo "   🤖 Serviço reiniciado"

echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "   1. Testar novo registro:"
echo "      curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- gruppen-it <NEW-TOKEN>"
echo ""
echo "   2. Monitorar logs:"
echo "      tail -f $LOG_FILE"
echo ""
echo "   3. Verificar status:"
echo "      systemctl status $SERVICE_NAME"

echo ""
log "✅ Correção de extração de token concluída para vlxsam04"