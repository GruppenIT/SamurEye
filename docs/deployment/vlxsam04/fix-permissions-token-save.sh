#!/bin/bash

#==============================================================================
# CORREÇÃO: Permissões e Salvamento de Token - vlxsam04
# 
# SOLUÇÃO: Corrige permissões de arquivo e processo de salvamento de token
#         Resolve problema onde script reporta sucesso mas não salva token
#         E problema de Permission denied do serviço
#==============================================================================

set -e

echo "🛠️  CORREÇÃO: Permissões e Salvamento de Token"
echo "==============================================="
echo "Data/Hora: $(date)"
echo

# Configurações
CONFIG_FILE="/etc/samureye-collector/.env"
CONFIG_DIR="/etc/samureye-collector"
COLLECTOR_USER="samureye-collector"
SERVICE_NAME="samureye-collector"
LOG_FILE="/var/log/samureye-collector/collector.log"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

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

# 1. Parar serviço se estiver rodando
echo "⏹️ 1. PARANDO SERVIÇO"
echo "--------------------"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "🔄 Parando serviço $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME"
    
    # Aguardar parada
    for i in {1..10}; do
        if ! systemctl is-active --quiet "$SERVICE_NAME"; then
            echo "✅ Serviço parado"
            break
        fi
        echo "   Aguardando... ($i/10)"
        sleep 1
    done
    
    # Terminar processos órfãos
    ORPHAN_PIDS=$(pgrep -f "samureye.*collector" 2>/dev/null || true)
    if [ -n "$ORPHAN_PIDS" ]; then
        echo "🔪 Terminando processos órfãos: $ORPHAN_PIDS"
        kill $ORPHAN_PIDS 2>/dev/null || true
        sleep 2
    fi
else
    echo "ℹ️  Serviço já estava parado"
fi
echo

# 2. Criar/verificar usuário do serviço
echo "👤 2. CONFIGURANDO USUÁRIO DO SERVIÇO"
echo "------------------------------------"

if ! id "$COLLECTOR_USER" &>/dev/null; then
    echo "👤 Criando usuário $COLLECTOR_USER..."
    useradd --system --no-create-home --shell /bin/false "$COLLECTOR_USER"
    echo "✅ Usuário criado"
else
    echo "✅ Usuário $COLLECTOR_USER já existe"
fi

# Verificar grupos necessários
echo "🔍 Verificando grupos do usuário..."
usermod -a -G adm,systemd-journal "$COLLECTOR_USER" 2>/dev/null || true
echo "✅ Grupos configurados"
echo

# 3. Corrigir permissões de diretórios e arquivos
echo "🔒 3. CORRIGINDO PERMISSÕES"
echo "--------------------------"

# Criar diretório de configuração se não existir
if [ ! -d "$CONFIG_DIR" ]; then
    echo "📁 Criando diretório $CONFIG_DIR..."
    mkdir -p "$CONFIG_DIR"
fi

# Definir permissões corretas do diretório
echo "🔒 Configurando permissões do diretório..."
chown root:"$COLLECTOR_USER" "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"
echo "✅ Diretório: owner=root, group=$COLLECTOR_USER, mode=750"

# Criar arquivo de configuração se não existir
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📄 Criando arquivo de configuração..."
    touch "$CONFIG_FILE"
fi

# Fazer backup do arquivo atual
echo "📁 Fazendo backup da configuração..."
backup_file "$CONFIG_FILE"

# Definir permissões corretas do arquivo
echo "🔒 Configurando permissões do arquivo..."
chown root:"$COLLECTOR_USER" "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"
echo "✅ Arquivo: owner=root, group=$COLLECTOR_USER, mode=640"

# Criar diretório de logs
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ]; then
    echo "📁 Criando diretório de logs..."
    mkdir -p "$LOG_DIR"
fi

echo "🔒 Configurando permissões do diretório de logs..."
chown root:"$COLLECTOR_USER" "$LOG_DIR"
chmod 750 "$LOG_DIR"

if [ -f "$LOG_FILE" ]; then
    chown root:"$COLLECTOR_USER" "$LOG_FILE"
    chmod 640 "$LOG_FILE"
fi
echo "✅ Logs configurados"
echo

# 4. Corrigir configuração do serviço systemd
echo "🔧 4. CORRIGINDO CONFIGURAÇÃO DO SERVIÇO"
echo "---------------------------------------"

if [ -f "$SERVICE_FILE" ]; then
    echo "📄 Fazendo backup do arquivo de serviço..."
    backup_file "$SERVICE_FILE"
    
    # Verificar se User está definido corretamente
    if grep -q "^User=" "$SERVICE_FILE"; then
        CURRENT_USER=$(grep "^User=" "$SERVICE_FILE" | cut -d'=' -f2)
        if [ "$CURRENT_USER" != "$COLLECTOR_USER" ]; then
            echo "🔄 Corrigindo usuário no arquivo de serviço: $CURRENT_USER → $COLLECTOR_USER"
            sed -i "s/^User=.*/User=$COLLECTOR_USER/" "$SERVICE_FILE"
        else
            echo "✅ Usuário no serviço já está correto: $COLLECTOR_USER"
        fi
    else
        echo "➕ Adicionando usuário ao arquivo de serviço..."
        # Adicionar User após [Service]
        sed -i '/^\[Service\]/a User='$COLLECTOR_USER "$SERVICE_FILE"
    fi
    
    # Verificar Group
    if ! grep -q "^Group=" "$SERVICE_FILE"; then
        echo "➕ Adicionando grupo ao arquivo de serviço..."
        sed -i '/^User='$COLLECTOR_USER'/a Group='$COLLECTOR_USER "$SERVICE_FILE"
    fi
    
    echo "✅ Arquivo de serviço atualizado"
else
    echo "❌ Arquivo de serviço não encontrado: $SERVICE_FILE"
    echo "⚠️  Será necessário executar install-hard-reset para recriar"
fi
echo

# 5. Criar configuração correta
echo "📝 5. CRIANDO CONFIGURAÇÃO CORRETA"
echo "---------------------------------"

echo "📄 Criando configuração com permissões corretas..."
cat > "$CONFIG_FILE" << 'EOF'
# SamurEye Collector Configuration
# Configuração com permissões corrigidas

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

# Aplicar permissões corretas novamente
chown root:"$COLLECTOR_USER" "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"
echo "✅ Configuração criada com permissões corretas"
echo

# 6. Testar permissões
echo "🧪 6. TESTANDO PERMISSÕES"
echo "------------------------"

echo "🔍 Testando leitura como usuário $COLLECTOR_USER..."
if sudo -u "$COLLECTOR_USER" cat "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "✅ Usuário $COLLECTOR_USER consegue ler o arquivo"
    PERMISSIONS_OK=true
else
    echo "❌ Usuário $COLLECTOR_USER ainda não consegue ler o arquivo"
    echo "🔍 Detalhes das permissões:"
    ls -la "$CONFIG_FILE" | sed 's/^/    /'
    echo "🔍 Grupos do usuário:"
    groups "$COLLECTOR_USER" | sed 's/^/    /'
    PERMISSIONS_OK=false
fi

echo "🔍 Testando escrita como root..."
if echo "# Teste $(date)" >> "$CONFIG_FILE" 2>/dev/null; then
    echo "✅ Root consegue escrever no arquivo"
    # Remover linha de teste
    sed -i '/# Teste/d' "$CONFIG_FILE" 2>/dev/null
else
    echo "❌ Root não consegue escrever no arquivo"
    PERMISSIONS_OK=false
fi
echo

# 7. Recarregar systemd
echo "🔄 7. RECARREGANDO SYSTEMD"
echo "-------------------------"

echo "🔄 Recarregando daemon..."
systemctl daemon-reload
echo "✅ Daemon recarregado"

echo "🔄 Resetando falhas..."
systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
echo "✅ Falhas resetadas"
echo

# 8. Limpar logs antigos
echo "📝 8. LIMPANDO LOGS ANTIGOS"
echo "--------------------------"

if [ -f "$LOG_FILE" ]; then
    echo "📄 Fazendo backup e limpeza do log..."
    backup_file "$LOG_FILE"
    
    # Manter apenas últimas 50 linhas
    tail -50 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
    
    # Aplicar permissões corretas
    chown root:"$COLLECTOR_USER" "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    # Adicionar marcador
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - === PERMISSÕES CORRIGIDAS ===" >> "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - Usuário: $COLLECTOR_USER, Permissões: 640" >> "$LOG_FILE"
    
    echo "✅ Log limpo e permissões aplicadas"
else
    echo "ℹ️  Log será criado automaticamente com permissões corretas"
fi
echo

# 9. Criar script melhorado de salvamento de token
echo "💾 9. CRIANDO SCRIPT DE SALVAMENTO DE TOKEN"
echo "------------------------------------------"

SAVE_TOKEN_SCRIPT="/opt/samureye/collector/scripts/save-token.sh"
mkdir -p "$(dirname "$SAVE_TOKEN_SCRIPT")"

cat > "$SAVE_TOKEN_SCRIPT" << 'EOF'
#!/bin/bash

# Script para salvar token no arquivo de configuração
# Uso: save-token.sh <collector_token> [enrollment_token]

CONFIG_FILE="/etc/samureye-collector/.env"

if [ $# -lt 1 ]; then
    echo "Erro: Token do collector é obrigatório"
    echo "Uso: $0 <collector_token> [enrollment_token]"
    exit 1
fi

COLLECTOR_TOKEN="$1"
ENROLLMENT_TOKEN="${2:-}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Erro: Arquivo de configuração não encontrado: $CONFIG_FILE"
    exit 1
fi

# Fazer backup
cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# Salvar tokens
if grep -q "^COLLECTOR_TOKEN=" "$CONFIG_FILE"; then
    sed -i "s/^COLLECTOR_TOKEN=.*/COLLECTOR_TOKEN=$COLLECTOR_TOKEN/" "$CONFIG_FILE"
else
    echo "COLLECTOR_TOKEN=$COLLECTOR_TOKEN" >> "$CONFIG_FILE"
fi

if [ -n "$ENROLLMENT_TOKEN" ]; then
    if grep -q "^ENROLLMENT_TOKEN=" "$CONFIG_FILE"; then
        sed -i "s/^ENROLLMENT_TOKEN=.*/ENROLLMENT_TOKEN=$ENROLLMENT_TOKEN/" "$CONFIG_FILE"
    else
        echo "ENROLLMENT_TOKEN=$ENROLLMENT_TOKEN" >> "$CONFIG_FILE"
    fi
fi

echo "Token salvo com sucesso no arquivo $CONFIG_FILE"
echo "COLLECTOR_TOKEN: ${COLLECTOR_TOKEN:0:8}...${COLLECTOR_TOKEN: -8}"
if [ -n "$ENROLLMENT_TOKEN" ]; then
    echo "ENROLLMENT_TOKEN: ${ENROLLMENT_TOKEN:0:8}...${ENROLLMENT_TOKEN: -8}"
fi
EOF

chmod +x "$SAVE_TOKEN_SCRIPT"
echo "✅ Script de salvamento criado: $SAVE_TOKEN_SCRIPT"
echo

# 10. Verificação final
echo "✅ 10. VERIFICAÇÃO FINAL"
echo "-----------------------"

echo "📊 Status final:"
echo "   🔴 Serviço: $(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo 'inactive')"
echo "   👤 Usuário: $COLLECTOR_USER $(id "$COLLECTOR_USER" 2>/dev/null | cut -d' ' -f1 || echo 'não encontrado')"
echo "   📁 Config dir: $(ls -ld "$CONFIG_DIR" | awk '{print $1, $3, $4}')"
echo "   📄 Config file: $(ls -l "$CONFIG_FILE" | awk '{print $1, $3, $4}')"
echo "   🔒 Permissões: $([ "$PERMISSIONS_OK" = true ] && echo "OK" || echo "PROBLEMA")"
echo

if [ "$PERMISSIONS_OK" = true ]; then
    echo "🎯 CORREÇÃO CONCLUÍDA COM SUCESSO!"
    echo "================================="
    echo
    echo "✅ Todas as permissões foram corrigidas"
    echo "✅ Usuário do serviço pode ler o arquivo de configuração"
    echo "✅ Script de salvamento de token criado"
    echo
    echo "📋 PRÓXIMOS PASSOS:"
    echo "  1️⃣  Execute novo registro do collector"
    echo "  2️⃣  O serviço será iniciado automaticamente"
    echo "  3️⃣  Não haverá mais erros Permission denied"
    echo
    echo "🔧 COMANDO DE REGISTRO:"
    echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- <tenant-slug> <enrollment-token>"
    echo
    echo "💡 OU use o script local de salvamento se necessário:"
    echo "$SAVE_TOKEN_SCRIPT <collector-token>"
else
    echo "⚠️  CORREÇÃO PARCIAL"
    echo "==================="
    echo
    echo "❌ Ainda há problemas com as permissões"
    echo "🔧 Pode ser necessário executar install-hard-reset completo"
    echo
    echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/install-hard-reset.sh | bash"
fi

echo
echo "Conclusão: $(date)"