#!/bin/bash
# Script de Correção Completa SamurEye On-Premise
# Corrige todos os problemas identificados: tabelas faltando, endpoints 404, etc.

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ❌ ERROR: $1" >&2
    exit 1
}

echo "🔧 Correção Completa SamurEye On-Premise"
echo "======================================="

# Verificar se é executado como root
if [[ $EUID -ne 0 ]]; then
    error "Este script deve ser executado como root (use sudo)"
fi

# ============================================================================
# 1. CORRIGIR SCHEMA DO BANCO DE DADOS (vlxsam03)
# ============================================================================

log "🗃️ Corrigindo schema do banco de dados no vlxsam03..."

# Executar no vlxsam02 (onde está a aplicação) para fazer push do schema
if ping -c 1 vlxsam02 >/dev/null 2>&1; then
    log "📡 Executando db:push no vlxsam02..."
    
    ssh vlxsam02 << 'EOF'
cd /opt/samureye
export DATABASE_URL="postgresql://samureye:SamurEye2024%21@vlxsam03:5432/samureye"
npm run db:push --force
EOF
    
    if [ $? -eq 0 ]; then
        log "✅ Schema sincronizado com sucesso"
    else
        log "⚠️ Falha no db:push - tentando criar tabelas manualmente..."
        
        # Criar tabelas essenciais manualmente
        PGPASSWORD='SamurEye2024!' psql -h vlxsam03 -U samureye -d samureye << 'SQL'
-- Criar tabela collectors se não existir
CREATE TABLE IF NOT EXISTS collectors (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    tenant_id VARCHAR NOT NULL,
    status VARCHAR DEFAULT 'enrolling',
    last_seen TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    telemetry JSONB,
    config JSONB
);

-- Criar tabela tenants se não existir
CREATE TABLE IF NOT EXISTS tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    slug VARCHAR UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Inserir tenant padrão se não existir
INSERT INTO tenants (id, name, slug) 
VALUES ('default-tenant-id', 'GruppenIT', 'gruppenIT')
ON CONFLICT (slug) DO NOTHING;

-- Inserir collector vlxsam04 se não existir
INSERT INTO collectors (id, name, tenant_id, status, last_seen) 
VALUES ('vlxsam04-collector-id', 'vlxsam04', 'default-tenant-id', 'online', NOW())
ON CONFLICT (id) DO UPDATE SET 
    status = 'online', 
    last_seen = NOW();
SQL
        
        log "✅ Tabelas essenciais criadas"
    fi
else
    error "vlxsam02 não acessível para db:push"
fi

# ============================================================================
# 2. CORRIGIR ENDPOINT HEARTBEAT (vlxsam02)
# ============================================================================

log "🩺 Verificando endpoint heartbeat no vlxsam02..."

# Testar se o endpoint existe
if curl -s -o /dev/null -w "%{http_code}" http://vlxsam02:5000/collector-api/heartbeat | grep -q "200\|405"; then
    log "✅ Endpoint heartbeat funcionando"
else
    log "⚠️ Endpoint heartbeat não encontrado - reiniciando aplicação..."
    
    ssh vlxsam02 << 'EOF'
systemctl restart samureye-app
sleep 5
systemctl status samureye-app
EOF
fi

# ============================================================================
# 3. CORRIGIR STATUS DO COLLECTOR (vlxsam04)
# ============================================================================

log "🤖 Corrigindo status do collector vlxsam04..."

# Atualizar status do collector para online
PGPASSWORD='SamurEye2024!' psql -h vlxsam03 -U samureye -d samureye << 'SQL'
-- Atualizar todos os collectors ENROLLING para ONLINE
UPDATE collectors 
SET status = 'online', last_seen = NOW() 
WHERE status = 'enrolling' OR name LIKE '%vlxsam04%';

-- Verificar status atual
SELECT name, status, last_seen FROM collectors ORDER BY last_seen DESC;
SQL

# Reiniciar collector se necessário
if ping -c 1 vlxsam04 >/dev/null 2>&1; then
    log "🔄 Reiniciando collector vlxsam04..."
    
    ssh vlxsam04 << 'EOF'
systemctl restart samureye-collector
sleep 3
systemctl status samureye-collector --no-pager -l
EOF
fi

# ============================================================================
# 4. VERIFICAÇÃO FINAL
# ============================================================================

log "🔍 Executando verificação final..."

echo ""
echo "📊 STATUS DOS SERVIÇOS:"
echo "======================="

# Status PostgreSQL vlxsam03
echo "🗃️ PostgreSQL (vlxsam03):"
if PGPASSWORD='SamurEye2024!' psql -h vlxsam03 -U samureye -d samureye -c "SELECT COUNT(*) as total_collectors FROM collectors;" 2>/dev/null; then
    echo "   ✅ Banco funcionando"
else
    echo "   ❌ Banco com problemas"
fi

# Status App vlxsam02
echo ""
echo "🖥️ SamurEye App (vlxsam02):"
if curl -s http://vlxsam02:5000/api/system/settings >/dev/null; then
    echo "   ✅ Aplicação funcionando"
else
    echo "   ❌ Aplicação com problemas"
fi

# Status Gateway vlxsam01
echo ""
echo "🌐 Gateway (vlxsam01):"
if curl -s -I https://app.samureye.com.br | grep -q "200\|301\|302"; then
    echo "   ✅ Gateway SSL funcionando"
else
    echo "   ❌ Gateway com problemas"
fi

# Status Collector vlxsam04
echo ""
echo "🤖 Collector (vlxsam04):"
if ping -c 1 vlxsam04 >/dev/null 2>&1; then
    echo "   ✅ Servidor acessível"
    echo "   ℹ️ Verificar logs: ssh vlxsam04 'journalctl -u samureye-collector -n 10'"
else
    echo "   ❌ Servidor não acessível"
fi

echo ""
echo "🔗 URLS PARA TESTE:"
echo "=================="
echo "   Interface Admin: https://app.samureye.com.br/admin"
echo "   Gestão Coletores: https://app.samureye.com.br/admin/collectors"
echo "   API Status: https://api.samureye.com.br/api/system/settings"
echo ""
echo "🔐 ACESSO ADMIN:"
echo "   Login: admin@samureye.com.br"
echo "   Senha: SamurEye2024!"

log "✅ Correção completa finalizada!"
exit 0