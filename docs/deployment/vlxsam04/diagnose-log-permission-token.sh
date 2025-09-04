#!/bin/bash

# Script de diagnóstico para problema de permissão de log e token não salvo
# vlxsam04 - SamurEye Collector

echo "🔍 DIAGNÓSTICO: Permissões Log + Token Não Salvo"
echo "================================================"

HOSTNAME=$(hostname)
CONFIG_FILE="/etc/samureye-collector/.env"
LOG_DIR="/var/log/samureye-collector"
LOG_FILE="$LOG_DIR/heartbeat.log"
SERVICE_NAME="samureye-collector"
COLLECTOR_USER="samureye-collector"

echo "📋 Sistema: $HOSTNAME"
echo ""

echo "🔍 1. VERIFICANDO PROBLEMA DE PERMISSÃO NO LOG:"
echo "================================================"

echo "📁 Diretório de logs: $LOG_DIR"
if [ -d "$LOG_DIR" ]; then
    echo "✅ Diretório existe"
    echo "   Dono: $(ls -ld $LOG_DIR | awk '{print $3":"$4}')"
    echo "   Permissões: $(ls -ld $LOG_DIR | awk '{print $1}')"
else
    echo "❌ Diretório não existe"
fi

echo ""
echo "📄 Arquivo de log: $LOG_FILE"
if [ -f "$LOG_FILE" ]; then
    echo "✅ Arquivo existe"
    echo "   Dono: $(ls -l $LOG_FILE | awk '{print $3":"$4}')"
    echo "   Permissões: $(ls -l $LOG_FILE | awk '{print $1}')"
else
    echo "❌ Arquivo não existe"
fi

echo ""
echo "👤 Usuário do serviço: $COLLECTOR_USER"
if id "$COLLECTOR_USER" &>/dev/null; then
    echo "✅ Usuário existe"
    echo "   UID/GID: $(id $COLLECTOR_USER)"
    echo "   Grupos: $(groups $COLLECTOR_USER)"
else
    echo "❌ Usuário não existe"
fi

echo ""
echo "🧪 Teste de escrita no diretório:"
if sudo -u "$COLLECTOR_USER" touch "$LOG_DIR/test_write" 2>/dev/null; then
    echo "✅ Usuário pode escrever no diretório"
    rm -f "$LOG_DIR/test_write"
else
    echo "❌ Usuário NÃO pode escrever no diretório"
    echo "   Erro: $(sudo -u "$COLLECTOR_USER" touch "$LOG_DIR/test_write" 2>&1)"
fi

echo ""
echo "🔍 2. VERIFICANDO PROBLEMA TOKEN NÃO SALVO:"
echo "==========================================="

echo "📄 Arquivo de configuração: $CONFIG_FILE"
if [ -f "$CONFIG_FILE" ]; then
    echo "✅ Arquivo existe"
    echo "   Dono: $(ls -l $CONFIG_FILE | awk '{print $3":"$4}')"
    echo "   Permissões: $(ls -l $CONFIG_FILE | awk '{print $1}')"
    
    echo ""
    echo "🔑 Tokens configurados:"
    if grep -q "COLLECTOR_TOKEN=" "$CONFIG_FILE"; then
        TOKEN_VALUE=$(grep "COLLECTOR_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2)
        if [ -n "$TOKEN_VALUE" ]; then
            echo "✅ COLLECTOR_TOKEN: ${TOKEN_VALUE:0:8}...${TOKEN_VALUE: -8}"
        else
            echo "❌ COLLECTOR_TOKEN: VAZIO"
        fi
    else
        echo "❌ COLLECTOR_TOKEN: NÃO CONFIGURADO"
    fi
    
    if grep -q "ENROLLMENT_TOKEN=" "$CONFIG_FILE"; then
        ENROLL_VALUE=$(grep "ENROLLMENT_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2)
        if [ -n "$ENROLL_VALUE" ]; then
            echo "✅ ENROLLMENT_TOKEN: ${ENROLL_VALUE:0:8}...${ENROLL_VALUE: -8}"
        else
            echo "❌ ENROLLMENT_TOKEN: VAZIO"
        fi
    else
        echo "❌ ENROLLMENT_TOKEN: NÃO CONFIGURADO"
    fi
else
    echo "❌ Arquivo não existe"
fi

echo ""
echo "🔍 3. VERIFICANDO STATUS DO SERVIÇO:"
echo "===================================="

echo "🤖 Status systemd:"
systemctl status "$SERVICE_NAME" --no-pager -l | head -10

echo ""
echo "📝 Últimos logs do systemd:"
journalctl -u "$SERVICE_NAME" --no-pager -n 10 | tail -10

echo ""
echo "🔍 4. VERIFICANDO SCRIPT REGISTER-COLLECTOR:"
echo "============================================"

REGISTER_SCRIPT="/opt/samureye/collector/scripts/register-collector.sh"
if [ -f "$REGISTER_SCRIPT" ]; then
    echo "✅ Script de registro existe"
    
    echo ""
    echo "🔍 Verificando função de salvamento de token:"
    if grep -q "save_token_to_file" "$REGISTER_SCRIPT"; then
        echo "✅ Função save_token_to_file encontrada"
    else
        echo "❌ Função save_token_to_file NÃO encontrada"
    fi
    
    if grep -q "COLLECTOR_TOKEN=" "$REGISTER_SCRIPT"; then
        echo "✅ Lógica de salvamento COLLECTOR_TOKEN encontrada"
    else
        echo "❌ Lógica de salvamento COLLECTOR_TOKEN NÃO encontrada"
    fi
else
    echo "❌ Script de registro não existe"
fi

echo ""
echo "🔍 5. ANÁLISE DO PROBLEMA:"
echo "=========================="

echo ""
echo "❌ PROBLEMAS DETECTADOS:"

# Verificar problema de permissão
if ! sudo -u "$COLLECTOR_USER" touch "$LOG_DIR/test_write" 2>/dev/null; then
    echo "   🔴 CRÍTICO: Usuário $COLLECTOR_USER não pode escrever em $LOG_DIR"
    echo "      Isso impede o heartbeat.py de criar/escrever logs"
fi

# Verificar token vazio
if [ -f "$CONFIG_FILE" ]; then
    TOKEN_VALUE=$(grep "COLLECTOR_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2)
    if [ -z "$TOKEN_VALUE" ]; then
        echo "   🔴 CRÍTICO: COLLECTOR_TOKEN está vazio no arquivo .env"
        echo "      Collector não pode autenticar na API"
    fi
else
    echo "   🔴 CRÍTICO: Arquivo de configuração não existe"
fi

echo ""
echo "🛠️ SOLUÇÕES RECOMENDADAS:"
echo "   1. Corrigir permissões do diretório de logs"
echo "   2. Verificar salvamento de token no register-collector.sh"
echo "   3. Executar script de correção específico"

echo ""
echo "🔧 COMANDOS DE CORREÇÃO:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/fix-log-permission-token.sh | bash"