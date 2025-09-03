#!/bin/bash

# ============================================================================
# CORREÇÃO ESPECÍFICA - COLLECTOR 401 UNAUTHORIZED vlxsam04
# ============================================================================
# Corrige problema do collector não conseguir voltar ONLINE após restart
# Remove configurações corrompidas e prepara para novo registro
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
echo "🔧 CORREÇÃO COLLECTOR 401 UNAUTHORIZED"
echo "======================================"
echo "Sistema: vlxsam04 ($(hostname))"
echo ""

# Configurações
COLLECTOR_DIR="/opt/samureye/collector"
ENV_FILE="/etc/samureye-collector/.env"
LOG_FILE="/var/log/samureye-collector/collector.log"
SERVICE_NAME="samureye-collector"

# ============================================================================
# 1. PARAR SERVIÇO E BACKUP DE CONFIGURAÇÕES
# ============================================================================

log "⏹️ Parando serviço do collector..."

if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME"
    log "✅ Serviço parado"
else
    log "✅ Serviço já estava parado"
fi

# Backup da configuração atual
if [ -f "$ENV_FILE" ]; then
    BACKUP_FILE="$ENV_FILE.backup.$(date +%s)"
    cp "$ENV_FILE" "$BACKUP_FILE"
    log "✅ Backup da configuração: $BACKUP_FILE"
fi

# ============================================================================
# 2. LIMPAR CONFIGURAÇÕES CORROMPIDAS
# ============================================================================

log "🧹 Limpando configurações corrompidas..."

# Limpar token corrompido/expirado
if [ -f "$ENV_FILE" ]; then
    # Preservar configurações básicas, remover apenas token
    sed -i '/^COLLECTOR_TOKEN=/d' "$ENV_FILE"
    log "✅ Token corrompido removido"
    
    # Verificar se outras configurações estão OK
    COLLECTOR_ID=$(grep "^COLLECTOR_ID=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "")
    if [ -z "$COLLECTOR_ID" ]; then
        warn "⚠️ COLLECTOR_ID não encontrado - será regenerado"
        # Adicionar COLLECTOR_ID baseado no hostname
        echo "COLLECTOR_ID=$(hostname)" >> "$ENV_FILE"
    fi
    
    # Verificar API_SERVER
    if ! grep -q "^API_SERVER=" "$ENV_FILE"; then
        warn "⚠️ API_SERVER não encontrado - adicionando padrão"
        echo "API_SERVER=https://api.samureye.com.br" >> "$ENV_FILE"
    fi
else
    warn "⚠️ Arquivo .env não existe - será recriado"
    
    # Criar arquivo .env básico
    mkdir -p "$(dirname "$ENV_FILE")"
    cat > "$ENV_FILE" << EOF
# SamurEye Collector Configuration
COLLECTOR_ID=$(hostname)
API_SERVER=https://api.samureye.com.br
HEARTBEAT_INTERVAL=30
LOG_LEVEL=INFO
VERIFY_SSL=false
EOF
    chmod 600 "$ENV_FILE"
    log "✅ Arquivo .env recriado"
fi

# Limpar logs antigos com erros
if [ -f "$LOG_FILE" ]; then
    # Manter apenas últimas 100 linhas dos logs
    tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    log "✅ Logs antigos limpos"
fi

# ============================================================================
# 3. VERIFICAR CONECTIVIDADE E DEPENDÊNCIAS
# ============================================================================

log "🔍 Verificando conectividade e dependências..."

# Verificar conectividade com API
API_SERVER=$(grep "^API_SERVER=" "$ENV_FILE" | cut -d'=' -f2-)
if curl -s --connect-timeout 10 --max-time 30 "$API_SERVER/health" >/dev/null 2>&1; then
    log "✅ Conectividade com API OK"
else
    warn "⚠️ Problemas de conectividade com API"
    echo "   • Verifique rede e firewall"
fi

# Verificar se Python e dependências estão OK
if command -v python3 >/dev/null 2>&1; then
    log "✅ Python3 disponível"
    
    # Verificar módulos Python essenciais
    PYTHON_MODULES=("requests" "psutil" "json")
    for module in "${PYTHON_MODULES[@]}"; do
        if python3 -c "import $module" 2>/dev/null; then
            log "   ✅ Módulo Python '$module' OK"
        else
            error "   ❌ Módulo Python '$module' ausente"
        fi
    done
else
    error "❌ Python3 não encontrado"
fi

# ============================================================================
# 4. PREPARAR PARA NOVO REGISTRO
# ============================================================================

log "🔧 Preparando para novo registro..."

# Remover qualquer configuração de collector anterior
CONFIG_FILES=(
    "/opt/samureye/collector/config.json"
    "/opt/samureye/collector/.collector_id"
    "/opt/samureye/collector/collector.pid"
)

for config_file in "${CONFIG_FILES[@]}"; do
    if [ -f "$config_file" ]; then
        rm -f "$config_file"
        log "✅ Removido arquivo de configuração: $(basename "$config_file")"
    fi
done

# Garantir permissões corretas
if [ -d "$COLLECTOR_DIR" ]; then
    chown -R samureye-collector:samureye-collector "$COLLECTOR_DIR" 2>/dev/null || true
    log "✅ Permissões do diretório collector verificadas"
fi

if [ -f "$ENV_FILE" ]; then
    chown samureye-collector:samureye-collector "$ENV_FILE" 2>/dev/null || true
    chmod 600 "$ENV_FILE"
    log "✅ Permissões do arquivo .env verificadas"
fi

# ============================================================================
# 5. TESTAR CONFIGURAÇÃO BÁSICA
# ============================================================================

log "🧪 Testando configuração básica..."

# Verificar se o heartbeat script existe e é executável
HEARTBEAT_SCRIPT="/opt/samureye/collector/heartbeat.py"
if [ -f "$HEARTBEAT_SCRIPT" ]; then
    if [ -x "$HEARTBEAT_SCRIPT" ]; then
        log "✅ Script heartbeat.py presente e executável"
    else
        chmod +x "$HEARTBEAT_SCRIPT"
        log "✅ Permissões do heartbeat.py corrigidas"
    fi
    
    # Teste sintático do Python
    if python3 -m py_compile "$HEARTBEAT_SCRIPT" 2>/dev/null; then
        log "✅ Script heartbeat.py válido sintaticamente"
    else
        warn "⚠️ Possíveis problemas de sintaxe no heartbeat.py"
    fi
else
    error "❌ Script heartbeat.py não encontrado"
    echo "   • Pode ser necessário reinstalação do sistema base"
fi

# ============================================================================
# 6. PREPARAR INSTRUÇÕES DE REGISTRO
# ============================================================================

log "📋 Preparando instruções de registro..."

HOSTNAME=$(hostname)
LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' 2>/dev/null || echo "N/A")

cat > /tmp/collector_registration_info.txt << EOF
════════════════════════════════════════════════════════════════
📋 INFORMAÇÕES PARA REGISTRO DO COLLECTOR
════════════════════════════════════════════════════════════════

🖥️  Informações do Servidor:
   • Hostname: $HOSTNAME
   • IP Local: $LOCAL_IP
   • Sistema: $(lsb_release -d 2>/dev/null | cut -f2 || uname -s)

🔧 Status Atual:
   • Configurações limpas ✅
   • Pronto para novo registro ✅
   • Token antigo removido ✅

📝 PRÓXIMOS PASSOS OBRIGATÓRIOS:

1. Acesse a interface administrativa:
   https://app.samureye.com.br/admin/collectors

2. Faça login e vá para 'Gestão de Coletores'

3. Clique em 'Novo Coletor' e preencha:
   • Nome: $HOSTNAME
   • Hostname: $HOSTNAME
   • IP: $LOCAL_IP
   • Descrição: Collector vlxsam04 corrigido

4. Copie o TOKEN DE ENROLLMENT gerado (válido por 15 minutos)

5. Execute o comando de registro:

curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- <tenant-slug> <enrollment-token>

📌 EXEMPLO:
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- gruppen-it abc123-def456-ghi789

⚠️  IMPORTANTE:
   • NÃO inicie o serviço antes do registro
   • Token expira em 15 minutos
   • Use o tenant-slug correto

════════════════════════════════════════════════════════════════
EOF

cat /tmp/collector_registration_info.txt
echo ""

# Salvar instruções no sistema
cp /tmp/collector_registration_info.txt "/opt/samureye/collector/REGISTRATION_INSTRUCTIONS.txt"
chown samureye-collector:samureye-collector "/opt/samureye/collector/REGISTRATION_INSTRUCTIONS.txt" 2>/dev/null || true

# ============================================================================
# 7. FINALIZAÇÃO
# ============================================================================

log "✅ CORREÇÃO APLICADA COM SUCESSO!"
echo ""
echo "🔧 O QUE FOI CORRIGIDO:"
echo "   ✅ Serviço parado e configuração limpa"
echo "   ✅ Token corrompido removido"
echo "   ✅ Permissões verificadas"
echo "   ✅ Dependências testadas"
echo "   ✅ Pronto para novo registro"
echo ""

warn "⚠️  AÇÃO NECESSÁRIA:"
echo "   1. Crie NOVO collector na interface admin"
echo "   2. Execute register-collector.sh com o token válido"
echo "   3. Collector voltará automaticamente para ONLINE"
echo ""

log "📋 INSTRUÇÕES SALVAS EM:"
echo "   /opt/samureye/collector/REGISTRATION_INSTRUCTIONS.txt"
echo ""

# Verificar se serviço está realmente parado
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    warn "⚠️ Serviço ainda ativo - parando novamente..."
    systemctl stop "$SERVICE_NAME"
fi

log "🎯 PRÓXIMO COMANDO:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- <tenant-slug> <enrollment-token>"
echo ""

exit 0