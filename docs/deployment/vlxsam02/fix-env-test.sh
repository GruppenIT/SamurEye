#!/bin/bash

# Script para corrigir problema específico do teste de .env
# Resolve o problema "Cannot find module 'dotenv'"

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"; exit 1; }

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-env-test.sh"
fi

# Configurações
WORKING_DIR="/opt/samureye/SamurEye"
SERVICE_USER="samureye"

log "🔧 CORREÇÃO ESPECÍFICA - TESTE ENV"

# Verificar se existe o diretório e node_modules
if [ ! -d "$WORKING_DIR" ]; then
    error "Diretório $WORKING_DIR não existe"
fi

if [ ! -d "$WORKING_DIR/node_modules" ]; then
    error "node_modules não existe em $WORKING_DIR"
fi

cd "$WORKING_DIR"

# Verificar se dotenv está instalado
log "Verificando instalação do dotenv..."
if ! sudo -u $SERVICE_USER npm list dotenv >/dev/null 2>&1; then
    log "Instalando dotenv..."
    sudo -u $SERVICE_USER npm install dotenv
else
    log "✅ dotenv já está instalado"
fi

# Criar teste específico no diretório correto
log "Criando teste corrigido..."
cat > "$WORKING_DIR/fix-test.mjs" << 'EOF'
import dotenv from 'dotenv';

try {
    console.log('Diretório atual:', process.cwd());
    console.log('Carregando dotenv...');
    
    dotenv.config();
    
    const vars = ['DATABASE_URL', 'PGHOST', 'PGPORT', 'NODE_ENV'];
    let allOk = true;
    
    console.log('=== VARIÁVEIS DE AMBIENTE ===');
    vars.forEach(varName => {
        const value = process.env[varName];
        if (value) {
            if (varName === 'DATABASE_URL') {
                console.log(`${varName}: ${value.substring(0, 40)}...`);
            } else {
                console.log(`${varName}: ${value}`);
            }
        } else {
            console.log(`${varName}: NÃO DEFINIDA`);
            allOk = false;
        }
    });
    
    if (process.env.DATABASE_URL && process.env.DATABASE_URL.includes(':443')) {
        console.log('❌ ERRO: DATABASE_URL tem porta 443');
        process.exit(1);
    }
    
    if (allOk) {
        console.log('✅ TESTE SUCESSO: Todas as variáveis carregadas');
    } else {
        console.log('❌ TESTE FALHA: Variáveis faltando');
        process.exit(1);
    }
} catch (error) {
    console.log('❌ ERRO JAVASCRIPT:', error.message);
    console.log('Stack:', error.stack);
    process.exit(1);
}
EOF

# Executar teste com debug completo
log "Executando teste corrigido..."
echo "=== DEBUG INFO ==="
echo "Working directory: $(pwd)"
echo "User: $(whoami)"
echo "Node version: $(node --version 2>/dev/null || echo 'não encontrado')"
echo "npm version: $(npm --version 2>/dev/null || echo 'não encontrado')"
echo ""

# Teste como usuário correto
log "Executando como usuário $SERVICE_USER..."
if sudo -u $SERVICE_USER NODE_ENV=development node fix-test.mjs; then
    log "✅ CORREÇÃO APLICADA COM SUCESSO"
else
    log "❌ Teste ainda falhando - verificar logs acima"
fi

# Limpeza
rm -f "$WORKING_DIR/fix-test.mjs"

log "✅ Correção concluída"