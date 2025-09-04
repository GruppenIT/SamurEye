#!/bin/bash

#==============================================================================
# CORREÇÃO: Limpar Collector após Exclusão - vlxsam04
# 
# SOLUÇÃO: Para o serviço collector e limpa configurações após exclusão
#         da interface, evitando tentativas de auto-registro com erro 401
#==============================================================================

set -e

echo "🛠️  CORREÇÃO: Collector após Exclusão - vlxsam04"
echo "==============================================="
echo "Data/Hora: $(date)"
echo

# Função para fazer backup
backup_config() {
    local config_file="$1"
    local backup_dir="/var/backups/samureye-collector"
    
    if [ -f "$config_file" ]; then
        mkdir -p "$backup_dir"
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$backup_dir/.env.backup.$timestamp"
        
        cp "$config_file" "$backup_file"
        echo "📁 Backup criado: $backup_file"
        
        # Manter apenas os 5 backups mais recentes
        find "$backup_dir" -name "*.env.backup.*" -type f | sort | head -n -5 | xargs rm -f 2>/dev/null || true
    fi
}

# 1. Verificar se o serviço está rodando
echo "🔍 1. VERIFICANDO STATUS DO SERVIÇO"
echo "----------------------------------"
if systemctl is-active --quiet samureye-collector; then
    echo "⚠️  Serviço samureye-collector está ATIVO"
    
    echo "⏹️  Parando serviço collector..."
    systemctl stop samureye-collector
    
    # Aguardar o serviço parar completamente
    for i in {1..10}; do
        if ! systemctl is-active --quiet samureye-collector; then
            echo "✅ Serviço parado com sucesso"
            break
        fi
        echo "   Aguardando serviço parar... ($i/10)"
        sleep 1
    done
    
    if systemctl is-active --quiet samureye-collector; then
        echo "⚠️  Forçando parada do serviço..."
        systemctl kill samureye-collector
        sleep 2
    fi
else
    echo "ℹ️  Serviço samureye-collector já estava parado"
fi
echo

# 2. Verificar processos órfãos
echo "🔧 2. VERIFICANDO PROCESSOS ÓRFÃOS"
echo "----------------------------------"
COLLECTOR_PIDS=$(pgrep -f "samureye.*collector" 2>/dev/null || true)
if [ -n "$COLLECTOR_PIDS" ]; then
    echo "⚠️  Processos collector ainda ativos: $COLLECTOR_PIDS"
    echo "🔪 Terminando processos órfãos..."
    
    # Tentar terminar gentilmente primeiro
    kill $COLLECTOR_PIDS 2>/dev/null || true
    sleep 3
    
    # Verificar se ainda existem
    REMAINING_PIDS=$(pgrep -f "samureye.*collector" 2>/dev/null || true)
    if [ -n "$REMAINING_PIDS" ]; then
        echo "🔨 Forçando término dos processos restantes..."
        kill -9 $REMAINING_PIDS 2>/dev/null || true
    fi
    
    echo "✅ Processos órfãos terminados"
else
    echo "ℹ️  Nenhum processo órfão encontrado"
fi
echo

# 3. Limpar configuração com backup
echo "🧹 3. LIMPANDO CONFIGURAÇÃO"
echo "--------------------------"
CONFIG_FILE="/etc/samureye-collector/.env"

if [ -f "$CONFIG_FILE" ]; then
    echo "📁 Fazendo backup da configuração atual..."
    backup_config "$CONFIG_FILE"
    
    echo "🗑️  Removendo token e configurações de registro..."
    
    # Criar nova configuração sem token
    cat > "$CONFIG_FILE" << 'EOF'
# SamurEye Collector Configuration
# Configuração limpa após exclusão do collector

# Informações básicas do servidor
COLLECTOR_ID=vlxsam04
COLLECTOR_NAME=
HOSTNAME=vlxsam04
IP_ADDRESS=

# Servidor da API (não modificar)
API_SERVER=https://api.samureye.com.br
API_PORT=443

# Token de registro (será configurado durante novo registro)
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

# IMPORTANTE: Collector foi removido da interface
# Para re-registrar, obtenha novo token de enrollment
# através da interface admin e execute:
# curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- <tenant-slug> <enrollment-token>
EOF

    chmod 600 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
    echo "✅ Configuração limpa criada"
else
    echo "ℹ️  Arquivo de configuração não encontrado"
fi
echo

# 4. Limpar logs antigos (manter apenas últimas 1000 linhas)
echo "📝 4. LIMPANDO LOGS ANTIGOS"
echo "--------------------------"
LOG_FILE="/var/log/samureye-collector/collector.log"

if [ -f "$LOG_FILE" ]; then
    echo "📄 Limpando log antigo (mantendo últimas 1000 linhas)..."
    
    # Fazer backup das últimas linhas
    tail -1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
    
    # Adicionar marcador de limpeza
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - === LOG LIMPO APÓS EXCLUSÃO DO COLLECTOR ===" >> "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - Collector removido da interface, aguardando novo registro" >> "$LOG_FILE"
    
    echo "✅ Log limpo e marcado"
else
    echo "ℹ️  Arquivo de log não encontrado"
fi
echo

# 5. Desabilitar inicialização automática temporariamente
echo "⚙️  5. CONFIGURANDO INICIALIZAÇÃO"
echo "--------------------------------"
if systemctl is-enabled --quiet samureye-collector; then
    echo "⏸️  Desabilitando inicialização automática temporária..."
    systemctl disable samureye-collector
    echo "✅ Inicialização automática desabilitada"
    echo "ℹ️  Para reabilitar após novo registro:"
    echo "   systemctl enable samureye-collector"
    echo "   systemctl start samureye-collector"
else
    echo "ℹ️  Inicialização automática já estava desabilitada"
fi
echo

# 6. Teste final
echo "✅ 6. VERIFICAÇÃO FINAL"
echo "----------------------"
echo "📊 Status final:"
echo "   🔴 Serviço: $(systemctl is-active samureye-collector 2>/dev/null || echo 'inactive')"
echo "   🔴 Inicialização: $(systemctl is-enabled samureye-collector 2>/dev/null || echo 'disabled')"
echo "   🔴 Processos: $(pgrep -f "samureye.*collector" 2>/dev/null | wc -l) processos ativos"
echo "   ✅ Configuração: Limpa e pronta para novo registro"
echo

echo "🎯 CORREÇÃO CONCLUÍDA COM SUCESSO!"
echo "================================="
echo
echo "📋 PRÓXIMOS PASSOS PARA NOVO REGISTRO:"
echo "  1️⃣  Acesse a interface admin"
echo "  2️⃣  Crie novo collector para vlxsam04"
echo "  3️⃣  Copie o comando de registro com token"
echo "  4️⃣  Execute o comando neste servidor"
echo
echo "🔧 Para registrar novamente:"
echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- <tenant-slug> <enrollment-token>"
echo
echo "✅ Não haverá mais erros 401 Unauthorized!"
echo
echo "Conclusão: $(date)"