#!/bin/bash
# Diagnóstico Completo - Autenticação Collector
# Autor: SamurEye Team
# Data: $(date +%Y-%m-%d)

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Função de log
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️ $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] ℹ️ $1${NC}"; }

# Configurações
POSTGRES_HOST="172.24.1.153"
POSTGRES_USER="samureye_user"
POSTGRES_DB="samureye"
API_URL="https://api.samureye.com.br"
COLLECTOR_ID="vlxsam04"
TOKEN_FROM_LOG="f47ce480-9b7acf84-2025-09-06-1757195483628"  # Token completo do log

echo ""
echo "🔍 DIAGNÓSTICO COMPLETO - AUTENTICAÇÃO COLLECTOR"
echo "=============================================="
echo ""

# ============================================================================
# 1. VERIFICAR CÓDIGO DOS ENDPOINTS NO SERVIDOR
# ============================================================================

log "📋 1. VERIFICANDO CÓDIGO DOS ENDPOINTS NO vlxsam02..."

if [ -f "/opt/samureye/SamurEye/server/routes.ts" ]; then
    log "🔍 Verificando endpoint /collector-api/journeys/pending..."
    
    # Verificar se as correções estão aplicadas
    if grep -q "or(.*eq(collectors.id, token" "/opt/samureye/SamurEye/server/routes.ts"; then
        log "✅ CORREÇÃO ENCONTRADA: Endpoint aceita token como collector ID"
    else
        error "❌ CORREÇÃO AUSENTE: Endpoint NÃO aceita token como collector ID"
        echo ""
        echo "🔧 Código atual do endpoint:"
        grep -A 20 "collector-api/journeys/pending" "/opt/samureye/SamurEye/server/routes.ts" || true
    fi
    
    # Verificar importação do 'or'
    if grep -q "import.*or.*from.*drizzle-orm" "/opt/samureye/SamurEye/server/routes.ts"; then
        log "✅ IMPORT OK: 'or' importado do drizzle-orm"
    else
        warn "⚠️ IMPORT MISSING: 'or' pode não estar importado"
        echo ""
        echo "🔍 Imports atuais do drizzle-orm:"
        grep "import.*drizzle-orm" "/opt/samureye/SamurEye/server/routes.ts" || true
    fi
else
    error "❌ Arquivo routes.ts não encontrado em /opt/samureye/SamurEye/server/"
fi

# ============================================================================
# 2. VERIFICAR BANCO DE DADOS
# ============================================================================

log "🗃️ 2. VERIFICANDO BANCO DE DADOS..."

# Verificar se PostgreSQL está acessível
if ! nc -z "$POSTGRES_HOST" 5432; then
    error "❌ PostgreSQL não acessível em $POSTGRES_HOST:5432"
fi

log "✅ PostgreSQL acessível"

# Verificar tabela collectors
log "🔍 Verificando tabela collectors..."
PGPASSWORD="samureye_secure_2024" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" << 'EOF'
\echo "=== ESTRUTURA DA TABELA COLLECTORS ==="
\d collectors;

\echo ""
\echo "=== TODOS OS COLLECTORS ==="
SELECT id, name, status, "enrollmentToken", "createdAt", "lastSeen" FROM collectors ORDER BY "createdAt" DESC;

\echo ""
\echo "=== COLLECTOR vlxsam04 ESPECÍFICO ==="
SELECT id, name, status, "enrollmentToken", "createdAt", "lastSeen" 
FROM collectors 
WHERE id = 'vlxsam04' OR name LIKE '%vlxsam04%';

\echo ""
\echo "=== BUSCAR POR TOKEN PARCIAL ==="
SELECT id, name, status, "enrollmentToken", "createdAt", "lastSeen" 
FROM collectors 
WHERE "enrollmentToken" LIKE '%f47ce480%';

EOF

# ============================================================================
# 3. TESTAR ENDPOINT DIRETAMENTE
# ============================================================================

log "🌐 3. TESTANDO ENDPOINT DIRETAMENTE..."

# Listar todos os collectors para pegar o token real
log "🔍 Buscando token real do vlxsam04..."
REAL_TOKEN=$(PGPASSWORD="samureye_secure_2024" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT \"enrollmentToken\" FROM collectors WHERE id = 'vlxsam04';" | xargs 2>/dev/null || echo "")

if [ -n "$REAL_TOKEN" ]; then
    log "✅ Token encontrado no banco: $REAL_TOKEN"
    
    # Testar com token do banco
    log "🔍 Testando endpoint com token do banco..."
    curl -v "$API_URL/collector-api/journeys/pending?collector_id=vlxsam04&token=$REAL_TOKEN" 2>&1 || true
    
else
    warn "⚠️ Token não encontrado no banco para vlxsam04"
fi

# Testar também com o token do log (parcial)
log "🔍 Testando endpoint com token do log..."
curl -v "$API_URL/collector-api/journeys/pending?collector_id=vlxsam04&token=$TOKEN_FROM_LOG" 2>&1 || true

# Testar com collector_id como token (nossa correção)
log "🔍 Testando endpoint com collector_id como token..."
curl -v "$API_URL/collector-api/journeys/pending?collector_id=vlxsam04&token=vlxsam04" 2>&1 || true

# ============================================================================
# 4. VERIFICAR LOGS DO SERVIDOR
# ============================================================================

log "📋 4. VERIFICANDO LOGS DO SERVIDOR..."

if [ -f "/var/log/samureye/app.log" ]; then
    log "🔍 Últimas linhas do log da aplicação:"
    tail -20 /var/log/samureye/app.log | grep -E "(collector|token|401|DEBUG)" || true
fi

if systemctl is-active --quiet samureye-app; then
    log "🔍 Logs do systemd (últimos 10):"
    journalctl -u samureye-app -n 10 --no-pager | grep -E "(collector|token|401|DEBUG)" || true
fi

# ============================================================================
# 5. VERIFICAR SE SERVIDOR ESTÁ USANDO CÓDIGO ATUALIZADO
# ============================================================================

log "🔄 5. VERIFICANDO SE SERVIDOR USA CÓDIGO ATUALIZADO..."

if systemctl is-active --quiet samureye-app; then
    log "✅ Serviço samureye-app está rodando"
    
    # Verificar quando foi a última modificação do routes.ts
    if [ -f "/opt/samureye/SamurEye/server/routes.ts" ]; then
        ROUTES_MODIFIED=$(stat -c %Y "/opt/samureye/SamurEye/server/routes.ts")
        CURRENT_TIME=$(date +%s)
        AGE=$((CURRENT_TIME - ROUTES_MODIFIED))
        
        log "📅 routes.ts modificado há $AGE segundos"
        
        if [ $AGE -lt 300 ]; then  # Menos de 5 minutos
            log "✅ Arquivo foi modificado recentemente"
        else
            warn "⚠️ Arquivo pode estar desatualizado"
        fi
    fi
    
    # Verificar se o processo foi reiniciado recentemente
    SERVICE_START=$(systemctl show samureye-app --property=ActiveEnterTimestamp --value)
    log "🕒 Serviço iniciado em: $SERVICE_START"
    
else
    error "❌ Serviço samureye-app não está rodando!"
fi

# ============================================================================
# 6. TESTE MANUAL DO CÓDIGO JAVASCRIPT
# ============================================================================

log "🔧 6. TESTE MANUAL DO CÓDIGO JAVASCRIPT..."

# Criar script de teste
cat > /tmp/test_token_validation.js << 'EOF'
const { Pool } = require('pg');

const pool = new Pool({
    connectionString: 'postgresql://samureye_user:samureye_secure_2024@172.24.1.153:5432/samureye'
});

async function testTokenValidation() {
    try {
        console.log("🔍 Testando validação de token...");
        
        const token = 'vlxsam04';  // Usando collector_id como token
        const collector_id = 'vlxsam04';
        
        // Teste 1: Busca por enrollment_token
        console.log("📋 Teste 1: Busca por enrollmentToken...");
        const result1 = await pool.query(
            'SELECT id, name, "enrollmentToken" FROM collectors WHERE "enrollmentToken" = $1',
            [token]
        );
        console.log("Resultado 1:", result1.rows);
        
        // Teste 2: Busca por ID
        console.log("📋 Teste 2: Busca por ID...");
        const result2 = await pool.query(
            'SELECT id, name, "enrollmentToken" FROM collectors WHERE id = $1',
            [token]
        );
        console.log("Resultado 2:", result2.rows);
        
        // Teste 3: Busca com OR (nossa correção)
        console.log("📋 Teste 3: Busca com OR...");
        const result3 = await pool.query(
            'SELECT id, name, "enrollmentToken" FROM collectors WHERE "enrollmentToken" = $1 OR id = $1',
            [token]
        );
        console.log("Resultado 3:", result3.rows);
        
    } catch (error) {
        console.error("❌ Erro:", error.message);
    } finally {
        await pool.end();
    }
}

testTokenValidation();
EOF

# Executar teste
log "🔍 Executando teste de validação..."
cd /opt/samureye/SamurEye
node /tmp/test_token_validation.js 2>&1 || true

echo ""
echo "🎯 RESUMO DO DIAGNÓSTICO:"
echo "========================"
echo "1. Verificar se correções estão no código"
echo "2. Verificar dados no banco de dados"  
echo "3. Testar endpoints diretamente"
echo "4. Verificar logs do servidor"
echo "5. Confirmar se código está sendo usado"
echo "6. Teste manual da lógica de validação"
echo ""
echo "📋 Analise os resultados acima para identificar o problema!"

# Cleanup
rm -f /tmp/test_token_validation.js