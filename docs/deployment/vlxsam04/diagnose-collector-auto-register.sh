#!/bin/bash

#==============================================================================
# DIAGNÓSTICO: Auto-registro do Collector após Exclusão - vlxsam04
# 
# PROBLEMA: Collector continua tentando se registrar automaticamente após 
#          exclusão da interface, causando erros 401 Unauthorized
#==============================================================================

echo "🔍 DIAGNÓSTICO: Auto-registro Collector vlxsam04"
echo "==============================================="
echo "Data/Hora: $(date)"
echo

# 1. Status do serviço collector
echo "📊 1. STATUS DO SERVIÇO COLLECTOR"
echo "--------------------------------"
if systemctl is-active --quiet samureye-collector; then
    echo "✅ Serviço samureye-collector está ATIVO"
    echo "⚠️  Status: $(systemctl is-active samureye-collector)"
    echo "⚠️  Desde: $(systemctl show samureye-collector --property=ActiveEnterTimestamp --value)"
else
    echo "❌ Serviço samureye-collector está INATIVO"
fi
echo

# 2. Configuração do collector
echo "📁 2. CONFIGURAÇÃO DO COLLECTOR"
echo "------------------------------"
CONFIG_FILE="/etc/samureye-collector/.env"
if [ -f "$CONFIG_FILE" ]; then
    echo "✅ Arquivo de configuração encontrado: $CONFIG_FILE"
    echo "📄 Conteúdo (sem senhas):"
    cat "$CONFIG_FILE" | grep -v -E "(TOKEN|PASSWORD|SECRET)" | sed 's/^/    /'
    echo
    
    # Verificar se tem token
    if grep -q "COLLECTOR_TOKEN" "$CONFIG_FILE"; then
        echo "🔑 COLLECTOR_TOKEN presente no arquivo"
        TOKEN_VALUE=$(grep "COLLECTOR_TOKEN=" "$CONFIG_FILE" | cut -d'=' -f2)
        if [ -z "$TOKEN_VALUE" ] || [ "$TOKEN_VALUE" = '""' ] || [ "$TOKEN_VALUE" = "''" ]; then
            echo "⚠️  Mas token está VAZIO"
        else
            echo "✅ Token configurado (mascarado): ${TOKEN_VALUE:0:8}..."
        fi
    else
        echo "❌ COLLECTOR_TOKEN NÃO encontrado no arquivo"
    fi
else
    echo "❌ Arquivo de configuração NÃO encontrado: $CONFIG_FILE"
fi
echo

# 3. Logs recentes do collector
echo "📝 3. LOGS RECENTES DO COLLECTOR"
echo "-------------------------------"
LOG_FILE="/var/log/samureye-collector/collector.log"
if [ -f "$LOG_FILE" ]; then
    echo "✅ Log file encontrado: $LOG_FILE"
    echo "📄 Últimas 10 linhas:"
    tail -10 "$LOG_FILE" | sed 's/^/    /'
    echo
    
    # Contagem de erros 401
    ERROR_401_COUNT=$(grep -c "401.*Unauthorized" "$LOG_FILE" 2>/dev/null || echo "0")
    echo "🚨 Total de erros 401 Unauthorized no log: $ERROR_401_COUNT"
    
    # Últimas tentativas de registro
    echo "🔄 Últimas tentativas de registro:"
    grep "registrando collector\|Erro no registro" "$LOG_FILE" | tail -5 | sed 's/^/    /'
else
    echo "❌ Log file NÃO encontrado: $LOG_FILE"
fi
echo

# 4. Processo do collector
echo "🔧 4. PROCESSO DO COLLECTOR"
echo "--------------------------"
COLLECTOR_PID=$(pgrep -f "samureye.*collector" 2>/dev/null)
if [ -n "$COLLECTOR_PID" ]; then
    echo "✅ Processo collector encontrado: PID $COLLECTOR_PID"
    echo "📊 Detalhes do processo:"
    ps aux | grep "$COLLECTOR_PID" | grep -v grep | sed 's/^/    /'
    echo
    echo "🔗 Conexões de rede do processo:"
    netstat -tulpn 2>/dev/null | grep "$COLLECTOR_PID" | sed 's/^/    /'
else
    echo "❌ Processo collector NÃO encontrado"
fi
echo

# 5. Teste de conectividade com API
echo "🌐 5. TESTE DE CONECTIVIDADE"
echo "---------------------------"
API_URL="https://api.samureye.com.br"
echo "🔗 Testando conectividade com: $API_URL"

# Test básico de conectividade
if curl -s --connect-timeout 5 --max-time 10 "$API_URL/health" >/dev/null 2>&1; then
    echo "✅ Conectividade com API: OK"
else
    echo "❌ Conectividade com API: FALHOU"
fi

# Test da rota de registro (sem dados)
echo "🔍 Testando rota de registro do collector:"
REGISTER_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/register_test.json \
    --connect-timeout 5 --max-time 10 \
    -X POST "$API_URL/collector-api/register" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null)

if [ -n "$REGISTER_RESPONSE" ]; then
    echo "📊 HTTP Status da rota register: $REGISTER_RESPONSE"
    if [ -f "/tmp/register_test.json" ]; then
        echo "📄 Resposta:"
        cat /tmp/register_test.json | sed 's/^/    /'
        rm -f /tmp/register_test.json
    fi
else
    echo "❌ Não foi possível testar rota de registro"
fi
echo

# 6. Diagnóstico da causa
echo "🎯 6. DIAGNÓSTICO DA CAUSA"
echo "-------------------------"
echo "PROBLEMA IDENTIFICADO:"
echo "  ➤ Collector foi excluído da interface/banco de dados"
echo "  ➤ Mas serviço ainda está rodando no servidor"
echo "  ➤ Tentando auto-registro sem token válido"
echo "  ➤ Resultando em erro 401 Unauthorized"
echo
echo "SOLUÇÕES RECOMENDADAS:"
echo "  1️⃣  Parar o serviço do collector"
echo "  2️⃣  Limpar configurações antigas"
echo "  3️⃣  Aguardar novo registro manual"
echo "  4️⃣  Ou executar hard reset completo"
echo

echo "🔧 Para corrigir, execute:"
echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/fix-collector-after-deletion.sh | bash"
echo

echo "✅ Diagnóstico concluído: $(date)"