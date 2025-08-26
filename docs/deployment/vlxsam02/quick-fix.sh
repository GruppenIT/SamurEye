#!/bin/bash

# Script de correção rápida para problema de permissões
# Execute apenas se o install.sh falhar com erro de permissões

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"; exit 1; }

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./quick-fix.sh"
fi

WORKING_DIR="/opt/samureye/SamurEye"
SERVICE_USER="samureye"

log "🔧 CORREÇÃO RÁPIDA DE PERMISSÕES"

# 1. Parar serviço se estiver rodando
if systemctl is-active --quiet samureye-app 2>/dev/null; then
    log "Parando serviço..."
    systemctl stop samureye-app || true
fi

# 2. Criar usuário se não existir
if ! id "$SERVICE_USER" &>/dev/null; then
    log "Criando usuário $SERVICE_USER..."
    useradd -r -s /bin/bash -d /opt/samureye -m "$SERVICE_USER"
else
    log "Usuário $SERVICE_USER já existe"
fi

# 3. Garantir estrutura de diretórios
log "Criando estrutura de diretórios..."
mkdir -p /opt/samureye
mkdir -p "$WORKING_DIR"

# 4. Limpar e recriar diretório de trabalho
log "Limpando diretório de trabalho..."
rm -rf "$WORKING_DIR"
mkdir -p "$WORKING_DIR"

# 5. Configurar permissões corretas
log "Configurando permissões..."
chown -R $SERVICE_USER:$SERVICE_USER /opt/samureye
chmod 755 /opt/samureye
chmod 755 "$WORKING_DIR"

# 6. Clonar repositório como usuário correto
log "Clonando repositório..."
cd "$WORKING_DIR"
sudo -u $SERVICE_USER git clone https://github.com/GruppenIT/SamurEye.git .

# 7. Verificar se clone funcionou
if [ -f "package.json" ]; then
    log "✅ Clone realizado com sucesso"
    
    # Instalar dependências
    log "Instalando dependências..."
    sudo -u $SERVICE_USER npm install
    
    # Verificar dotenv
    if ! grep -q '"dotenv"' package.json; then
        log "Adicionando dotenv..."
        sudo -u $SERVICE_USER npm install dotenv
    fi
    
    log "✅ Correção concluída com sucesso"
    log "Agora execute: sudo ./install.sh"
else
    error "Falha no clone do repositório"
fi