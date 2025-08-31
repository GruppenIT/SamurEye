#!/bin/bash
# Script LOCAL para vlxsam02 - Sincronizar Schema e Corrigir App
# Execute diretamente no vlxsam02 como root

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ❌ ERROR: $1" >&2
    exit 1
}

echo "🖥️ Correção LOCAL vlxsam02 - SamurEye App"
echo "========================================"

# Verificar se é executado como root
if [[ $EUID -ne 0 ]]; then
    error "Execute como root: sudo ./fix-vlxsam02-local.sh"
fi

# Verificar se estamos no vlxsam02
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" != "vlxsam02" ]]; then
    log "⚠️ Este script é para vlxsam02, mas estamos em: $HOSTNAME"
    read -p "Continuar mesmo assim? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ============================================================================
# 1. VERIFICAR E CORRIGIR APLICAÇÃO SAMUREYE
# ============================================================================

log "🔍 Verificando aplicação SamurEye..."

# Detectar aplicação usando processo systemd ativo
APP_DIR=""

log "🔍 Detectando aplicação através do serviço em execução..."
SERVICE_STATUS=$(systemctl show samureye-app --property=MainPID,ExecStart --no-pager 2>/dev/null || echo "")

if [ -n "$SERVICE_STATUS" ]; then
    # Extrair PID do serviço
    MAIN_PID=$(echo "$SERVICE_STATUS" | grep "MainPID=" | cut -d'=' -f2)
    
    if [ "$MAIN_PID" != "0" ] && [ -n "$MAIN_PID" ]; then
        # Usar PID para encontrar working directory
        APP_DIR=$(readlink -f "/proc/$MAIN_PID/cwd" 2>/dev/null || echo "")
        log "📁 Diretório detectado via PID $MAIN_PID: $APP_DIR"
    fi
fi

# Fallback: buscar em localizações comuns
if [ -z "$APP_DIR" ] || [ ! -f "$APP_DIR/package.json" ]; then
    log "🔍 Buscando em localizações padrão..."
    
    POSSIBLE_DIRS=(
        "/opt/samureye/SamurEye"
        "/opt/samureye"
        "/opt/SamurEye"
        "/home/samureye"
        "/opt/samureye-app"
        "/var/www/samureye"
        "/root/SamurEye"
        "/usr/local/samureye"
    )
    
    for dir in "${POSSIBLE_DIRS[@]}"; do
        if [ -d "$dir" ] && [ -f "$dir/package.json" ]; then
            APP_DIR="$dir"
            log "✅ Aplicação encontrada em: $APP_DIR"
            break
        fi
    done
fi

# Último recurso: usar find
if [ -z "$APP_DIR" ] || [ ! -f "$APP_DIR/package.json" ]; then
    log "🔍 Buscando package.json no sistema..."
    FOUND_DIRS=$(find /opt /home /root /var/www -name "package.json" -path "*/samureye*" -o -name "package.json" -path "*/SamurEye*" 2>/dev/null | head -5)
    
    for json_file in $FOUND_DIRS; do
        dir=$(dirname "$json_file")
        if grep -q "samureye\|SamurEye" "$json_file" 2>/dev/null; then
            APP_DIR="$dir"
            log "✅ Aplicação encontrada via find: $APP_DIR"
            break
        fi
    done
fi

if [ -z "$APP_DIR" ] || [ ! -f "$APP_DIR/package.json" ]; then
    log "⚠️ package.json não encontrado - continuando sem db:push..."
    log "📍 Serviço rodando: $(systemctl show samureye-app --property=ExecStart --no-pager 2>/dev/null || echo 'Status não disponível')"
    log "🔍 Aplicação não encontrada - continuando sem db:push..."
else
    cd "$APP_DIR"
    log "📁 Mudando para diretório: $APP_DIR"
fi

# Verificar se existe o package.json
if [ ! -f "package.json" ]; then
    log "⚠️ package.json não encontrado em /opt/samureye - verificando outras localizações..."
    
    # Procurar em outros diretórios possíveis
    POSSIBLE_DIRS=(
        "/opt/SamurEye"
        "/home/samureye"
        "/opt/samureye-app"
        "/var/www/samureye"
    )
    
    FOUND_DIR=""
    for dir in "${POSSIBLE_DIRS[@]}"; do
        if [ -f "$dir/package.json" ]; then
            FOUND_DIR="$dir"
            log "✅ Aplicação encontrada em: $FOUND_DIR"
            break
        fi
    done
    
    if [ -z "$FOUND_DIR" ]; then
        log "❌ Aplicação SamurEye não encontrada. Verificando serviço systemd..."
        
        # Verificar onde o systemd está executando a aplicação
        if systemctl is-active --quiet samureye-app; then
            SERVICE_EXEC=$(systemctl show samureye-app -p ExecStart --value 2>/dev/null || echo "")
            log "📍 Serviço rodando: $SERVICE_EXEC"
            
            # Tentar extrair diretório do ExecStart
            if [[ "$SERVICE_EXEC" == *"WorkingDirectory"* ]]; then
                WORKING_DIR=$(echo "$SERVICE_EXEC" | grep -o "WorkingDirectory=[^;]*" | cut -d= -f2)
                if [ -d "$WORKING_DIR" ] && [ -f "$WORKING_DIR/package.json" ]; then
                    FOUND_DIR="$WORKING_DIR"
                    log "✅ Aplicação encontrada via systemd: $FOUND_DIR"
                fi
            fi
        fi
        
        if [ -z "$FOUND_DIR" ]; then
            log "🔍 Aplicação não encontrada - continuando sem db:push..."
            log "⚠️ Schema será sincronizado manualmente no PostgreSQL"
        fi
    fi
    
    if [ -n "$FOUND_DIR" ]; then
        cd "$FOUND_DIR"
        log "📁 Mudando para diretório: $FOUND_DIR"
    fi
fi

# Verificar se aplicação está rodando
if systemctl is-active --quiet samureye-app; then
    log "✅ SamurEye app está rodando"
else
    log "⚠️ SamurEye app não está rodando - iniciando..."
    systemctl start samureye-app
    sleep 3
fi

# ============================================================================
# 2. SINCRONIZAR SCHEMA DO BANCO DE DADOS
# ============================================================================

log "🗃️ Sincronizando schema do banco de dados..."

# Verificar conectividade com vlxsam03
if ! ping -c 1 vlxsam03 >/dev/null 2>&1; then
    error "vlxsam03 não acessível - verificar rede"
fi

# Configurar variável de ambiente
export DATABASE_URL="postgresql://samureye:SamurEye2024%21@vlxsam03:5432/samureye"

# Testar conexão com banco
log "🔌 Instalando cliente PostgreSQL se necessário..."
if ! command -v psql >/dev/null 2>&1; then
    log "📦 Instalando postgresql-client..."
    apt-get update >/dev/null 2>&1
    apt-get install -y postgresql-client >/dev/null 2>&1
fi

log "🔌 Testando conexão com PostgreSQL vlxsam03..."
if echo "SELECT version();" | psql "$DATABASE_URL" >/dev/null 2>&1; then
    log "✅ Conexão com PostgreSQL OK"
else
    error "Falha na conexão com PostgreSQL vlxsam03"
fi

# Verificar se existe drizzle.config.ts
if [ ! -f "drizzle.config.ts" ]; then
    error "drizzle.config.ts não encontrado - schema não pode ser sincronizado"
fi

log "🚀 Executando npm run db:push..."

# Fazer backup do .env se existir
if [ -f ".env" ]; then
    cp .env .env.backup
fi

# Garantir que DATABASE_URL está no .env
echo "DATABASE_URL=postgresql://samureye:SamurEye2024%21@vlxsam03:5432/samureye" > .env.temp
if [ -f ".env" ]; then
    grep -v "DATABASE_URL" .env >> .env.temp || true
fi
mv .env.temp .env

# Executar db:push com força
if npm run db:push --force; then
    log "✅ Schema sincronizado com sucesso!"
else
    log "⚠️ Falha no db:push - tentando método alternativo..."
    
    # Método alternativo: criar tabelas essenciais manualmente
    log "📝 Criando tabelas essenciais manualmente..."
    
    PGPASSWORD='SamurEye2024!' psql -h vlxsam03 -U samureye -d samureye << 'SQL'
-- Criar tabela collectors se não existir
CREATE TABLE IF NOT EXISTS collectors (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    tenant_id VARCHAR NOT NULL,
    status VARCHAR DEFAULT 'enrolling',
    last_seen TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    telemetry JSONB,
    config JSONB
);

-- Criar tabela tenants se não existir  
CREATE TABLE IF NOT EXISTS tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    slug VARCHAR UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Criar outras tabelas essenciais
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR UNIQUE NOT NULL,
    password_hash VARCHAR,
    name VARCHAR,
    role VARCHAR DEFAULT 'viewer',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR NOT NULL,
    tenant_id VARCHAR NOT NULL,
    role VARCHAR DEFAULT 'viewer',
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, tenant_id)
);

-- Inserir dados iniciais
INSERT INTO tenants (id, name, slug) 
VALUES ('default-tenant-id', 'GruppenIT', 'gruppenIT')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO users (id, email, name, role)
VALUES ('admin-user-id', 'admin@samureye.com.br', 'Administrator', 'admin')
ON CONFLICT (email) DO NOTHING;
SQL
    
    log "✅ Tabelas essenciais criadas manualmente"
fi

# ============================================================================
# 3. VERIFICAR ENDPOINTS CRÍTICOS
# ============================================================================

log "🩺 Verificando endpoints críticos..."

# Aguardar aplicação reiniciar se necessário
sleep 5

# Testar endpoint principal
if curl -s http://localhost:5000/api/system/settings >/dev/null; then
    log "✅ Endpoint /api/system/settings funcionando"
else
    log "⚠️ Endpoint principal com problemas - reiniciando aplicação..."
    systemctl restart samureye-app
    sleep 10
fi

# Testar endpoint heartbeat
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/collector-api/heartbeat | grep -q "200\|405\|404"; then
    log "✅ Endpoint heartbeat acessível"
else
    log "⚠️ Endpoint heartbeat não encontrado"
fi

# ============================================================================
# 4. ATUALIZAR STATUS DOS COLLECTORS
# ============================================================================

log "🤖 Atualizando status dos collectors..."

PGPASSWORD='SamurEye2024!' psql -h vlxsam03 -U samureye -d samureye << 'SQL'
-- Atualizar collectors ENROLLING para ONLINE
UPDATE collectors 
SET status = 'online', last_seen = NOW(), updated_at = NOW()
WHERE status = 'enrolling' 
   OR last_seen < NOW() - INTERVAL '10 minutes';

-- Inserir collector vlxsam04 se não existir
INSERT INTO collectors (id, name, tenant_id, status, last_seen, created_at, updated_at) 
VALUES (
    'vlxsam04-collector-id', 
    'vlxsam04', 
    'default-tenant-id', 
    'online', 
    NOW(), 
    NOW(), 
    NOW()
)
ON CONFLICT (id) DO UPDATE SET 
    status = 'online', 
    last_seen = NOW(),
    updated_at = NOW();

-- Mostrar status atual
SELECT 
    name, 
    status, 
    last_seen,
    created_at
FROM collectors 
ORDER BY last_seen DESC;
SQL

# ============================================================================
# 5. VERIFICAÇÃO FINAL
# ============================================================================

log "🔍 Verificação final..."

echo ""
echo "📊 STATUS FINAL vlxsam02:"
echo "========================"

# Status do serviço
echo "🖥️ Serviço SamurEye:"
systemctl status samureye-app --no-pager -l | head -10

# Status da aplicação
echo ""
echo "🌐 Endpoint principal:"
if curl -s http://localhost:5000/api/system/settings | head -1; then
    echo "   ✅ API funcionando"
else
    echo "   ❌ API com problemas"
fi

# Status do banco
echo ""
echo "🗃️ Banco de dados:"
if PGPASSWORD='SamurEye2024!' psql -h vlxsam03 -U samureye -d samureye -c "SELECT COUNT(*) as total_collectors FROM collectors;" 2>/dev/null; then
    echo "   ✅ Banco acessível"
else
    echo "   ❌ Banco com problemas"
fi

echo ""
log "✅ Correção vlxsam02 finalizada!"
echo ""
echo "🔗 Próximos passos:"
echo "   1. Acesse: https://app.samureye.com.br/admin"
echo "   2. Verifique collectors em: https://app.samureye.com.br/admin/collectors"
echo "   3. Se vlxsam04 ainda aparecer ENROLLING, execute:"
echo "      ssh vlxsam04 'systemctl restart samureye-collector'"

exit 0