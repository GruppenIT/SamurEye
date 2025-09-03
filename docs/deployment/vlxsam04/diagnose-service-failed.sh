#!/bin/bash
# Script de diagnóstico para vlxsam04 - Service Failed

echo "🔍 DIAGNÓSTICO DETALHADO - vlxsam04 Service Failed"
echo "================================================="

HOSTNAME=$(hostname)
echo "📋 Sistema: $HOSTNAME"
echo "📅 Data: $(date)"
echo ""

echo "🤖 STATUS SYSTEMD DETALHADO:"
echo "=============================="
systemctl status samureye-collector --no-pager -l
echo ""

echo "📝 LOGS SYSTEMD (últimas 50 linhas):"
echo "===================================="
journalctl -u samureye-collector --no-pager -n 50
echo ""

echo "📁 ESTRUTURA DE ARQUIVOS:"
echo "========================="
echo "🔍 Diretório principal:"
ls -la /opt/samureye/collector/ 2>/dev/null || echo "❌ Diretório não existe"
echo ""

echo "🔍 Script heartbeat:"
if [ -f "/opt/samureye/collector/heartbeat.py" ]; then
    echo "✅ heartbeat.py existe"
    ls -la /opt/samureye/collector/heartbeat.py
    echo "📋 Permissões do usuário:"
    id samureye-collector 2>/dev/null || echo "❌ Usuário samureye-collector não existe"
else
    echo "❌ heartbeat.py não encontrado"
fi
echo ""

echo "🔍 Configuração:"
if [ -f "/etc/samureye-collector/.env" ]; then
    echo "✅ .env existe:"
    cat /etc/samureye-collector/.env
else
    echo "❌ .env não existe"
fi
echo ""

echo "🔍 Token:"
if [ -f "/etc/samureye-collector/token.conf" ]; then
    echo "✅ token.conf existe"
    ls -la /etc/samureye-collector/token.conf
else
    echo "❌ token.conf não existe"
fi
echo ""

echo "🐍 TESTE PYTHON:"
echo "================"
echo "📋 Versão Python:"
python3 --version
python3.11 --version 2>/dev/null || echo "❌ Python 3.11 não disponível"

echo ""
echo "📋 Teste importações:"
python3 -c "
try:
    import os, sys, json, time, socket, requests, logging, psutil
    from pathlib import Path
    print('✅ Todas importações OK')
except ImportError as e:
    print(f'❌ Erro importação: {e}')
"

echo ""
echo "📋 Teste execução heartbeat:"
if [ -f "/opt/samureye/collector/heartbeat.py" ]; then
    echo "🧪 Testando execução (timeout 10s):"
    timeout 10s sudo -u samureye-collector python3 /opt/samureye/collector/heartbeat.py 2>&1 || echo "❌ Falha na execução"
else
    echo "❌ Arquivo heartbeat.py não encontrado"
fi
echo ""

echo "🛡️ FERRAMENTAS DE SEGURANÇA:"
echo "============================"
echo "📋 Nmap:"
if command -v nmap >/dev/null 2>&1; then
    echo "✅ nmap instalado: $(nmap --version | head -1)"
else
    echo "❌ nmap não encontrado"
    echo "🔍 Tentativa instalação:"
    apt-cache policy nmap
fi

echo ""
echo "📋 Nuclei:"
if command -v nuclei >/dev/null 2>&1; then
    echo "✅ nuclei instalado: $(nuclei -version 2>/dev/null || echo 'versão não detectada')"
else
    echo "❌ nuclei não encontrado no PATH"
    echo "🔍 Busca manual:"
    find /usr -name "nuclei" -type f 2>/dev/null || echo "Não encontrado"
fi

echo ""
echo "📋 Gobuster:"
if command -v gobuster >/dev/null 2>&1; then
    echo "✅ gobuster instalado: $(gobuster version 2>/dev/null || echo 'versão não detectada')"
else
    echo "❌ gobuster não encontrado no PATH"
    echo "🔍 Status apt:"
    dpkg -l | grep gobuster || echo "Não instalado via apt"
fi

echo ""
echo "📋 Masscan:"
if command -v masscan >/dev/null 2>&1; then
    echo "✅ masscan instalado: $(masscan --version 2>/dev/null | head -1 || echo 'versão não detectada')"
else
    echo "❌ masscan não encontrado"
fi

echo ""
echo "🔗 CONECTIVIDADE:"
echo "================"
echo "📋 DNS:"
nslookup api.samureye.com.br || echo "❌ Problema DNS"

echo ""
echo "📋 Conectividade HTTPS:"
if timeout 5 bash -c "</dev/tcp/api.samureye.com.br/443" >/dev/null 2>&1; then
    echo "✅ api.samureye.com.br:443 acessível"
else
    echo "❌ api.samureye.com.br:443 inacessível"
fi

echo ""
echo "📋 Teste curl:"
curl -I --connect-timeout 10 https://api.samureye.com.br/ 2>/dev/null | head -5 || echo "❌ Falha curl"

echo ""
echo "🔥 FIREWALL:"
echo "==========="
ufw status verbose

echo ""
echo "📊 RESUMO PROBLEMAS IDENTIFICADOS:"
echo "=================================="

# Verificar problemas
problems=()

if ! systemctl is-active --quiet samureye-collector; then
    problems+=("❌ Serviço samureye-collector inativo")
fi

if [ ! -f "/opt/samureye/collector/heartbeat.py" ]; then
    problems+=("❌ Script heartbeat.py ausente")
fi

if [ ! -f "/etc/samureye-collector/.env" ]; then
    problems+=("❌ Configuração .env ausente")
fi

if ! command -v nmap >/dev/null 2>&1; then
    problems+=("❌ nmap não instalado")
fi

if ! command -v gobuster >/dev/null 2>&1; then
    problems+=("❌ gobuster não disponível no PATH")
fi

if [ ${#problems[@]} -eq 0 ]; then
    echo "✅ Nenhum problema crítico identificado"
else
    for problem in "${problems[@]}"; do
        echo "$problem"
    done
fi

echo ""
echo "🔧 RECOMENDAÇÕES:"
echo "================"
echo "1. Verificar logs systemd: journalctl -u samureye-collector -f"
echo "2. Instalar nmap: apt install nmap -y"
echo "3. Verificar gobuster: dpkg -l | grep gobuster"
echo "4. Recriar .env se ausente"
echo "5. Testar heartbeat manualmente"
echo "6. Restart do serviço após correções"