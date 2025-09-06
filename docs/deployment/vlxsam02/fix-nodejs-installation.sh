#!/bin/bash
# Fix Node.js Installation Issues - vlxsam02
# Autor: SamurEye Team
# Data: $(date +%Y-%m-%d)

set -euo pipefail

# Configurações
NODE_VERSION="20"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função de log
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# ============================================================================
# 1. DIAGNÓSTICO DO SISTEMA
# ============================================================================

log "🔍 Diagnosticando sistema..."

# Verificar espaço em disco
log "📊 Verificando espaço em disco..."
df -h /
FREE_SPACE=$(df / | awk 'NR==2 {print $4}' | sed 's/[^0-9]*//g')
if [ "$FREE_SPACE" -lt 1000000 ]; then  # Menos de 1GB livre
    warn "Pouco espaço em disco disponível"
    # Limpeza automática
    apt-get clean
    apt-get autoremove -y
    log "✅ Limpeza de disco realizada"
fi

# Verificar permissões em /tmp
log "🔐 Verificando permissões..."
if [ ! -w /tmp ]; then
    chmod 1777 /tmp
    log "✅ Permissões de /tmp corrigidas"
fi

# Verificar conectividade de rede
log "🌐 Verificando conectividade..."
if ! ping -c 2 8.8.8.8 > /dev/null 2>&1; then
    error "Sem conectividade de rede"
fi

# ============================================================================
# 2. LIMPEZA COMPLETA NODE.JS ANTERIOR
# ============================================================================

log "🗑️ Removendo Node.js anterior completamente..."

# Parar processos node
pkill -f node || true
pkill -f npm || true

# Remover pacotes
apt-get remove -y nodejs npm node 2>/dev/null || true
apt-get purge -y nodejs npm node 2>/dev/null || true
apt-get autoremove -y

# Remover repositórios NodeSource
rm -f /etc/apt/sources.list.d/nodesource.list*
rm -f /etc/apt/trusted.gpg.d/nodesource.gpg*
rm -f /usr/share/keyrings/nodesource.gpg*

# Remover diretórios
rm -rf /usr/local/lib/node_modules
rm -rf /usr/local/bin/node
rm -rf /usr/local/bin/npm
rm -rf /usr/local/bin/npx
rm -rf ~/.npm
rm -rf ~/.node-gyp
rm -rf /tmp/npm-*

# Limpar cache
apt-get clean
apt-get update

log "✅ Limpeza completa realizada"

# ============================================================================
# 3. MÉTODO ALTERNATIVO - DIRECT DOWNLOAD
# ============================================================================

log "📥 Instalando Node.js via download direto..."

# Detectar arquitetura
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        NODE_ARCH="x64"
        ;;
    aarch64)
        NODE_ARCH="arm64"
        ;;
    armv7l)
        NODE_ARCH="armv7l"
        ;;
    *)
        error "Arquitetura não suportada: $ARCH"
        ;;
esac

# URL do Node.js
NODE_TARBALL="node-v20.19.5-linux-${NODE_ARCH}.tar.xz"
NODE_URL="https://nodejs.org/dist/v20.19.5/${NODE_TARBALL}"

log "🔗 URL: $NODE_URL"

# Download com múltiplas tentativas
cd /tmp
for attempt in 1 2 3; do
    log "📥 Tentativa $attempt de download..."
    
    # Limpar arquivo anterior
    rm -f "$NODE_TARBALL"
    
    # Download com wget (alternativa ao curl)
    if wget --timeout=30 --tries=3 "$NODE_URL"; then
        log "✅ Download concluído"
        break
    elif [ $attempt -eq 3 ]; then
        error "Falha no download após 3 tentativas"
    else
        warn "Tentativa $attempt falhou, tentando novamente..."
        sleep 5
    fi
done

# Verificar integridade do download
if [ ! -f "$NODE_TARBALL" ] || [ ! -s "$NODE_TARBALL" ]; then
    error "Arquivo baixado está corrompido ou vazio"
fi

log "📊 Tamanho do arquivo: $(du -h $NODE_TARBALL | cut -f1)"

# ============================================================================
# 4. INSTALAÇÃO MANUAL
# ============================================================================

log "⚙️ Instalando Node.js manualmente..."

# Extrair
tar -xf "$NODE_TARBALL"
NODE_DIR="node-v20.19.5-linux-${NODE_ARCH}"

if [ ! -d "$NODE_DIR" ]; then
    error "Falha na extração do Node.js"
fi

# Copiar binários
cp -r "$NODE_DIR"/* /usr/local/

# Criar links simbólicos
ln -sf /usr/local/bin/node /usr/bin/node
ln -sf /usr/local/bin/npm /usr/bin/npm
ln -sf /usr/local/bin/npx /usr/bin/npx

# Verificar instalação
if ! node --version > /dev/null 2>&1; then
    error "Node.js não foi instalado corretamente"
fi

if ! npm --version > /dev/null 2>&1; then
    error "npm não foi instalado corretamente"
fi

# Configurar npm
npm config set fund false
npm config set audit false
npm config set fund false --global
npm config set audit false --global

# Limpeza
rm -rf /tmp/node-*
rm -f /tmp/*.tar.xz

log "✅ Node.js instalado com sucesso"
log "📋 Versão Node.js: $(node --version)"
log "📋 Versão npm: $(npm --version)"

# ============================================================================
# 5. VERIFICAÇÃO FINAL
# ============================================================================

log "🔍 Verificação final..."

# Teste básico
echo "console.log('Node.js funcionando!');" > /tmp/test.js
if node /tmp/test.js | grep -q "funcionando"; then
    log "✅ Node.js está funcionando corretamente"
else
    error "Node.js não está funcionando"
fi

rm -f /tmp/test.js

# Verificar npm
if npm list -g --depth=0 > /dev/null 2>&1; then
    log "✅ npm está funcionando corretamente"
else
    warn "npm pode ter problemas"
fi

log "🎉 INSTALAÇÃO NODE.JS CONCLUÍDA COM SUCESSO!"
log ""
log "📋 PRÓXIMOS PASSOS:"
log "   1. Continue o install-hard-reset.sh"
log "   2. Execute: cd /opt/samureye/SamurEye"
log "   3. Execute: npm install"
log ""
log "💡 Se ainda houver problemas, execute:"
log "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/fix-nodejs-installation.sh | bash"