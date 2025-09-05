#!/bin/bash

echo "🔧 CORREÇÃO POSTGRESQL - vlxsam03"
echo "================================="

# Função para log
log() { echo "[$(date +'%H:%M:%S')] $1"; }
error() { echo "[$(date +'%H:%M:%S')] ❌ $1"; }
success() { echo "[$(date +'%H:%M:%S')] ✅ $1"; }

log "🔍 Verificando status do PostgreSQL..."

# Verificar se PostgreSQL está instalado
if ! which psql > /dev/null 2>&1; then
    error "PostgreSQL não está instalado"
    log "🔧 Instalando PostgreSQL 16..."
    apt update
    apt install -y postgresql-16 postgresql-client-16 postgresql-contrib-16
fi

# Verificar status do serviço
if systemctl is-active --quiet postgresql; then
    success "PostgreSQL está rodando"
else
    error "PostgreSQL não está rodando"
    log "🔧 Iniciando PostgreSQL..."
    systemctl start postgresql
    systemctl enable postgresql
    
    if systemctl is-active --quiet postgresql; then
        success "PostgreSQL iniciado com sucesso"
    else
        error "Falha ao iniciar PostgreSQL"
        systemctl status postgresql
        exit 1
    fi
fi

# Verificar se está escutando na porta 5432
log "🔍 Verificando porta 5432..."
if netstat -ln | grep -q ":5432"; then
    success "PostgreSQL escutando na porta 5432"
else
    error "PostgreSQL não está escutando na porta 5432"
fi

# Verificar configuração para aceitar conexões externas
log "🔍 Verificando configuração postgresql.conf..."
POSTGRES_VERSION=$(psql --version | awk '{print $3}' | sed 's/\..*//')
POSTGRES_CONF="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"

if [ -f "$POSTGRES_CONF" ]; then
    if grep -q "listen_addresses.*=.*'\*'" "$POSTGRES_CONF"; then
        success "listen_addresses configurado para aceitar conexões externas"
    else
        log "🔧 Configurando listen_addresses..."
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$POSTGRES_CONF"
        sed -i "s/listen_addresses = 'localhost'/listen_addresses = '*'/" "$POSTGRES_CONF"
        success "listen_addresses configurado"
        
        log "🔄 Reiniciando PostgreSQL para aplicar configuração..."
        systemctl restart postgresql
    fi
else
    error "Arquivo postgresql.conf não encontrado em $POSTGRES_CONF"
fi

# Verificar pg_hba.conf para permitir conexões md5
log "🔍 Verificando configuração pg_hba.conf..."
PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"

if [ -f "$PG_HBA" ]; then
    if grep -q "host.*all.*all.*md5" "$PG_HBA"; then
        success "pg_hba.conf já permite conexões externas"
    else
        log "🔧 Configurando pg_hba.conf..."
        echo "host    all             all             172.24.1.0/24           md5" >> "$PG_HBA"
        echo "host    all             all             192.168.100.0/24        md5" >> "$PG_HBA"
        success "pg_hba.conf configurado"
        
        log "🔄 Recarregando configuração PostgreSQL..."
        systemctl reload postgresql
    fi
fi

# Verificar/criar usuário e banco samureye
log "🔍 Verificando usuário e banco samureye..."
sudo -u postgres psql -c "SELECT 1" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    success "Acesso ao PostgreSQL como postgres OK"
    
    # Criar usuário samureye se não existir
    if sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='samureye'" | grep -q 1; then
        success "Usuário samureye já existe"
    else
        log "🔧 Criando usuário samureye..."
        sudo -u postgres psql -c "CREATE USER samureye WITH PASSWORD 'SamurEye2024!';"
        sudo -u postgres psql -c "ALTER USER samureye CREATEDB;"
        success "Usuário samureye criado"
    fi
    
    # Criar banco samureye se não existir
    if sudo -u postgres psql -t -c "SELECT 1 FROM pg_database WHERE datname='samureye'" | grep -q 1; then
        success "Banco samureye já existe"
    else
        log "🔧 Criando banco samureye..."
        sudo -u postgres psql -c "CREATE DATABASE samureye OWNER samureye;"
        success "Banco samureye criado"
    fi
else
    error "Falha ao acessar PostgreSQL como postgres"
    exit 1
fi

# Teste final de conectividade
log "🧪 Teste final de conectividade..."
if PGPASSWORD="SamurEye2024!" psql -h localhost -U samureye -d samureye -c "SELECT version();" > /dev/null 2>&1; then
    success "Conectividade local OK"
else
    error "Falha na conectividade local"
fi

# Teste conectividade externa (se não estiver no próprio vlxsam03)
if [ "$(hostname)" != "vlxsam03" ]; then
    log "🧪 Teste conectividade externa..."
    if PGPASSWORD="SamurEye2024!" psql -h 172.24.1.153 -U samureye -d samureye -c "SELECT version();" > /dev/null 2>&1; then
        success "Conectividade externa OK"
    else
        error "Falha na conectividade externa"
    fi
fi

echo ""
success "🎉 CORREÇÃO POSTGRESQL CONCLUÍDA!"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "   1. PostgreSQL está funcionando"
echo "   2. Aplicar schema do SamurEye:"
echo "      ssh root@172.24.1.152"
echo "      cd /opt/samureye/SamurEye"
echo "      npm run db:push --force"
echo ""
echo "   3. Testar novamente o collector"