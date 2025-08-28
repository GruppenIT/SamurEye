#!/bin/bash

# Fix masscan validation issue on vlxsam04
echo "🔧 Verificando status do masscan..."

# Testar diretamente
echo "Testando /usr/bin/masscan:"
if [[ -f "/usr/bin/masscan" ]]; then
    ls -la /usr/bin/masscan
    /usr/bin/masscan --version
    echo "PATH atual: $PATH"
else
    echo "❌ /usr/bin/masscan não existe"
fi

echo ""
echo "Testando command -v masscan:"
if command -v masscan >/dev/null 2>&1; then
    echo "✅ command -v found: $(command -v masscan)"
    which masscan
else
    echo "❌ command -v failed"
fi

echo ""
echo "Testando which masscan:"
which masscan || echo "❌ which failed"

echo ""
echo "Testando masscan --version diretamente:"
masscan --version 2>&1 || echo "❌ masscan --version failed"

echo ""
echo "Forçando atualização do PATH e testando novamente:"
export PATH="/usr/bin:/usr/local/bin:$PATH"
hash -r
masscan --version 2>&1 || echo "❌ Ainda falhou após PATH update"