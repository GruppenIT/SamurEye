#!/bin/bash

# ============================================================================
# CORREÇÃO VLXSAM04: Compatibilidade Ubuntu 24.04 
# ============================================================================
#
# Servidor: vlxsam04 (192.168.100.151)  
# Função: Corrigir compatibilidade de pacotes Python para Ubuntu 24.04
#
# PROBLEMA IDENTIFICADO:
# - Ubuntu 24.04 usa Python 3.12 por padrão, não Python 3.11
# - Package 'netcat' foi substituído por 'netcat-openbsd' 
#
# SOLUÇÃO:
# - Instalar Python 3.12 e dependências corretas
# - Usar netcat-openbsd em vez de netcat
# ============================================================================

set -euo pipefail

# Função de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/vlxsam04-fix.log
}

log "🔧 Iniciando correção Ubuntu 24.04 para vlxsam04"

# ============================================================================
# 1. CORRIGIR PACOTES PYTHON E NETCAT
# ============================================================================

log "📦 Instalando pacotes corretos para Ubuntu 24.04..."

# Atualizar repositórios
apt update

# Instalar pacotes corretos
apt install -y \
    netcat-openbsd \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    build-essential

log "✅ Pacotes corretos instalados"

# ============================================================================
# 2. CONFIGURAR PYTHON 3.12 COMO PADRÃO
# ============================================================================

log "🐍 Configurando Python 3.12 como padrão..."

# Definir Python 3.12 como padrão
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 100
update-alternatives --install /usr/bin/python python /usr/bin/python3.12 100

# Instalar pip para Python 3.12
python3.12 -m ensurepip --upgrade
python3.12 -m pip install --upgrade pip setuptools wheel

log "✅ Python 3.12 configurado como padrão"

# ============================================================================
# 3. INSTALAR DEPENDÊNCIAS PYTHON
# ============================================================================

log "📚 Instalando dependências Python para o collector agent..."

# Dependências Python para o agente
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

log "✅ Dependências Python instaladas"

# ============================================================================
# 4. VALIDAR INSTALAÇÃO
# ============================================================================

log "🔍 Validando instalação..."

# Verificar versões instaladas
python_version=$(python3 --version)
pip_version=$(python3 -m pip --version)
netcat_test=$(which nc)

log "Python: $python_version"
log "Pip: $pip_version"
log "Netcat: $netcat_test"

# Testar importações críticas
python3 -c "
import aiohttp, websockets, cryptography, requests
import psutil, asyncio, yaml, structlog
print('✅ Todas as dependências importadas com sucesso')
" 2>/dev/null || {
    log "❌ Erro na importação de dependências Python"
    exit 1
}

# ============================================================================
# 5. STATUS FINAL
# ============================================================================

log "🎉 CORREÇÃO CONCLUÍDA COM SUCESSO!"
log ""
log "✅ Python 3.12 instalado e configurado"
log "✅ netcat-openbsd instalado"
log "✅ Todas as dependências Python funcionando"
log ""
log "Próximo passo: Executar o script principal install.sh"
