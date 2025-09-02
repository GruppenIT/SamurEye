#!/bin/bash

# ============================================================================
# CORREÇÃO AUTOMÁTICA - CONECTIVIDADE POSTGRESQL vlxsam03
# ============================================================================
# Corrige problemas de conectividade entre vlxsam03 e vlxsam02

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️  $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}"; exit 1; }

echo ""
echo "🔧 CORREÇÃO AUTOMÁTICA - CONECTIVIDADE POSTGRESQL"
echo "================================================"
echo "🖥️  Servidor: $(hostname)"
echo "📅 Data: $(date)"
echo "================================================"
echo ""

# ============================================================================
# 1. VERIFICAR SE É O vlxsam03
# ============================================================================

if [ "$(hostname)" != "vlxsam03" ]; then
    error "Este script deve ser executado no vlxsam03, não em $(hostname)"
fi

# ============================================================================
# 2. VERIFICAR E CORRIGIR SERVIÇO POSTGRESQL
# ============================================================================

log "🐘 Verificando status do PostgreSQL..."

if ! systemctl is-active --quiet postgresql; then
    warn "PostgreSQL não está ativo - iniciando..."
    systemctl start postgresql
    systemctl enable postgresql
    sleep 5
    
    if systemctl is-active --quiet postgresql; then
        log "✅ PostgreSQL iniciado com sucesso"
    else
        error "❌ Falha ao iniciar PostgreSQL"
    fi
else
    log "✅ PostgreSQL já está ativo"
fi

# ============================================================================
# 3. VERIFICAR E CORRIGIR CONFIGURAÇÃO DE ESCUTA
# ============================================================================

log "⚙️ Verificando configuração listen_addresses..."

POSTGRES_VERSION=$(ls /etc/postgresql/ | head -1)
POSTGRES_CONF="/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"

# Verificar listen_addresses
if grep -q "^listen_addresses = '\*'" "$POSTGRES_CONF"; then
    log "✅ listen_addresses já configurado corretamente"
else
    warn "Corrigindo listen_addresses..."
    
    # Comentar linha antiga e adicionar nova
    sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" "$POSTGRES_CONF"
    
    # Verificar se foi aplicado
    if grep -q "^listen_addresses = '\*'" "$POSTGRES_CONF"; then
        log "✅ listen_addresses corrigido"
        RESTART_NEEDED=true
    else
        # Forçar adição se não funcionou
        echo "listen_addresses = '*'" >> "$POSTGRES_CONF"
        log "✅ listen_addresses adicionado"
        RESTART_NEEDED=true
    fi
fi

# ============================================================================
# 4. VERIFICAR E CORRIGIR pg_hba.conf
# ============================================================================

log "🔐 Verificando configuração pg_hba.conf..."

# Verificar se já tem as regras SamurEye
if grep -q "SamurEye On-Premise Access" "$PG_HBA"; then
    log "✅ Regras SamurEye já existem no pg_hba.conf"
else
    warn "Adicionando regras SamurEye ao pg_hba.conf..."
    
    # Backup do arquivo original
    cp "$PG_HBA" "$PG_HBA.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Adicionar regras SamurEye
    cat >> "$PG_HBA" << 'EOF'

# SamurEye On-Premise Access
# vlxsam01 - Gateway
host    samureye        samureye_user   172.24.1.151/32         md5
host    samureye        samureye        172.24.1.151/32         md5
# vlxsam02 - Application Server  
host    samureye        samureye_user   172.24.1.152/32         md5
host    samureye        samureye        172.24.1.152/32         md5
# vlxsam03 - Database (local)
host    samureye        samureye_user   127.0.0.1/32            md5
host    samureye        samureye        127.0.0.1/32            md5
host    samureye        samureye_user   172.24.1.153/32         md5
host    samureye        samureye        172.24.1.153/32         md5
# vlxsam04 - Collector
host    samureye        samureye_user   172.24.1.154/32         md5
host    samureye        samureye        172.24.1.154/32         md5
# Rede local SamurEye (backup)
host    samureye        samureye_user   172.24.1.0/24           md5
host    samureye        samureye        172.24.1.0/24           md5
host    grafana         grafana         172.24.1.153/32         md5
# Permitir conexões md5 para usuários corretos
host    all             samureye_user   172.24.1.0/24           md5
host    all             samureye        172.24.1.0/24           md5
EOF
    
    log "✅ Regras SamurEye adicionadas ao pg_hba.conf"
    RESTART_NEEDED=true
fi

# ============================================================================
# 5. VERIFICAR E CORRIGIR FIREWALL
# ============================================================================

log "🔥 Verificando configuração do firewall..."

# Verificar se UFW está ativo
if ufw status | grep -q "Status: active"; then
    log "🔍 UFW ativo - verificando regras..."
    
    # Verificar se porta 5432 está liberada
    if ufw status | grep -q "5432"; then
        log "✅ Porta 5432 já liberada no firewall"
    else
        warn "Liberando porta 5432 no firewall..."
        ufw allow 5432/tcp
        log "✅ Porta 5432 liberada"
    fi
    
    # Verificar regras específicas para vlxsam02
    if ufw status numbered | grep -q "172.24.1.152"; then
        log "✅ Regras específicas para vlxsam02 já existem"
    else
        warn "Adicionando regras específicas para vlxsam02..."
        ufw allow from 172.24.1.152 to any port 5432
        log "✅ Regras para vlxsam02 adicionadas"
    fi
    
else
    warn "UFW não está ativo - ativando com regras básicas..."
    ufw --force enable
    ufw allow ssh
    ufw allow 5432/tcp
    ufw allow from 172.24.1.0/24
    log "✅ UFW configurado e ativado"
fi

# ============================================================================
# 6. REINICIAR POSTGRESQL SE NECESSÁRIO
# ============================================================================

if [ "$RESTART_NEEDED" = "true" ]; then
    log "🔄 Reiniciando PostgreSQL para aplicar mudanças..."
    systemctl restart postgresql
    sleep 10
    
    if systemctl is-active --quiet postgresql; then
        log "✅ PostgreSQL reiniciado com sucesso"
    else
        error "❌ Falha ao reiniciar PostgreSQL"
    fi
fi

# ============================================================================
# 7. VERIFICAR USUÁRIOS E SENHAS
# ============================================================================

log "👤 Verificando usuários PostgreSQL..."

# Verificar se usuários existem
USERS_CHECK=$(sudo -u postgres psql -t -c "SELECT usename FROM pg_user WHERE usename IN ('samureye', 'samureye_user');" 2>/dev/null | tr -d ' ' | grep -v '^$' | wc -l)

if [ "$USERS_CHECK" -lt 2 ]; then
    warn "Usuários SamurEye não encontrados - criando..."
    
    sudo -u postgres psql << 'EOF'
-- Remover usuários se existirem
DROP USER IF EXISTS samureye_user;
DROP USER IF EXISTS samureye;

-- Criar usuários com permissões corretas
CREATE USER samureye_user WITH ENCRYPTED PASSWORD 'samureye_secure_2024';
ALTER USER samureye_user CREATEDB;
ALTER USER samureye_user SUPERUSER;

CREATE USER samureye WITH ENCRYPTED PASSWORD 'samureye_secure_2024';
ALTER USER samureye CREATEDB; 
ALTER USER samureye SUPERUSER;

-- Verificar criação
\du
EOF
    
    log "✅ Usuários SamurEye criados"
else
    log "✅ Usuários SamurEye já existem"
    
    # Garantir que senhas estão corretas
    sudo -u postgres psql << 'EOF'
ALTER USER samureye_user WITH ENCRYPTED PASSWORD 'samureye_secure_2024';
ALTER USER samureye WITH ENCRYPTED PASSWORD 'samureye_secure_2024';
EOF
    log "✅ Senhas atualizadas"
fi

# ============================================================================
# 8. VERIFICAR BANCO SAMUREYE
# ============================================================================

log "🗃️ Verificando banco de dados SamurEye..."

if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw samureye; then
    log "✅ Banco 'samureye' já existe"
else
    warn "Criando banco 'samureye'..."
    
    sudo -u postgres psql << 'EOF'
CREATE DATABASE samureye OWNER samureye_user;
GRANT ALL PRIVILEGES ON DATABASE samureye TO samureye_user;
GRANT ALL PRIVILEGES ON DATABASE samureye TO samureye;
EOF
    
    log "✅ Banco 'samureye' criado"
fi

# Criar extensões necessárias
sudo -u postgres psql -d samureye << 'EOF'
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

GRANT ALL ON SCHEMA public TO samureye_user;
GRANT ALL ON SCHEMA public TO samureye;
EOF

log "✅ Extensões configuradas"

# ============================================================================
# 9. TESTES DE CONECTIVIDADE
# ============================================================================

log "🧪 Executando testes de conectividade..."

# Teste 1: Conectividade local
echo -n "• Teste local (samureye_user): "
if PGPASSWORD="samureye_secure_2024" psql -h localhost -U samureye_user -d samureye -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OK${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
fi

echo -n "• Teste local (samureye): "
if PGPASSWORD="samureye_secure_2024" psql -h localhost -U samureye -d samureye -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OK${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
fi

# Teste 2: Conectividade via IP específico
echo -n "• Teste IP 172.24.1.153 (samureye_user): "
if PGPASSWORD="samureye_secure_2024" psql -h 172.24.1.153 -U samureye_user -d samureye -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OK${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
fi

# Teste 3: Porta TCP acessível
echo -n "• Porta 5432 acessível: "
if netstat -tlnp | grep -q ":5432.*LISTEN"; then
    echo -e "${GREEN}✅ LISTENING${NC}"
else
    echo -e "${RED}❌ NOT LISTENING${NC}"
fi

# Teste 4: Firewall
echo -n "• Firewall permite 5432: "
if ufw status | grep -q "5432.*ALLOW"; then
    echo -e "${GREEN}✅ ALLOWED${NC}"
else
    echo -e "${RED}❌ BLOCKED${NC}"
fi

# ============================================================================
# 10. RESUMO E PRÓXIMOS PASSOS
# ============================================================================

echo ""
log "🎉 CORREÇÃO CONCLUÍDA!"
echo "======================================"
echo ""
echo "✅ CONFIGURAÇÕES APLICADAS:"
echo "• PostgreSQL iniciado e habilitado"
echo "• listen_addresses = '*'"
echo "• pg_hba.conf com regras SamurEye"
echo "• Firewall liberando porta 5432"
echo "• Usuários: samureye_user e samureye"
echo "• Senha: samureye_secure_2024"
echo "• Banco: samureye com extensões"
echo ""
echo "🔧 COMANDOS PARA TESTAR NO vlxsam02:"
echo "nc -z 172.24.1.153 5432"
echo "PGPASSWORD=samureye_secure_2024 psql -h 172.24.1.153 -U samureye_user -d samureye -c 'SELECT version();'"
echo ""
echo "⚠️ SE AINDA HOUVER PROBLEMAS:"
echo "1. Reiniciar vlxsam03: sudo reboot"
echo "2. Verificar logs: tail -f /var/log/postgresql/postgresql-*.log"
echo "3. Testar manualmente no vlxsam02"
echo ""
log "Conectividade PostgreSQL configurada para SamurEye!"