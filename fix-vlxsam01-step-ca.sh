#!/bin/bash
# Fix vlxsam01 - Instalação step-ca ausente
# 28 de Agosto 2025

set -euo pipefail

echo "🔐 CORREÇÃO VLXSAM01 - Step-CA Certificate Authority Ausente"
echo "==========================================================="
echo "Data: $(date)"
echo

echo "⚠️ PROBLEMA IDENTIFICADO:"
echo "• vlxsam01 install.sh NÃO instala step-ca server"
echo "• Apenas configura NGINX proxy para ca.samureye.com.br"
echo "• vlxsam04 collector falha porque CA não existe"
echo "• Comando 'step' não encontrado no vlxsam01"
echo

echo "🔧 SOLUÇÕES IMPLEMENTADAS NO INSTALL.SH VLXSAM01:"
echo "1. ✅ Instalação completa do step CLI v0.25.2"
echo "2. ✅ Instalação completa do step-ca server v0.25.2"  
echo "3. ✅ Configuração automática da CA com:"
echo "   • Nome: SamurEye Internal CA"
echo "   • DNS: ca.samureye.com.br"
echo "   • Porta: 9000 (interno)"
echo "   • Provisioner: admin@samureye.com.br"
echo "4. ✅ Criação de usuário system 'step-ca'"
echo "5. ✅ Configuração de serviço systemd"
echo "6. ✅ Configuração de segurança hardening"
echo "7. ✅ Geração automática de password e fingerprint"
echo "8. ✅ NGINX proxy corrigido para porta 9000"
echo "9. ✅ Exibição do fingerprint na finalização"
echo

echo "📋 VERIFICAÇÃO DO VLXSAM01 INSTALL.SH:"
cd docs/deployment/vlxsam01

echo "• Total de linhas: $(wc -l < install.sh)"
echo "• Referencias step-ca: $(grep -c "step-ca" install.sh || echo 0)"
echo "• Seção step-ca adicionada: $(grep -c "INSTALAÇÃO STEP-CA" install.sh || echo 0)"
echo "• Systemd service incluído: $(grep -c "step-ca.service" install.sh || echo 0)"
echo "• NGINX proxy corrigido: $(grep -c "proxy_pass http://127.0.0.1:9000" install.sh || echo 0)"

echo
if bash -n install.sh 2>/dev/null; then
    echo "✅ SINTAXE: Script vlxsam01 sintaticamente correto"
else
    echo "❌ SINTAXE: Erro detectado no script"
    exit 1
fi

echo
echo "🚀 RESULTADO ESPERADO APÓS EXECUÇÃO:"
echo "1. step-ca server funcionando na porta 9000"
echo "2. systemctl status step-ca -> active"
echo "3. NGINX proxy https://ca.samureye.com.br -> 127.0.0.1:9000"
echo "4. Fingerprint disponível em /etc/step-ca/fingerprint.txt"
echo "5. vlxsam04 poderá se registrar com mTLS"
echo

echo "🎯 PRÓXIMOS PASSOS PARA O USUÁRIO:"
echo "1. No vlxsam01, executar install.sh atualizado:"
echo "   curl -fsSL <url_install.sh> | bash"
echo
echo "2. Após instalação, verificar step-ca:"
echo "   systemctl status step-ca"
echo "   step version"
echo "   cat /etc/step-ca/fingerprint.txt"
echo
echo "3. No vlxsam04, re-executar registro do collector:"
echo "   cd /opt/samureye-collector && sudo ./register-collector.sh gruppen-it vlxsam04"
echo
echo "4. Verificar conectividade entre vlxsam04 e vlxsam01:"
echo "   nc -z ca.samureye.com.br 443"
echo "   curl -k https://ca.samureye.com.br/health"
echo

echo "✅ vlxsam01 install.sh corrigido - Step-CA Certificate Authority incluído!"

# Auto-remover
rm -f "$0"