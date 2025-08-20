#!/bin/bash

# Script para corrigir problemas específicos de instalação no vlxsam02

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

log "🔧 Corrigindo problemas de instalação do SamurEye..."

# 1. Verificar se estamos no diretório correto
if [ ! -f "package.json" ]; then
    error "Execute este script em /opt/samureye/SamurEye (onde está o package.json)"
fi

# 2. Verificar se package-lock.json existe
if [ ! -f "package-lock.json" ]; then
    warn "package-lock.json não encontrado. Isso pode causar problemas com npm ci."
    log "Executando npm install para gerar package-lock.json..."
    npm install
fi

# 3. Limpar cache do npm
log "Limpando cache do npm..."
npm cache clean --force

# 4. Remover node_modules se existir
if [ -d "node_modules" ]; then
    log "Removendo node_modules existente..."
    rm -rf node_modules
fi

# 5. Instalar dependências
log "Instalando dependências com npm install..."
npm install

# 6. Verificar se tsx está instalado (necessário para TypeScript)
if ! npm list tsx >/dev/null 2>&1; then
    log "Instalando tsx globalmente..."
    npm install -g tsx
fi

# 7. Verificar se build funciona
log "Testando build..."
npm run build 2>/dev/null || warn "Build falhou - pode ser normal se não tiver script de build configurado"

# 8. Corrigir permissões
log "Corrigindo permissões..."
sudo chown -R samureye:samureye /opt/samureye
chmod -R 755 /opt/samureye/SamurEye

# 9. Criar arquivo .env local se não existir
if [ ! -f ".env" ]; then
    log "Criando arquivo .env local..."
    cat > .env << 'EOF'
NODE_ENV=development
PORT=3000
DATABASE_URL="postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod"
SESSION_SECRET="samureye-development-secret-key"
EOF
fi

# 10. Testar se aplicação inicia
log "Testando se aplicação inicia..."
timeout 10 npm run dev &
PID=$!
sleep 5

if kill -0 $PID 2>/dev/null; then
    log "✅ Aplicação iniciou com sucesso!"
    kill $PID 2>/dev/null || true
else
    warn "Aplicação não iniciou corretamente. Verificar logs."
fi

# 11. Verificar dependências críticas
log "Verificando dependências críticas..."
CRITICAL_DEPS=("express" "tsx" "@types/node" "typescript")

for dep in "${CRITICAL_DEPS[@]}"; do
    if npm list "$dep" >/dev/null 2>&1; then
        echo "✅ $dep"
    else
        echo "❌ $dep - FALTANDO"
        npm install "$dep" || warn "Falha ao instalar $dep"
    fi
done

log "🎯 Correção concluída!"

echo ""
echo "📋 RESUMO:"
echo "- Diretório: $(pwd)"
echo "- package.json: $([ -f package.json ] && echo "✅" || echo "❌")"
echo "- package-lock.json: $([ -f package-lock.json ] && echo "✅" || echo "❌")"
echo "- node_modules: $([ -d node_modules ] && echo "✅" || echo "❌")"
echo "- .env: $([ -f .env ] && echo "✅" || echo "❌")"
echo ""
echo "💡 PRÓXIMOS COMANDOS:"
echo "npm run dev        # Para desenvolvimento"
echo "npm start          # Para produção"
echo "npm run db:push    # Para migrações"