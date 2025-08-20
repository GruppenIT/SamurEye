#!/bin/bash

# Script para configurar usuário samureye e credenciais no vlxsam02

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./setup-user.sh"
fi

log "🔐 Configurando usuário samureye no vlxsam02..."

# Definir senha padrão (pode ser alterada depois)
SAMUREYE_PASSWORD="SamurEye2024!"

# Criar usuário se não existir
if ! id "samureye" &>/dev/null; then
    log "Criando usuário samureye..."
    useradd -m -s /bin/bash samureye
    log "Usuário samureye criado"
else
    log "Usuário samureye já existe"
fi

# Definir senha
log "Definindo senha para o usuário samureye..."
echo "samureye:$SAMUREYE_PASSWORD" | chpasswd
log "Senha definida para o usuário samureye"

# Adicionar ao grupo sudo
usermod -aG sudo samureye
log "Usuário samureye adicionado ao grupo sudo"

# Configurar sudoers para não pedir senha (opcional, para automação)
if ! grep -q "samureye ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
    echo "samureye ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    log "Configurado sudo sem senha para samureye"
fi

# Criar diretórios necessários
log "Criando diretórios..."
mkdir -p /opt/samureye
mkdir -p /var/log/samureye
mkdir -p /home/samureye/.ssh

# Definir permissões
chown -R samureye:samureye /opt/samureye
chown -R samureye:samureye /var/log/samureye
chown -R samureye:samureye /home/samureye
chmod 700 /home/samureye/.ssh

# Configurar ambiente para o usuário samureye
log "Configurando ambiente do usuário..."
cat >> /home/samureye/.bashrc << 'EOF'

# SamurEye Environment
export PATH=/usr/local/bin:$PATH
export NODE_ENV=production
export SAMUREYE_HOME=/opt/samureye

# Aliases úteis
alias ll='ls -la'
alias la='ls -la'
alias samureye-logs='tail -f /var/log/samureye/*.log'
alias samureye-status='pm2 status'
alias samureye-restart='pm2 restart all'

# Navegar diretamente para o diretório da aplicação
cd /opt/samureye 2>/dev/null || true
EOF

chown samureye:samureye /home/samureye/.bashrc

# Criar arquivo de credenciais de referência
log "Criando arquivo de credenciais..."
cat > /opt/samureye/CREDENTIALS.txt << EOF
CREDENCIAIS DO SERVIDOR VLXSAM02
================================

Usuário do Sistema:
- Usuário: samureye
- Senha: $SAMUREYE_PASSWORD
- Home: /home/samureye
- Diretório App: /opt/samureye

Comandos Úteis:
- Fazer login: su - samureye
- Ver logs: tail -f /var/log/samureye/*.log
- Status da app: pm2 status
- Reiniciar app: pm2 restart all

Diretórios Importantes:
- /opt/samureye - Aplicação principal
- /var/log/samureye - Logs da aplicação
- /etc/samureye - Configurações
- /opt/backup - Backups

Para trocar senha:
sudo passwd samureye
EOF

chmod 600 /opt/samureye/CREDENTIALS.txt
chown samureye:samureye /opt/samureye/CREDENTIALS.txt

# Instalar chaves SSH se necessário (para deploy automatizado)
if [ ! -f /home/samureye/.ssh/id_rsa ]; then
    log "Gerando chave SSH para o usuário samureye..."
    sudo -u samureye ssh-keygen -t rsa -b 4096 -f /home/samureye/.ssh/id_rsa -N "" -C "samureye@vlxsam02"
    log "Chave SSH gerada"
fi

log "✅ Configuração do usuário samureye concluída!"

echo ""
echo "🎯 INFORMAÇÕES DE ACESSO:"
echo "========================="
echo "Servidor: vlxsam02 (172.24.1.152)"
echo "Usuário: samureye"
echo "Senha: $SAMUREYE_PASSWORD"
echo "Diretório: /opt/samureye"
echo ""
echo "📋 COMANDOS PARA CONECTAR:"
echo "ssh samureye@172.24.1.152"
echo "# Ou localmente:"
echo "su - samureye"
echo ""
echo "💡 PRÓXIMOS PASSOS:"
echo "1. Conectar como usuário samureye"
echo "2. Clonar/copiar o código da aplicação para /opt/samureye"  
echo "3. Executar script de instalação das dependências"
echo ""
echo "🔒 SEGURANÇA:"
echo "- Arquivo de credenciais salvo em: /opt/samureye/CREDENTIALS.txt"
echo "- Altere a senha se necessário: sudo passwd samureye"
echo "- Chave SSH gerada em: /home/samureye/.ssh/id_rsa"