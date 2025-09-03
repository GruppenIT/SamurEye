#!/bin/bash

# ============================================================================
# CORREÇÃO IMEDIATA VLXSAM04: Ubuntu 24.04 
# ============================================================================

set -euo pipefail

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

log "🔧 Correção imediata para Ubuntu 24.04 iniciada"

# Atualizar repositórios
apt update

# Instalar pacotes corretos para Ubuntu 24.04
log "📦 Instalando Python 3.12 e dependências..."

apt install -y \
    curl \
    wget \
    gnupg \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    jq \
    htop \
    iotop \
    netcat-openbsd \
    net-tools \
    dnsutils \
    tcpdump \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    build-essential \
    git \
    unzip

log "✅ Pacotes instalados com sucesso"

# Configurar Python 3.12 como padrão
log "🐍 Configurando Python 3.12..."
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 100
update-alternatives --install /usr/bin/python python /usr/bin/python3.12 100

# Instalar pip e dependências Python
python3.12 -m ensurepip --upgrade
python3.12 -m pip install --upgrade pip setuptools wheel

python3.12 -m pip install \
    aiohttp \
    websockets \
    cryptography \
    requests \
    certifi \
    psutil \
    asyncio \
    pyyaml \
    structlog \
    python-multipart \
    aiofiles

log "✅ Python 3.12 configurado e dependências instaladas"

# Instalar Node.js 20
log "🟢 Instalando Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

node_version=$(node --version)
log "Node.js instalado: $node_version"

# Testar tudo
log "🔍 Testando instalação..."
python_version=$(python3 --version)
log "Python: $python_version"

python3 -c "
import aiohttp, websockets, cryptography, requests
import psutil, asyncio, yaml, structlog
print('✅ Dependências Python OK')
" || {
    log "❌ Erro nas dependências Python"
    exit 1
}

log "🎉 CORREÇÃO CONCLUÍDA!"
log "Agora você pode continuar com o resto da instalação do vlxsam04"