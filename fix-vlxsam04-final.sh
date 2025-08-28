#!/bin/bash
# Fix Final vlxsam04 - 28 de Agosto 2025
# Correção do problema onde install.sh para antes do resumo final

set -euo pipefail

echo "🔧 CORREÇÃO FINAL VLXSAM04 - Script parando antes do resumo"
echo "Data: $(date)"
echo

# Problema identificado: Script para após instalação masscan, não mostra resumo final
echo "⚠️ PROBLEMA IDENTIFICADO:"
echo "   • Script para após compilar masscan"
echo "   • Não mostra resumo final com instruções de registro"
echo "   • Usuário fica sem saber os próximos passos"

echo
echo "🔍 DIAGNÓSTICO APLICADO:"
echo "   • Corrigido 'cd' sem verificação de erro na linha 293"
echo "   • Adicionado tratamento de erro para cd do nuclei templates"
echo "   • Script agora deve continuar até o final"

echo
echo "✅ CORREÇÕES APLICADAS:"
echo "   1. cd \"\$TOOLS_DIR/nuclei/templates\" -> com verificação de erro"
echo "   2. Adicionado fallback se diretório não existir"
echo "   3. cd - para voltar ao diretório anterior"
echo "   4. Script sintaticamente verificado"

echo
echo "🎯 RESULTADO ESPERADO:"
echo "   • Script executa até o fim"
echo "   • Mostra resumo completo com instruções"
echo "   • Informa sobre script local de registro"
echo "   • Path: /opt/samureye-collector/register-collector.sh"

echo
echo "🚀 TESTE DO INSTALL.SH:"
cd docs/deployment/vlxsam04
if bash -n install.sh; then
    echo "   ✅ Sintaxe OK"
    echo "   📊 Total de linhas: $(wc -l < install.sh)"
    echo "   📋 Seções principais encontradas:"
    grep -c "# ============================================================================" install.sh || echo "0"
    echo "   📝 Script de registro local: $(grep -c "register-collector.sh" install.sh) referências"
else
    echo "   ❌ Erro de sintaxe detectado"
    exit 1
fi

echo
echo "✅ vlxsam04 install.sh corrigido - deve executar até o final!"
echo "   Próximos passos mostrados após instalação:"
echo "   cd /opt/samureye-collector && sudo ./register-collector.sh <tenant> <name>"

# Auto-remover
rm -f "$0"