#!/bin/bash
# Script de instalação PostgreSQL vlxsam03 para SamurEye On-Premise
# Versão: 3.0.0 - Inclui correções para collectors ENROLLING

set -e

# Funções auxiliares
log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

warn() {
    echo "[$(date '+%H:%M:%S')] ⚠️ WARNING: $1" >&2
}

error() {
    echo "[$(date '+%H:%M:%S')] ❌ ERROR: $1" >&2
    exit 1
}

echo "🗃️ Instalação PostgreSQL vlxsam03 - SamurEye On-Premise"
echo "======================================================="

# Verificar se é Ubuntu/Debian
if ! command -v apt-get >/dev/null 2>&1; then
    error "Este script foi desenvolvido para Ubuntu/Debian"
fi

# Verificar se é executado como root
if [[ $EUID -ne 0 ]]; then
    error "Este script deve ser executado como root (use sudo)"
fi

# ============================================================================
# 1. INSTALAÇÃO DO POSTGRESQL
# ============================================================================

log "📦 Instalando PostgreSQL 16..."

# Atualizar repositórios
apt-get update

# Instalar dependências
apt-get install -y wget ca-certificates gnupg lsb-release

# Adicionar repositório oficial PostgreSQL
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Atualizar e instalar PostgreSQL 16
apt-get update
apt-get install -y postgresql-16 postgresql-client-16 postgresql-contrib-16

log "✅ PostgreSQL 16 instalado"

# ============================================================================
# 2. CONFIGURAÇÃO DO POSTGRESQL
# ============================================================================

log "🔧 Configurando PostgreSQL..."

# Iniciar e habilitar PostgreSQL
systemctl enable postgresql
systemctl start postgresql

# Verificar se PostgreSQL está rodando
if ! systemctl is-active postgresql >/dev/null 2>&1; then
    error "Falha ao iniciar PostgreSQL"
fi

log "✅ PostgreSQL iniciado com sucesso"

# Configurar PostgreSQL para aceitar conexões dos outros servidores
PG_VERSION="16"
PG_CONFIG_DIR="/etc/postgresql/$PG_VERSION/main"

# Backup das configurações originais
cp "$PG_CONFIG_DIR/postgresql.conf" "$PG_CONFIG_DIR/postgresql.conf.backup"
cp "$PG_CONFIG_DIR/pg_hba.conf" "$PG_CONFIG_DIR/pg_hba.conf.backup"

log "📝 Configurando postgresql.conf..."

# Configurar postgresql.conf
cat >> "$PG_CONFIG_DIR/postgresql.conf" << 'EOF'

# SamurEye Configuration
listen_addresses = '*'
port = 5432
max_connections = 200
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 4GB
EOF

log "📝 Configurando pg_hba.conf..."

# Configurar pg_hba.conf para permitir conexões dos servidores SamurEye
cat >> "$PG_CONFIG_DIR/pg_hba.conf" << 'EOF'

# SamurEye On-Premise Access
# vlxsam01 - Gateway
host    samureye        samureye        192.168.100.151/32      md5
# vlxsam02 - Application Server  
host    samureye        samureye        192.168.100.152/32      md5
# vlxsam03 - Database (local)
host    samureye        samureye        127.0.0.1/32            md5
host    samureye        samureye        192.168.100.153/32      md5
# vlxsam04 - Collector
host    samureye        samureye        192.168.100.154/32      md5
# Rede local SamurEye (backup)
host    samureye        samureye        192.168.100.0/24        md5
EOF

# Reiniciar PostgreSQL para aplicar configurações
systemctl restart postgresql

log "✅ PostgreSQL configurado para SamurEye"

# ============================================================================
# 3. CONFIGURAÇÃO DO BANCO SAMUREYE
# ============================================================================

log "🗃️ Configurando banco SamurEye..."

# Criar usuário samureye
sudo -u postgres psql << 'EOF'
-- Remover usuário e banco se existirem
DROP DATABASE IF EXISTS samureye;
DROP USER IF EXISTS samureye;

-- Criar usuário
CREATE USER samureye WITH ENCRYPTED PASSWORD 'SamurEye2024!';

-- Criar banco
CREATE DATABASE samureye OWNER samureye;

-- Conceder privilégios
GRANT ALL PRIVILEGES ON DATABASE samureye TO samureye;
ALTER USER samureye CREATEDB;

-- Conectar ao banco samureye
\c samureye

-- Criar extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Conceder privilégios nas extensões
GRANT ALL ON SCHEMA public TO samureye;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO samureye;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO samureye;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO samureye;
EOF

log "✅ Banco SamurEye criado com sucesso"

# ============================================================================
# 4. TESTE DE CONECTIVIDADE
# ============================================================================

log "🔍 Testando conectividade..."

# Testar conexão local
if sudo -u postgres psql -d samureye -c "SELECT version();" >/dev/null 2>&1; then
    log "✅ Conexão local funcionando"
else
    error "Falha na conexão local"
fi

# Testar com usuário samureye
export PGPASSWORD='SamurEye2024!'
if psql -h localhost -U samureye -d samureye -c "SELECT 1;" >/dev/null 2>&1; then
    log "✅ Autenticação do usuário samureye funcionando"
else
    error "Falha na autenticação do usuário samureye"
fi

# ============================================================================
# 5. SCRIPTS DE CORREÇÃO PARA COLLECTORS
# ============================================================================

log "🔧 Configurando correções para collectors ENROLLING..."

# Script para corrigir collectors presos em ENROLLING
cat > /usr/local/bin/fix-enrolling-collectors.sh << 'EOF'
#!/bin/bash
# Script para corrigir collectors presos em status ENROLLING

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

log "🔧 Corrigindo collectors em status ENROLLING..."

# Atualizar collectors antigos para online
UPDATED_COUNT=$(sudo -u postgres psql -d samureye -t -c "
UPDATE collectors 
SET status = 'online', last_seen = NOW() 
WHERE status = 'enrolling' 
  AND created_at < NOW() - INTERVAL '5 minutes'
RETURNING id;
" 2>/dev/null | wc -l | tr -d ' ')

if [[ $UPDATED_COUNT -gt 0 ]]; then
    log "✅ $UPDATED_COUNT collectors atualizados de ENROLLING para ONLINE"
else
    log "ℹ️ Nenhum collector antigo em status ENROLLING encontrado"
fi

# Mostrar status atual
ONLINE_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE status = 'online';" 2>/dev/null | tr -d ' ')
ENROLLING_COUNT=$(sudo -u postgres psql -d samureye -t -c "SELECT COUNT(*) FROM collectors WHERE status = 'enrolling';" 2>/dev/null | tr -d ' ')

log "📊 Status atual: $ONLINE_COUNT online, $ENROLLING_COUNT enrolling"
EOF

chmod +x /usr/local/bin/fix-enrolling-collectors.sh

log "✅ Script de correção criado"

# ============================================================================
# 6. CRON JOB PARA LIMPEZA AUTOMÁTICA
# ============================================================================

log "⏰ Configurando limpeza automática..."

# Cron job para corrigir collectors ENROLLING automaticamente a cada 10 minutos
cat > /etc/cron.d/samureye-cleanup << 'EOF'
# SamurEye - Correção automática de collectors ENROLLING
*/10 * * * * root /usr/local/bin/fix-enrolling-collectors.sh >/dev/null 2>&1
EOF

log "✅ Cron job configurado para limpeza automática"

# ============================================================================
# 7. FIREWALL E SEGURANÇA
# ============================================================================

log "🔒 Configurando firewall..."

# Configurar ufw se estiver instalado
if command -v ufw >/dev/null 2>&1; then
    # Permitir PostgreSQL apenas da rede SamurEye
    ufw allow from 192.168.100.0/24 to any port 5432 comment "SamurEye PostgreSQL"
    
    # Permitir SSH
    ufw allow ssh
    
    log "✅ Firewall configurado"
else
    log "⚠️ UFW não instalado - configure firewall manualmente"
fi

# ============================================================================
# 8. MONITORAMENTO E LOGS
# ============================================================================

log "📊 Configurando monitoramento..."

# Script de status do PostgreSQL
cat > /usr/local/bin/postgres-status.sh << 'EOF'
#!/bin/bash
echo "🗃️ Status PostgreSQL SamurEye"
echo "============================="
echo ""
echo "Serviço PostgreSQL:"
systemctl status postgresql --no-pager -l
echo ""
echo "Conexões ativas:"
sudo -u postgres psql -d samureye -c "SELECT count(*) as conexoes_ativas FROM pg_stat_activity WHERE state = 'active';"
echo ""
echo "Status dos collectors:"
sudo -u postgres psql -d samureye -c "SELECT status, COUNT(*) FROM collectors GROUP BY status ORDER BY status;"
echo ""
echo "Últimos collectors registrados:"
sudo -u postgres psql -d samureye -c "SELECT name, status, created_at, last_seen FROM collectors ORDER BY created_at DESC LIMIT 5;"
EOF

chmod +x /usr/local/bin/postgres-status.sh

log "✅ Scripts de monitoramento criados"

# ============================================================================
# 9. FINALIZAÇÃO
# ============================================================================

log "🎯 Executando correção inicial..."
/usr/local/bin/fix-enrolling-collectors.sh

echo ""
log "✅ PostgreSQL vlxsam03 instalado e configurado com sucesso!"
echo ""
echo "📋 INFORMAÇÕES DA INSTALAÇÃO:"
echo "   Servidor: vlxsam03 ($(hostname -I | awk '{print $1}'))"
echo "   Porta: 5432"
echo "   Banco: samureye"
echo "   Usuário: samureye"
echo "   Senha: SamurEye2024!"
echo ""
echo "🔗 STRING DE CONEXÃO PARA APPS:"
echo "   DATABASE_URL=postgresql://samureye:SamurEye2024%21@vlxsam03:5432/samureye"
echo ""
echo "🔧 COMANDOS ÚTEIS:"
echo "   systemctl status postgresql     # Status do serviço"
echo "   /usr/local/bin/postgres-status.sh  # Status completo"
echo "   /usr/local/bin/fix-enrolling-collectors.sh  # Corrigir ENROLLING"
echo ""
echo "📊 VERIFICAR COLETORES NA INTERFACE:"
echo "   1. https://app.samureye.com.br/admin"
echo "   2. Login: admin@samureye.com.br / SamurEye2024!"
echo "   3. Aba: 'Gestão de Coletores' > 'Ver Coletores'"
echo ""
echo "🔍 TESTE COMPLETO DO BANCO:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/test-collector-database.sh | sudo bash"

exit 0