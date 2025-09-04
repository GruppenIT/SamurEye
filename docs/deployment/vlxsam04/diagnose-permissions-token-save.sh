#!/bin/bash

#==============================================================================
# DIAGNÓSTICO: Permissões e Salvamento de Token - vlxsam04
# 
# PROBLEMA: Script de registro reporta sucesso mas não salva token +
#          Serviço não consegue ler arquivo por problemas de permissão
#==============================================================================

echo "🔍 DIAGNÓSTICO: Permissões e Salvamento de Token"
echo "==============================================="
echo "Data/Hora: $(date)"
echo

# Configurações
CONFIG_FILE="/etc/samureye-collector/.env"
CONFIG_DIR="/etc/samureye-collector"
COLLECTOR_USER="samureye-collector"
SERVICE_NAME="samureye-collector"
LOG_FILE="/var/log/samureye-collector/collector.log"

# 1. Análise do usuário do serviço
echo "👤 1. ANÁLISE DO USUÁRIO DO SERVIÇO"
echo "-----------------------------------"

if id "$COLLECTOR_USER" &>/dev/null; then
    echo "✅ Usuário $COLLECTOR_USER existe"
    echo "📊 Detalhes do usuário:"
    id "$COLLECTOR_USER" | sed 's/^/    /'
    echo "🏠 Home directory:"
    eval echo "~$COLLECTOR_USER" | sed 's/^/    /'
    echo "🐚 Shell:"
    getent passwd "$COLLECTOR_USER" | cut -d: -f7 | sed 's/^/    /'
else
    echo "❌ Usuário $COLLECTOR_USER NÃO existe"
    echo "⚠️  PROBLEMA CRÍTICO: Serviço não pode executar sem usuário"
fi
echo

# 2. Análise do arquivo de serviço systemd
echo "🔧 2. ANÁLISE DO ARQUIVO DE SERVIÇO SYSTEMD"
echo "------------------------------------------"

SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
if [ -f "$SERVICE_FILE" ]; then
    echo "✅ Arquivo de serviço encontrado: $SERVICE_FILE"
    echo "📄 Conteúdo do arquivo de serviço:"
    cat "$SERVICE_FILE" | sed 's/^/    /'
    echo
    
    # Verificar User= na configuração
    if grep -q "^User=" "$SERVICE_FILE"; then
        SERVICE_USER=$(grep "^User=" "$SERVICE_FILE" | cut -d'=' -f2)
        echo "👤 Usuário configurado no serviço: $SERVICE_USER"
        
        if [ "$SERVICE_USER" = "$COLLECTOR_USER" ]; then
            echo "✅ Usuário do serviço está correto"
        else
            echo "❌ Usuário do serviço ($SERVICE_USER) diferente do esperado ($COLLECTOR_USER)"
        fi
    else
        echo "⚠️  Nenhum usuário específico configurado (executará como root)"
    fi
else
    echo "❌ Arquivo de serviço NÃO encontrado: $SERVICE_FILE"
fi
echo

# 3. Análise detalhada de permissões
echo "🔒 3. ANÁLISE DETALHADA DE PERMISSÕES"
echo "------------------------------------"

echo "📁 Diretório de configuração: $CONFIG_DIR"
if [ -d "$CONFIG_DIR" ]; then
    echo "✅ Diretório existe"
    echo "🔒 Permissões do diretório:"
    ls -la "$CONFIG_DIR" | head -1 | sed 's/^/    /'
    ls -la "$(dirname "$CONFIG_DIR")" | grep "$(basename "$CONFIG_DIR")" | sed 's/^/    /'
    
    echo "📄 Conteúdo do diretório:"
    ls -la "$CONFIG_DIR" | sed 's/^/    /'
else
    echo "❌ Diretório NÃO existe: $CONFIG_DIR"
fi
echo

echo "📄 Arquivo de configuração: $CONFIG_FILE"
if [ -f "$CONFIG_FILE" ]; then
    echo "✅ Arquivo existe"
    echo "🔒 Permissões detalhadas:"
    ls -la "$CONFIG_FILE" | sed 's/^/    /'
    
    # Verificar se o usuário do serviço pode ler
    if [ -n "$SERVICE_USER" ] && [ "$SERVICE_USER" != "root" ]; then
        echo "🔍 Testando acesso de leitura pelo usuário $SERVICE_USER:"
        if sudo -u "$SERVICE_USER" test -r "$CONFIG_FILE" 2>/dev/null; then
            echo "✅ Usuário $SERVICE_USER PODE ler o arquivo"
        else
            echo "❌ Usuário $SERVICE_USER NÃO PODE ler o arquivo"
            echo "⚠️  PROBLEMA CRÍTICO: Causa do erro Permission denied"
        fi
    fi
    
    echo "📊 Tamanho do arquivo: $(stat -c%s "$CONFIG_FILE") bytes"
    echo "⏰ Última modificação: $(stat -c%y "$CONFIG_FILE")"
else
    echo "❌ Arquivo NÃO existe: $CONFIG_FILE"
fi
echo

# 4. Análise dos logs de permissão
echo "📝 4. ANÁLISE DOS LOGS DE PERMISSÃO"
echo "----------------------------------"

if [ -f "$LOG_FILE" ]; then
    echo "✅ Log encontrado: $LOG_FILE"
    
    # Contar erros de permissão
    PERMISSION_ERRORS=$(grep -c "Permission denied" "$LOG_FILE" 2>/dev/null || echo "0")
    echo "🚨 Total de erros Permission denied: $PERMISSION_ERRORS"
    
    if [ "$PERMISSION_ERRORS" -gt 0 ]; then
        echo "📄 Últimos erros de permissão:"
        grep "Permission denied" "$LOG_FILE" | tail -5 | sed 's/^/    /'
        echo
        
        echo "⏰ Timeframe dos erros de permissão:"
        FIRST_ERROR=$(grep "Permission denied" "$LOG_FILE" | head -1 | cut -d' ' -f1-2)
        LAST_ERROR=$(grep "Permission denied" "$LOG_FILE" | tail -1 | cut -d' ' -f1-2)
        echo "   Primeiro erro: $FIRST_ERROR"
        echo "   Último erro: $LAST_ERROR"
    fi
else
    echo "❌ Log não encontrado: $LOG_FILE"
fi
echo

# 5. Teste de criação e escrita no arquivo
echo "🧪 5. TESTE DE CRIAÇÃO E ESCRITA"
echo "-------------------------------"

echo "🔍 Testando criação de arquivo de teste como root..."
TEST_FILE="/tmp/samureye-test-config.env"
echo "TESTE=123" > "$TEST_FILE"
if [ -f "$TEST_FILE" ]; then
    echo "✅ Root consegue criar arquivos"
    rm -f "$TEST_FILE"
else
    echo "❌ Root não consegue criar arquivos (problema no filesystem)"
fi

echo "🔍 Testando escrita no arquivo de configuração como root..."
if echo "# Teste de escrita $(date)" >> "$CONFIG_FILE" 2>/dev/null; then
    echo "✅ Root consegue escrever no arquivo de configuração"
    # Remover linha de teste
    sed -i '/# Teste de escrita/d' "$CONFIG_FILE" 2>/dev/null
else
    echo "❌ Root não consegue escrever no arquivo de configuração"
fi

# Testar como usuário do serviço
if [ -n "$SERVICE_USER" ] && [ "$SERVICE_USER" != "root" ] && id "$SERVICE_USER" &>/dev/null; then
    echo "🔍 Testando leitura como usuário $SERVICE_USER..."
    if sudo -u "$SERVICE_USER" cat "$CONFIG_FILE" >/dev/null 2>&1; then
        echo "✅ Usuário $SERVICE_USER consegue ler o arquivo"
    else
        echo "❌ Usuário $SERVICE_USER NÃO consegue ler o arquivo"
        echo "⚠️  Este é o motivo do erro Permission denied"
    fi
fi
echo

# 6. Análise do processo de salvamento do token
echo "💾 6. ANÁLISE DO PROCESSO DE SALVAMENTO"
echo "--------------------------------------"

echo "🔍 Verificando se o arquivo tem conteúdo de token..."
if [ -f "$CONFIG_FILE" ]; then
    # Procurar por linhas de token
    COLLECTOR_TOKEN_LINE=$(grep "^COLLECTOR_TOKEN=" "$CONFIG_FILE" || true)
    ENROLLMENT_TOKEN_LINE=$(grep "^ENROLLMENT_TOKEN=" "$CONFIG_FILE" || true)
    
    echo "📄 Linhas de token no arquivo:"
    echo "   COLLECTOR_TOKEN: $COLLECTOR_TOKEN_LINE"
    echo "   ENROLLMENT_TOKEN: $ENROLLMENT_TOKEN_LINE"
    
    # Verificar se estão vazios
    if echo "$COLLECTOR_TOKEN_LINE" | grep -q "COLLECTOR_TOKEN=$" || echo "$COLLECTOR_TOKEN_LINE" | grep -q 'COLLECTOR_TOKEN=""' || echo "$COLLECTOR_TOKEN_LINE" | grep -q "COLLECTOR_TOKEN=''"; then
        echo "❌ COLLECTOR_TOKEN está VAZIO"
    elif [ -z "$COLLECTOR_TOKEN_LINE" ]; then
        echo "❌ COLLECTOR_TOKEN NÃO ENCONTRADO"
    else
        echo "✅ COLLECTOR_TOKEN tem valor"
    fi
    
    if echo "$ENROLLMENT_TOKEN_LINE" | grep -q "ENROLLMENT_TOKEN=$" || echo "$ENROLLMENT_TOKEN_LINE" | grep -q 'ENROLLMENT_TOKEN=""' || echo "$ENROLLMENT_TOKEN_LINE" | grep -q "ENROLLMENT_TOKEN=''"; then
        echo "❌ ENROLLMENT_TOKEN está VAZIO"
    elif [ -z "$ENROLLMENT_TOKEN_LINE" ]; then
        echo "❌ ENROLLMENT_TOKEN NÃO ENCONTRADO"
    else
        echo "✅ ENROLLMENT_TOKEN tem valor"
    fi
fi
echo

# 7. Análise do script de registro
echo "📜 7. ANÁLISE DO SCRIPT DE REGISTRO"
echo "----------------------------------"

REGISTER_SCRIPT="/opt/samureye/collector/scripts/register-collector.sh"
if [ -f "$REGISTER_SCRIPT" ]; then
    echo "✅ Script de registro local encontrado: $REGISTER_SCRIPT"
    
    echo "🔍 Verificando se o script local salva tokens..."
    if grep -q "COLLECTOR_TOKEN" "$REGISTER_SCRIPT"; then
        echo "✅ Script menciona COLLECTOR_TOKEN"
    else
        echo "❌ Script NÃO menciona COLLECTOR_TOKEN"
    fi
    
    # Verificar o que o script faz com o arquivo de configuração
    echo "🔍 Verificando operações no arquivo de configuração:"
    grep -n "$CONFIG_FILE\|\.env" "$REGISTER_SCRIPT" 2>/dev/null | sed 's/^/    /' || echo "    ❌ Nenhuma referência ao arquivo de configuração encontrada"
else
    echo "⚠️  Script de registro local não encontrado"
    echo "ℹ️  Provavelmente está sendo executado via curl direto do GitHub"
fi
echo

# 8. Diagnóstico final
echo "🎯 8. DIAGNÓSTICO FINAL"
echo "----------------------"

echo "PROBLEMAS IDENTIFICADOS:"

# Problema 1: Usuário do serviço
if [ -z "$SERVICE_USER" ] || [ "$SERVICE_USER" = "root" ]; then
    echo "  1️⃣  ✅ Serviço roda como root (sem problema de permissão)"
elif ! id "$SERVICE_USER" &>/dev/null; then
    echo "  1️⃣  ❌ Usuário do serviço ($SERVICE_USER) não existe"
elif ! sudo -u "$SERVICE_USER" test -r "$CONFIG_FILE" 2>/dev/null; then
    echo "  1️⃣  ❌ Usuário do serviço não pode ler arquivo de configuração"
else
    echo "  1️⃣  ✅ Permissões de usuário estão corretas"
fi

# Problema 2: Token vazio
if [ -f "$CONFIG_FILE" ]; then
    if grep -q "^COLLECTOR_TOKEN=$\|^COLLECTOR_TOKEN=\"\"\|^COLLECTOR_TOKEN=''" "$CONFIG_FILE"; then
        echo "  2️⃣  ❌ Token está vazio no arquivo (script de registro falhou)"
    else
        echo "  2️⃣  ✅ Token está presente no arquivo"
    fi
else
    echo "  2️⃣  ❌ Arquivo de configuração não existe"
fi

# Problema 3: Logs de erro
if [ "$PERMISSION_ERRORS" -gt 0 ]; then
    echo "  3️⃣  ❌ Erros de permissão detectados nos logs ($PERMISSION_ERRORS erros)"
else
    echo "  3️⃣  ✅ Nenhum erro de permissão nos logs"
fi

echo
echo "CAUSA RAIZ PROVÁVEL:"
if [ "$PERMISSION_ERRORS" -gt 0 ] && grep -q "^COLLECTOR_TOKEN=$\|^COLLECTOR_TOKEN=\"\"\|^COLLECTOR_TOKEN=''" "$CONFIG_FILE" 2>/dev/null; then
    echo "  ➤ Script de registro não salva token + problema de permissões"
    echo "  ➤ DUPLO PROBLEMA: Salvamento falho + Acesso negado"
elif [ "$PERMISSION_ERRORS" -gt 0 ]; then
    echo "  ➤ Problema de permissões impedindo leitura do arquivo"
    echo "  ➤ FOCO: Corrigir permissões do arquivo/usuário"
elif grep -q "^COLLECTOR_TOKEN=$\|^COLLECTOR_TOKEN=\"\"\|^COLLECTOR_TOKEN=''" "$CONFIG_FILE" 2>/dev/null; then
    echo "  ➤ Script de registro reporta sucesso mas não salva token"
    echo "  ➤ FOCO: Corrigir processo de salvamento do token"
else
    echo "  ➤ Problema não identificado claramente"
fi

echo
echo "🔧 CORREÇÃO RECOMENDADA:"
echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/fix-permissions-token-save.sh | bash"
echo

echo "✅ Diagnóstico concluído: $(date)"