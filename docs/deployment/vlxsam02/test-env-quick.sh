#!/bin/bash

# Script de teste rápido para verificar carregamento do .env

set -e

WORKING_DIR="/opt/samureye/SamurEye"
SERVICE_USER="samureye"

echo "=== TESTE RÁPIDO DE CARREGAMENTO .env ==="

cd "$WORKING_DIR"

# Verificar se arquivos existem
echo "1. Verificando arquivos:"
echo "   .env exists: $([ -f .env ] && echo "SIM" || echo "NÃO")"
echo "   package.json exists: $([ -f package.json ] && echo "SIM" || echo "NÃO")"

if [ -f .env ]; then
    echo "   .env size: $(stat -c%s .env) bytes"
    echo "   .env owner: $(stat -c %U .env)"
    echo "   .env perms: $(stat -c %a .env)"
fi

# Verificar dotenv disponível
echo ""
echo "2. Verificando dotenv:"
if npm list dotenv >/dev/null 2>&1; then
    echo "   dotenv: INSTALADO"
else
    echo "   dotenv: NÃO INSTALADO"
fi

# Teste simples de carregamento
echo ""
echo "3. Teste de carregamento como usuário $SERVICE_USER:"

cat > /tmp/quick-test.js << 'EOF'
try {
    require('dotenv').config();
    console.log('   DATABASE_URL carregada:', process.env.DATABASE_URL ? 'SIM' : 'NÃO');
    console.log('   PGHOST:', process.env.PGHOST || 'undefined');
    console.log('   PGPORT:', process.env.PGPORT || 'undefined');
    console.log('   NODE_ENV:', process.env.NODE_ENV || 'undefined');
    
    if (process.env.DATABASE_URL && process.env.DATABASE_URL.includes(':443')) {
        console.log('   ❌ ERRO: DATABASE_URL contém porta 443');
        process.exit(1);
    } else if (process.env.DATABASE_URL && process.env.DATABASE_URL.includes(':5432')) {
        console.log('   ✅ DATABASE_URL com porta 5432 (correto)');
    }
    
    console.log('   ✅ Teste concluído');
} catch (error) {
    console.log('   ❌ Erro:', error.message);
    process.exit(1);
}
EOF

if sudo -u $SERVICE_USER node /tmp/quick-test.js; then
    echo "✅ TESTE SUCESSO: Carregamento funcionando"
else
    echo "❌ TESTE FALHA: Problema no carregamento"
fi

rm -f /tmp/quick-test.js
echo ""
echo "=== FIM DO TESTE ==="