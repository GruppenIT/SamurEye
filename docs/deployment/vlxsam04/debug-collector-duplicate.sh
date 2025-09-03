#!/bin/bash
# Script de diagnóstico para problema de duplicação de coletores vlxsam04

echo "🔍 DIAGNÓSTICO DE DUPLICAÇÃO DE COLETORES - vlxsam04"
echo "=================================================="

# Informações do sistema
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
API_URL="https://api.samureye.com.br"

echo ""
echo "📋 INFORMAÇÕES DO SISTEMA:"
echo "   Hostname: $HOSTNAME"
echo "   IP: $IP_ADDRESS"
echo "   API: $API_URL"

echo ""
echo "🔍 VERIFICANDO COLETORES REGISTRADOS NA API:"
echo "============================================"

# Listar todos os coletores registrados
curl -s -k "$API_URL/api/admin/collectors" \
    -H "Content-Type: application/json" \
    -H "Cookie: connect.sid=admin-session" | jq '.' 2>/dev/null || echo "❌ Erro ao acessar API"

echo ""
echo "🔍 VERIFICANDO ARQUIVOS LOCAIS:"
echo "==============================="

# Verificar configurações locais
echo "📁 Diretório collector:"
ls -la /opt/samureye/collector/ 2>/dev/null || echo "❌ Diretório não encontrado"

echo ""
echo "📁 Configurações:"
ls -la /etc/samureye-collector/ 2>/dev/null || echo "❌ Configurações não encontradas"

echo ""
echo "📝 Token atual:"
if [ -f "/etc/samureye-collector/token.conf" ]; then
    cat /etc/samureye-collector/token.conf
else
    echo "❌ Token não encontrado"
fi

echo ""
echo "📝 Variáveis de ambiente:"
if [ -f "/etc/samureye-collector/.env" ]; then
    cat /etc/samureye-collector/.env
else
    echo "❌ Arquivo .env não encontrado"
fi

echo ""
echo "🔍 VERIFICANDO SERVIÇO:"
echo "======================"

echo "Status do serviço:"
systemctl status samureye-collector --no-pager

echo ""
echo "Logs recentes (últimas 20 linhas):"
journalctl -u samureye-collector -n 20 --no-pager

echo ""
echo "🔍 VERIFICANDO PROCESSOS:"
echo "========================"

echo "Processos relacionados:"
ps aux | grep -E "(samureye|collector)" | grep -v grep

echo ""
echo "🔍 VERIFICANDO REDE:"
echo "==================="

echo "Teste de conectividade API:"
if timeout 5 bash -c "</dev/tcp/api.samureye.com.br/443" >/dev/null 2>&1; then
    echo "✅ Porta 443 acessível"
else
    echo "❌ Porta 443 bloqueada"
fi

echo ""
echo "Teste de DNS:"
if nslookup api.samureye.com.br >/dev/null 2>&1; then
    echo "✅ DNS funcionando"
else
    echo "❌ DNS com problemas"
fi

echo ""
echo "🔍 ANÁLISE DO PROBLEMA:"
echo "======================"

# Contar quantos coletores existem com este hostname
COLLECTOR_COUNT=$(curl -s -k "$API_URL/api/admin/collectors" 2>/dev/null | \
    jq --arg hostname "$HOSTNAME" '[.[] | select(.hostname == $hostname)] | length' 2>/dev/null || echo "0")

if [ "$COLLECTOR_COUNT" -gt 1 ]; then
    echo "❌ PROBLEMA DETECTADO: $COLLECTOR_COUNT coletores duplicados para hostname $HOSTNAME"
    echo ""
    echo "🔧 RECOMENDAÇÕES:"
    echo "1. Executar script de limpeza de duplicatas"
    echo "2. Reregistrar collector com identificador único"
    echo "3. Verificar heartbeat automático"
elif [ "$COLLECTOR_COUNT" -eq 1 ]; then
    echo "✅ Apenas 1 collector registrado para este hostname"
    echo ""
    echo "🔧 VERIFICAR:"
    echo "1. Status do collector (deve ser ONLINE)"
    echo "2. Heartbeat funcionando"
    echo "3. Serviço ativo"
else
    echo "❌ Nenhum collector encontrado para hostname $HOSTNAME"
    echo ""
    echo "🔧 AÇÃO NECESSÁRIA:"
    echo "1. Registrar collector pela primeira vez"
fi

echo ""
echo "📊 RESUMO DO DIAGNÓSTICO CONCLUÍDO"
echo "================================="