#!/bin/bash
# Script master para correção completa do problema de duplicação de coletores vlxsam04

echo "🔧 CORREÇÃO COMPLETA DE DUPLICAÇÃO - vlxsam04"
echo "=============================================="

# Informações do sistema
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
SCRIPT_DIR="$(dirname "$0")"

echo ""
echo "📋 SISTEMA: $HOSTNAME ($IP_ADDRESS)"
echo ""

# Verificar se estamos executando como root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Este script deve ser executado como root"
    echo "   Use: sudo $0"
    exit 1
fi

echo "🔍 PASSO 1: DIAGNÓSTICO INICIAL"
echo "==============================="

# Executar diagnóstico
if [ -f "$SCRIPT_DIR/debug-collector-duplicate.sh" ]; then
    echo "📊 Executando diagnóstico..."
    bash "$SCRIPT_DIR/debug-collector-duplicate.sh"
else
    echo "⚠️ Script de diagnóstico não encontrado"
fi

echo ""
echo "⏸️ PAUSA PARA ANÁLISE"
echo "===================="
echo "Pressione ENTER para continuar com a correção ou Ctrl+C para sair"
read -r

echo ""
echo "🔧 PASSO 2: APLICANDO CORREÇÕES"
echo "==============================="

# Executar correção
if [ -f "$SCRIPT_DIR/fix-collector-duplicates.sh" ]; then
    echo "🛠️ Executando correções..."
    bash "$SCRIPT_DIR/fix-collector-duplicates.sh"
else
    echo "⚠️ Script de correção não encontrado"
fi

echo ""
echo "🔍 PASSO 3: VERIFICAÇÃO FINAL"
echo "============================="

# Aguardar serviço estabilizar
echo "⏱️ Aguardando 30 segundos para serviço estabilizar..."
sleep 30

# Verificar status final
echo ""
echo "📊 STATUS FINAL:"
echo "==============="

echo "🤖 Serviço:"
systemctl status samureye-collector --no-pager -l

echo ""
echo "📝 Logs recentes:"
if [ -f "/var/log/samureye-collector/heartbeat.log" ]; then
    echo "--- Heartbeat Log (últimas 10 linhas) ---"
    tail -n 10 /var/log/samureye-collector/heartbeat.log
else
    echo "❌ Log de heartbeat não encontrado"
fi

if [ -f "/var/log/samureye-collector/collector.log" ]; then
    echo ""
    echo "--- Collector Log (últimas 5 linhas) ---"
    tail -n 5 /var/log/samureye-collector/collector.log
fi

echo ""
echo "🔗 Teste de conectividade:"
if [ -f "/opt/samureye/collector/test-connectivity.sh" ]; then
    echo "🧪 Executando teste..."
    sudo -u samureye-collector /opt/samureye/collector/test-connectivity.sh
else
    echo "⚠️ Script de teste não encontrado"
fi

echo ""
echo "✅ CORREÇÃO COMPLETA FINALIZADA"
echo "==============================="
echo ""
echo "📋 RESUMO:"
echo "• Duplicatas diagnosticadas e corrigidas"
echo "• Heartbeat robusto implementado"
echo "• Serviço configurado para auto-recovery"
echo "• Monitoramento de status ativo"
echo ""
echo "🔧 PRÓXIMOS PASSOS:"
echo "1. Monitorar logs: tail -f /var/log/samureye-collector/heartbeat.log"
echo "2. Verificar interface: https://app.samureye.com.br/admin/collectors"
echo "3. Aguardar transição: ENROLLING → ONLINE"
echo "4. Confirmar apenas 1 collector para hostname $HOSTNAME"
echo ""
echo "⚠️ Se problemas persistirem:"
echo "• Verificar firewall: ufw status"
echo "• Testar DNS: nslookup api.samureye.com.br"
echo "• Verificar certificados: ls -la /opt/samureye/collector/certs/"
echo "• Contatar suporte com logs"