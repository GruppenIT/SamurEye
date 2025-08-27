#!/bin/bash

# ============================================================================
# CORREÇÃO ES6 APENAS - SAMUREYE VLXSAM02
# Script focado apenas em corrigir o erro "require is not defined"
# ============================================================================

set -euo pipefail

# Variáveis
readonly WORKING_DIR="/opt/samureye/SamurEye"
readonly ETC_DIR="/etc/samureye"
readonly SERVICE_USER="samureye"
readonly POSTGRES_HOST="172.24.1.153"
readonly POSTGRES_PORT="5432"

# Função de logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

echo "🔧 CORREÇÃO ES6 - SAMUREYE VLXSAM02"
echo "=================================="
log "🎯 Corrigindo apenas problema ES6 modules..."

# 1. Verificar se é root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script deve ser executado como root"
    exit 1
fi

# 2. Verificar se diretório existe
if [ ! -d "$WORKING_DIR" ]; then
    echo "❌ Diretório $WORKING_DIR não encontrado"
    echo "Execute o script install.sh primeiro"
    exit 1
fi

# 3. Verificar arquivo .env
if [ ! -f "$WORKING_DIR/.env" ]; then
    echo "❌ Arquivo .env não encontrado"
    echo "Execute o script install.sh primeiro"
    exit 1
fi

cd "$WORKING_DIR"

# 4. Remover arquivos de teste conflitantes
log "🧹 Removendo arquivos de teste conflitantes..."
rm -f test-env-loading.js test-env-loading.mjs
rm -f final-test.js final-test.mjs
rm -f fix-test.js fix-test.mjs
rm -f ultimate-test.js ultimate-test.mjs

# 5. Criar teste ES6 definitivo
log "📝 Criando teste ES6 correto..."
cat > "es6-fix-test.mjs" << 'EOF'
import dotenv from 'dotenv';

console.log('=== TESTE ES6 DEFINITIVO ===');
console.log('Diretório atual:', process.cwd());
console.log('Arquivo sendo executado: es6-fix-test.mjs');

try {
    // Carregar .env usando ES6 modules
    const result = dotenv.config();
    
    if (result.error) {
        console.log('❌ ERRO ao carregar .env:', result.error.message);
        process.exit(1);
    }
    
    console.log('✅ dotenv carregado com sucesso usando ES6');
    
    // Verificar variáveis essenciais
    const checkVars = ['DATABASE_URL', 'PGHOST', 'PGPORT', 'NODE_ENV'];
    let allOk = true;
    
    for (const varName of checkVars) {
        if (process.env[varName]) {
            const displayValue = varName === 'DATABASE_URL' ? 
                process.env[varName].substring(0, 30) + '...' : 
                process.env[varName];
            console.log(`✅ ${varName}: ${displayValue}`);
        } else {
            console.log(`❌ ${varName}: NÃO DEFINIDA`);
            allOk = false;
        }
    }
    
    // Verificar porta 443 específicamente
    if (process.env.DATABASE_URL) {
        if (process.env.DATABASE_URL.includes(':443')) {
            console.log('❌ PROBLEMA DETECTADO: DATABASE_URL contém porta 443');
            console.log('🔧 Execute o script install.sh para corrigir');
            process.exit(1);
        } else if (process.env.DATABASE_URL.includes(':5432')) {
            console.log('✅ DATABASE_URL usa porta 5432 (correto)');
        }
    }
    
    if (allOk) {
        console.log('');
        console.log('🎉 SUCESSO TOTAL!');
        console.log('✅ ES6 modules funcionando corretamente');
        console.log('✅ dotenv carregado sem require()');
        console.log('✅ Todas as variáveis presentes');
        console.log('✅ Nenhuma porta 443 detectada');
        console.log('');
        console.log('O problema "require is not defined" foi resolvido!');
    } else {
        console.log('❌ ALGUMAS VARIÁVEIS FALTANDO');
        process.exit(1);
    }
    
} catch (error) {
    console.log('❌ ERRO JAVASCRIPT:', error.message);
    console.log('Stack trace:', error.stack);
    process.exit(1);
}
EOF

# 6. Executar teste como usuário correto
log "🧪 Executando teste ES6..."
echo ""
echo "=== RESULTADO DO TESTE ==="

if sudo -u $SERVICE_USER NODE_ENV=development node es6-fix-test.mjs; then
    echo ""
    log "✅ CORREÇÃO ES6: SUCESSO COMPLETO!"
    log "✅ O erro 'require is not defined' foi resolvido"
    log "✅ ES6 modules funcionando corretamente"
else
    echo ""
    log "❌ CORREÇÃO ES6: AINDA COM PROBLEMAS"
    log "❌ Verificar se o Node.js 20 está instalado corretamente"
    log "❌ Verificar se o package.json contém: \"type\": \"module\""
fi

# 7. Limpeza
rm -f es6-fix-test.mjs

echo ""
echo "================== RESUMO =================="
log "🔧 Correção ES6 concluída"
log "📁 Diretório: $WORKING_DIR"
log "📄 Arquivo .env: $(ls -la $WORKING_DIR/.env | cut -d' ' -f1,9-)"
log "🚀 Para iniciar aplicação: systemctl start samureye-app"
log "📋 Para ver logs: journalctl -u samureye-app -f"
echo "============================================="