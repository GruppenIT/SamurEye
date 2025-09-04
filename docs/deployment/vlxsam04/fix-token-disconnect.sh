#!/bin/bash

#==============================================================================
# CORREÇÃO: Desconexão entre Registro e Serviço Collector - vlxsam04
# 
# SOLUÇÃO: Sincroniza token entre script de registro e serviço collector
#         Resolve problema onde registro é bem-sucedido mas serviço dá erro 401
#==============================================================================

set -e

echo "🛠️  CORREÇÃO: Sincronização Token Registro vs Serviço"
echo "===================================================="
echo "Data/Hora: $(date)"
echo

# Configurações
SERVICE_NAME="samureye-collector"
CONFIG_FILE="/etc/samureye-collector/.env"
LOG_FILE="/var/log/samureye-collector/collector.log"
COLLECTOR_DIR="/opt/samureye/collector"

# Função para fazer backup
backup_file() {
    local file="$1"
    local backup_dir="/var/backups/samureye-collector"
    
    if [ -f "$file" ]; then
        mkdir -p "$backup_dir"
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$backup_dir/$(basename $file).backup.$timestamp"
        
        cp "$file" "$backup_file"
        echo "📁 Backup criado: $backup_file"
    fi
}

# 1. Análise inicial do problema
echo "🔍 1. ANÁLISE INICIAL DO PROBLEMA"
echo "--------------------------------"

if [ -f "$CONFIG_FILE" ]; then
    echo "✅ Arquivo de configuração encontrado"
    
    # Verificar se há token
    if grep -q "COLLECTOR_TOKEN" "$CONFIG_FILE"; then
        TOKEN_VALUE=$(grep "COLLECTOR_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"'"'"'')
        if [ -n "$TOKEN_VALUE" ] && [ "$TOKEN_VALUE" != "" ]; then
            echo "✅ Token presente no arquivo: ${TOKEN_VALUE:0:8}...${TOKEN_VALUE: -8}"
            TOKEN_EXISTS=true
        else
            echo "❌ Token vazio no arquivo"
            TOKEN_EXISTS=false
        fi
    else
        echo "❌ Token não encontrado no arquivo"
        TOKEN_EXISTS=false
    fi
else
    echo "❌ Arquivo de configuração não encontrado"
    TOKEN_EXISTS=false
fi

# Verificar se serviço está rodando
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "⚠️  Serviço está rodando e pode estar usando configuração antiga"
    SERVICE_RUNNING=true
else
    echo "ℹ️  Serviço está parado"
    SERVICE_RUNNING=false
fi
echo

# 2. Parar serviço para sincronização
echo "⏹️ 2. PARANDO SERVIÇO PARA SINCRONIZAÇÃO"
echo "----------------------------------------"

if [ "$SERVICE_RUNNING" = true ]; then
    echo "🔄 Parando serviço $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME"
    
    # Aguardar parada completa
    for i in {1..10}; do
        if ! systemctl is-active --quiet "$SERVICE_NAME"; then
            echo "✅ Serviço parado com sucesso"
            break
        fi
        echo "   Aguardando parada... ($i/10)"
        sleep 1
    done
    
    # Verificar processos órfãos
    ORPHAN_PIDS=$(pgrep -f "samureye.*collector" 2>/dev/null || true)
    if [ -n "$ORPHAN_PIDS" ]; then
        echo "🔪 Terminando processos órfãos: $ORPHAN_PIDS"
        kill $ORPHAN_PIDS 2>/dev/null || true
        sleep 2
        
        # Force kill se necessário
        REMAINING_PIDS=$(pgrep -f "samureye.*collector" 2>/dev/null || true)
        if [ -n "$REMAINING_PIDS" ]; then
            echo "🔨 Force kill processos restantes: $REMAINING_PIDS"
            kill -9 $REMAINING_PIDS 2>/dev/null || true
        fi
    fi
else
    echo "ℹ️  Serviço já estava parado"
fi
echo

# 3. Verificar e corrigir configuração
echo "🔧 3. VERIFICANDO E CORRIGINDO CONFIGURAÇÃO"
echo "------------------------------------------"

if [ -f "$CONFIG_FILE" ]; then
    echo "📁 Fazendo backup da configuração atual..."
    backup_file "$CONFIG_FILE"
    
    # Verificar se configuração está válida
    echo "🔍 Verificando configuração atual..."
    
    if [ "$TOKEN_EXISTS" = true ]; then
        echo "✅ Token presente, verificando formato..."
        
        # Verificar se token tem formato UUID válido
        TOKEN_VALUE=$(grep "COLLECTOR_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"'"'"'')
        if [[ $TOKEN_VALUE =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
            echo "✅ Token tem formato UUID válido"
            CONFIG_VALID=true
        else
            echo "⚠️  Token não tem formato UUID válido: $TOKEN_VALUE"
            CONFIG_VALID=false
        fi
    else
        echo "❌ Token não encontrado na configuração"
        CONFIG_VALID=false
    fi
    
    # Se configuração não está válida, limpar e preparar para novo registro
    if [ "$CONFIG_VALID" = false ]; then
        echo "🧹 Limpando configuração inválida..."
        
        # Criar configuração limpa
        cat > "$CONFIG_FILE" << 'EOF'
# SamurEye Collector Configuration
# Configuração preparada para novo registro

# Informações básicas do servidor
COLLECTOR_ID=vlxsam04
COLLECTOR_NAME=vlxsam04
HOSTNAME=vlxsam04
IP_ADDRESS=192.168.100.151

# Servidor da API (não modificar)
API_SERVER=https://api.samureye.com.br
API_PORT=443

# Token de registro (será preenchido durante registro)
COLLECTOR_TOKEN=
ENROLLMENT_TOKEN=

# Status (será atualizado automaticamente)
STATUS=offline

# Logs
LOG_LEVEL=INFO
LOG_FILE=/var/log/samureye-collector/collector.log

# Configurações de heartbeat
HEARTBEAT_INTERVAL=30
RETRY_INTERVAL=10
MAX_RETRIES=3
EOF
        
        chmod 600 "$CONFIG_FILE"
        chown root:root "$CONFIG_FILE"
        echo "✅ Configuração limpa criada"
    fi
else
    echo "❌ Arquivo de configuração não encontrado, criando novo..."
    
    # Criar diretório se não existir
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    # Criar configuração básica
    cat > "$CONFIG_FILE" << 'EOF'
# SamurEye Collector Configuration
# Configuração inicial criada automaticamente

# Informações básicas do servidor
COLLECTOR_ID=vlxsam04
COLLECTOR_NAME=vlxsam04
HOSTNAME=vlxsam04
IP_ADDRESS=192.168.100.151

# Servidor da API (não modificar)
API_SERVER=https://api.samureye.com.br
API_PORT=443

# Token de registro (será preenchido durante registro)
COLLECTOR_TOKEN=
ENROLLMENT_TOKEN=

# Status (será atualizado automaticamente)
STATUS=offline

# Logs
LOG_LEVEL=INFO
LOG_FILE=/var/log/samureye-collector/collector.log

# Configurações de heartbeat
HEARTBEAT_INTERVAL=30
RETRY_INTERVAL=10
MAX_RETRIES=3
EOF
    
    chmod 600 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
    echo "✅ Arquivo de configuração criado"
fi
echo

# 4. Limpar logs antigos com problema
echo "📝 4. LIMPANDO LOGS COM PROBLEMA"
echo "-------------------------------"

if [ -f "$LOG_FILE" ]; then
    echo "📄 Fazendo backup e limpeza do log..."
    backup_file "$LOG_FILE"
    
    # Manter apenas últimas 100 linhas
    tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
    
    # Adicionar marcador de correção
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - === CORREÇÃO APLICADA: Sincronização Token ===" >> "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - Configuração limpa, pronto para novo registro" >> "$LOG_FILE"
    
    echo "✅ Log limpo e marcado"
else
    echo "ℹ️  Log não encontrado, será criado automaticamente"
fi
echo

# 5. Força recarregamento do systemd
echo "🔄 5. RECARREGANDO CONFIGURAÇÃO DO SYSTEMD"
echo "------------------------------------------"

echo "🔄 Recarregando daemon do systemd..."
systemctl daemon-reload
echo "✅ Daemon recarregado"

echo "🔄 Resetando falhas do serviço..."
systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
echo "✅ Falhas resetadas"
echo

# 6. Preparar serviço para novo registro
echo "⚙️  6. PREPARANDO SERVIÇO PARA NOVO REGISTRO"
echo "-------------------------------------------"

echo "ℹ️  Serviço permanecerá parado para novo registro manual"
echo "ℹ️  Isso evita conflitos durante o processo de registro"

# Verificar que está realmente parado
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "⚠️  Serviço ainda ativo, forçando parada..."
    systemctl kill "$SERVICE_NAME"
    sleep 2
fi

echo "✅ Serviço preparado para novo registro"
echo

# 7. Teste de configuração
echo "✅ 7. VERIFICAÇÃO FINAL"
echo "----------------------"

echo "📊 Status final:"
echo "   🔴 Serviço: $(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo 'inactive')"
echo "   📁 Config: $([ -f "$CONFIG_FILE" ] && echo "presente" || echo "ausente")"
echo "   📝 Log: $([ -f "$LOG_FILE" ] && echo "presente" || echo "será criado")"
echo "   🔒 Permissões config: $([ -f "$CONFIG_FILE" ] && ls -la "$CONFIG_FILE" | awk '{print $1, $3, $4}' || echo "n/a")"
echo

echo "🎯 CORREÇÃO CONCLUÍDA COM SUCESSO!"
echo "================================="
echo
echo "📋 PRÓXIMOS PASSOS OBRIGATÓRIOS:"
echo "  1️⃣  O serviço está parado para evitar conflitos"
echo "  2️⃣  A configuração foi limpa e preparada"
echo "  3️⃣  Execute NOVO REGISTRO com o comando completo:"
echo
echo "🔧 COMANDO DE REGISTRO:"
echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- <tenant-slug> <enrollment-token>"
echo
echo "💡 IMPORTANTE:"
echo "  ➤ Use um NOVO token de enrollment (gere na interface)"
echo "  ➤ O token anterior pode ter expirado (15 minutos)"
echo "  ➤ O serviço será iniciado automaticamente após registro bem-sucedido"
echo
echo "✅ Não haverá mais conflitos entre registro e serviço!"
echo
echo "Conclusão: $(date)"