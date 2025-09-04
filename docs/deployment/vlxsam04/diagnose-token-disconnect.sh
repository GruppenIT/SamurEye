#!/bin/bash

#==============================================================================
# DIAGNÓSTICO: Desconexão entre Registro e Serviço Collector - vlxsam04
# 
# PROBLEMA: Registro bem-sucedido mas serviço não encontra token
#          Script register-collector.sh funciona, mas serviço dá erro 401
#==============================================================================

echo "🔍 DIAGNÓSTICO: Desconexão Token Registro vs Serviço"
echo "==================================================="
echo "Data/Hora: $(date)"
echo

# 1. Status atual do serviço
echo "📊 1. STATUS DO SERVIÇO COLLECTOR"
echo "--------------------------------"
SERVICE_NAME="samureye-collector"
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✅ Serviço $SERVICE_NAME está ATIVO"
    echo "⏰ Ativo desde: $(systemctl show $SERVICE_NAME --property=ActiveEnterTimestamp --value)"
    echo "🔄 PID: $(systemctl show $SERVICE_NAME --property=MainPID --value)"
else
    echo "❌ Serviço $SERVICE_NAME está INATIVO"
fi
echo

# 2. Arquivos de configuração
echo "📁 2. ANÁLISE DOS ARQUIVOS DE CONFIGURAÇÃO"
echo "----------------------------------------"

CONFIG_FILE="/etc/samureye-collector/.env"
echo "🔍 Arquivo principal: $CONFIG_FILE"
if [ -f "$CONFIG_FILE" ]; then
    echo "✅ Arquivo encontrado"
    echo "📄 Conteúdo completo:"
    cat "$CONFIG_FILE" | sed 's/^/    /'
    echo
    
    # Verificar permissões
    echo "🔒 Permissões do arquivo:"
    ls -la "$CONFIG_FILE" | sed 's/^/    /'
    echo
    
    # Verificar tokens
    if grep -q "COLLECTOR_TOKEN" "$CONFIG_FILE"; then
        TOKEN_VALUE=$(grep "COLLECTOR_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"'"'"'')
        if [ -n "$TOKEN_VALUE" ] && [ "$TOKEN_VALUE" != "" ]; then
            echo "✅ COLLECTOR_TOKEN presente: ${TOKEN_VALUE:0:8}...${TOKEN_VALUE: -8}"
        else
            echo "❌ COLLECTOR_TOKEN está VAZIO"
        fi
    else
        echo "❌ COLLECTOR_TOKEN NÃO encontrado"
    fi
    
    if grep -q "ENROLLMENT_TOKEN" "$CONFIG_FILE"; then
        ENROLL_VALUE=$(grep "ENROLLMENT_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"'"'"'')
        if [ -n "$ENROLL_VALUE" ] && [ "$ENROLL_VALUE" != "" ]; then
            echo "✅ ENROLLMENT_TOKEN presente: ${ENROLL_VALUE:0:8}...${ENROLL_VALUE: -8}"
        else
            echo "❌ ENROLLMENT_TOKEN está VAZIO"
        fi
    else
        echo "❌ ENROLLMENT_TOKEN NÃO encontrado"
    fi
else
    echo "❌ Arquivo NÃO encontrado: $CONFIG_FILE"
fi
echo

# 3. Processo do collector - análise detalhada
echo "🔧 3. ANÁLISE DO PROCESSO COLLECTOR"
echo "----------------------------------"
COLLECTOR_PIDS=$(pgrep -f "samureye.*collector" 2>/dev/null || true)
if [ -n "$COLLECTOR_PIDS" ]; then
    echo "✅ Processos collector encontrados: $COLLECTOR_PIDS"
    
    for pid in $COLLECTOR_PIDS; do
        echo "📊 Processo PID $pid:"
        ps aux | grep "$pid" | grep -v grep | sed 's/^/    /'
        
        echo "🔍 Variáveis de ambiente do processo:"
        cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep -E "(COLLECTOR|TOKEN|API)" | sed 's/^/    /' || echo "    ❌ Não foi possível acessar environ"
        
        echo "📁 Working directory:"
        readlink /proc/$pid/cwd 2>/dev/null | sed 's/^/    /' || echo "    ❌ Não foi possível determinar"
        
        echo "🔗 Arquivos abertos relacionados a config:"
        lsof -p "$pid" 2>/dev/null | grep -E "(\.env|config)" | sed 's/^/    /' || echo "    ℹ️  Nenhum arquivo de config aberto"
        echo
    done
else
    echo "❌ Nenhum processo collector encontrado"
fi
echo

# 4. Logs detalhados do collector
echo "📝 4. ANÁLISE DETALHADA DOS LOGS"
echo "-------------------------------"
LOG_FILE="/var/log/samureye-collector/collector.log"
if [ -f "$LOG_FILE" ]; then
    echo "✅ Log encontrado: $LOG_FILE"
    
    echo "📊 Estatísticas do log:"
    echo "   📏 Total de linhas: $(wc -l < "$LOG_FILE")"
    echo "   🚨 Erros 401: $(grep -c "401.*Unauthorized" "$LOG_FILE" 2>/dev/null || echo "0")"
    echo "   🔍 Token não encontrado: $(grep -c "Token não encontrado" "$LOG_FILE" 2>/dev/null || echo "0")"
    echo "   ✅ Registros bem-sucedidos: $(grep -c "registrado com sucesso\|registration successful" "$LOG_FILE" 2>/dev/null || echo "0")"
    echo
    
    echo "📄 Últimas 15 linhas do log:"
    tail -15 "$LOG_FILE" | sed 's/^/    /'
    echo
    
    echo "🔍 Padrão de tentativas de registro (últimas 10):"
    grep -E "(Token não encontrado|registrando collector|Erro no registro)" "$LOG_FILE" | tail -10 | sed 's/^/    /'
    echo
else
    echo "❌ Log não encontrado: $LOG_FILE"
fi

# 5. Verificar outras instâncias de arquivos .env
echo "🔍 5. BUSCA POR OUTROS ARQUIVOS .env"
echo "-----------------------------------"
echo "🔍 Procurando por arquivos .env relacionados ao collector:"
find /opt /etc /var /home -name "*.env" -type f 2>/dev/null | grep -i collector | sed 's/^/    /' || echo "    ℹ️  Nenhum arquivo .env adicional encontrado"
echo

echo "🔍 Procurando por arquivos de configuração do SamurEye:"
find /opt /etc /var -name "*samureye*" -type f 2>/dev/null | grep -E "\.(env|conf|config|cfg)$" | sed 's/^/    /' || echo "    ℹ️  Nenhum arquivo de config adicional encontrado"
echo

# 6. Teste de conectividade e API
echo "🌐 6. TESTE DE CONECTIVIDADE DETALHADO"
echo "------------------------------------"
API_BASE="https://api.samureye.com.br"

echo "🔗 Testando conectividade básica:"
if curl -s --connect-timeout 5 --max-time 10 "$API_BASE/health" >/dev/null 2>&1; then
    echo "✅ Conectividade básica: OK"
else
    echo "❌ Conectividade básica: FALHOU"
fi

echo "🔍 Testando endpoint de heartbeat:"
HEARTBEAT_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/heartbeat_test.json \
    --connect-timeout 5 --max-time 10 \
    -X POST "$API_BASE/collector-api/heartbeat" \
    -H "Content-Type: application/json" \
    -d '{"collector_id":"test","status":"test"}' 2>/dev/null)

if [ -n "$HEARTBEAT_RESPONSE" ]; then
    echo "📊 HTTP Status heartbeat: $HEARTBEAT_RESPONSE"
    if [ -f "/tmp/heartbeat_test.json" ]; then
        echo "📄 Resposta heartbeat:"
        cat /tmp/heartbeat_test.json | sed 's/^/    /'
        rm -f /tmp/heartbeat_test.json
    fi
else
    echo "❌ Teste de heartbeat falhou"
fi
echo

# 7. Diagnóstico específico do problema
echo "🎯 7. DIAGNÓSTICO ESPECÍFICO DO PROBLEMA"
echo "---------------------------------------"
echo "SITUAÇÃO ATUAL:"
echo "  ✅ Script register-collector.sh executado com sucesso"
echo "  ✅ Registro reportado como bem-sucedido pela API"
echo "  ❌ Serviço collector reporta 'Token não encontrado'"
echo "  ❌ Serviço gera erro 401 Unauthorized"
echo

echo "POSSÍVEIS CAUSAS:"
echo "  1️⃣  Token salvo em local diferente do que o serviço lê"
echo "  2️⃣  Permissões incorretas impedem leitura do token"
echo "  3️⃣  Serviço iniciado antes do token ser salvo"
echo "  4️⃣  Duas instâncias diferentes de configuração"
echo "  5️⃣  Formato incorreto do token no arquivo"
echo "  6️⃣  Cache ou buffer de arquivo não sincronizado"
echo

echo "INVESTIGAÇÃO NECESSÁRIA:"
if [ -f "$CONFIG_FILE" ] && grep -q "COLLECTOR_TOKEN" "$CONFIG_FILE"; then
    TOKEN_VALUE=$(grep "COLLECTOR_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"'"'"'')
    if [ -n "$TOKEN_VALUE" ] && [ "$TOKEN_VALUE" != "" ]; then
        echo "  ➤ Token presente no arquivo, mas serviço não encontra"
        echo "  ➤ SUSPEITA: Problema de sincronização ou leitura"
        echo "  ➤ AÇÃO: Reiniciar serviço para recarregar configuração"
    else
        echo "  ➤ Token vazio no arquivo de configuração"
        echo "  ➤ SUSPEITA: Script de registro não salvou corretamente"
        echo "  ➤ AÇÃO: Executar novo registro e verificar salvamento"
    fi
else
    echo "  ➤ Arquivo de configuração ausente ou sem token"
    echo "  ➤ SUSPEITA: Script de registro falhou silenciosamente"
    echo "  ➤ AÇÃO: Executar novo registro com debug ativado"
fi
echo

echo "🔧 CORREÇÃO RECOMENDADA:"
echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/fix-token-disconnect.sh | bash"
echo

echo "✅ Diagnóstico concluído: $(date)"