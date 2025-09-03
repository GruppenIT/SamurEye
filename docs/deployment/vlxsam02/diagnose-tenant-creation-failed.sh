#!/bin/bash

# ============================================================================
# SCRIPT DIAGNÓSTICO - FALHA CRIAÇÃO TENANT vlxsam02  
# ============================================================================
# Investiga problema "Failed to create tenant" após hard reset
# Verifica schema, conectividade e configurações necessárias
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

echo ""
echo "🔍 DIAGNÓSTICO - FALHA CRIAÇÃO TENANT"
echo "====================================="
echo "Sistema: vlxsam02 ($(hostname))"
echo "Problema: 500 - Failed to create tenant"
echo ""

# ============================================================================
# 1. STATUS BÁSICO DA APLICAÇÃO
# ============================================================================

log "📊 Verificando status da aplicação..."

# Verificar se aplicação está rodando
if systemctl is-active --quiet samureye-app 2>/dev/null; then
    log "✅ Serviço samureye-app está ATIVO"
else
    error "❌ Serviço samureye-app está INATIVO"
    echo "   • Execute: systemctl status samureye-app"
    echo "   • Execute: systemctl start samureye-app"
fi

# Verificar se aplicação responde
if curl -s --connect-timeout 5 http://localhost:5000/api/health >/dev/null 2>&1; then
    log "✅ Aplicação responde na porta 5000"
else
    error "❌ Aplicação não responde na porta 5000"
    echo "   • Verifique logs: journalctl -u samureye-app -f"
fi

# ============================================================================
# 2. CONECTIVIDADE COM BANCO DE DADOS
# ============================================================================

log "🗄️ Verificando conectividade com PostgreSQL..."

# Verificar se PostgreSQL está rodando no vlxsam03
if timeout 5 bash -c "</dev/tcp/192.168.100.153/5432" >/dev/null 2>&1; then
    log "✅ PostgreSQL vlxsam03:5432 acessível"
else
    error "❌ PostgreSQL vlxsam03:5432 inacessível"
    echo "   • Verifique se vlxsam03 está online"
    echo "   • Verifique firewall no vlxsam03"
    echo "   • Execute no vlxsam03: systemctl status postgresql"
fi

# Testar credenciais de banco
DB_HOST="192.168.100.153"
DB_PORT="5432"
DB_NAME="samureye"
DB_USER="samureye"
DB_PASS="samureye123"

if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
    log "✅ Credenciais de banco funcionando"
else
    error "❌ Falha nas credenciais de banco"
    echo "   • Host: $DB_HOST"
    echo "   • Port: $DB_PORT"
    echo "   • Database: $DB_NAME"
    echo "   • User: $DB_USER"
    echo "   • Verifique se usuário/database existem no vlxsam03"
fi

# ============================================================================
# 3. VERIFICAÇÃO DO SCHEMA DE TABELAS
# ============================================================================

log "📋 Verificando schema de tabelas necessárias..."

# Lista de tabelas obrigatórias
REQUIRED_TABLES=(
    "users"
    "tenants" 
    "tenant_users"
    "collectors"
    "journeys"
    "credentials"
    "sessions"
    "system_settings"
    "tenant_user_auth"
)

info "Tabelas existentes no banco:"
EXISTING_TABLES=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public';" 2>/dev/null | tr -d ' ')

for table in "${REQUIRED_TABLES[@]}"; do
    if echo "$EXISTING_TABLES" | grep -q "^$table$"; then
        log "   ✅ Tabela '$table' existe"
    else
        error "   ❌ Tabela '$table' AUSENTE"
    fi
done

# Verificar estrutura específica da tabela tenants
log "🔍 Verificando estrutura da tabela 'tenants'..."
if echo "$EXISTING_TABLES" | grep -q "^tenants$"; then
    TENANT_COLUMNS=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'tenants';" 2>/dev/null | tr -d ' ')
    
    REQUIRED_COLUMNS=("id" "name" "slug" "created_at" "updated_at")
    
    for column in "${REQUIRED_COLUMNS[@]}"; do
        if echo "$TENANT_COLUMNS" | grep -q "^$column$"; then
            log "   ✅ Coluna 'tenants.$column' existe"
        else
            error "   ❌ Coluna 'tenants.$column' AUSENTE"
        fi
    done
else
    error "❌ Tabela 'tenants' não existe - schema não foi criado"
fi

# ============================================================================
# 4. VARIÁVEIS DE AMBIENTE E CONFIGURAÇÃO
# ============================================================================

log "⚙️ Verificando configuração da aplicação..."

# Verificar arquivo .env
ENV_FILE="/opt/samureye/.env"
if [ -f "$ENV_FILE" ]; then
    log "✅ Arquivo .env existe"
    
    # Verificar variáveis críticas
    CRITICAL_VARS=("DATABASE_URL" "SESSION_SECRET" "NODE_ENV")
    
    for var in "${CRITICAL_VARS[@]}"; do
        if grep -q "^$var=" "$ENV_FILE"; then
            log "   ✅ Variável '$var' definida"
        else
            error "   ❌ Variável '$var' AUSENTE"
        fi
    done
    
    # Verificar formato da DATABASE_URL
    if grep -q "^DATABASE_URL=" "$ENV_FILE"; then
        DB_URL=$(grep "^DATABASE_URL=" "$ENV_FILE" | cut -d'=' -f2-)
        if [[ "$DB_URL" == postgresql://* ]]; then
            log "   ✅ DATABASE_URL tem formato correto"
        else
            error "   ❌ DATABASE_URL tem formato incorreto"
            echo "   • Formato esperado: postgresql://user:pass@host:port/database"
        fi
    fi
    
else
    error "❌ Arquivo .env não existe em $ENV_FILE"
    echo "   • Arquivo necessário para configuração da aplicação"
fi

# ============================================================================
# 5. LOGS DE ERRO ESPECÍFICOS
# ============================================================================

log "📝 Analisando logs recentes da aplicação..."

# Verificar logs do systemd
if systemctl is-active --quiet samureye-app 2>/dev/null; then
    info "Últimos erros no serviço samureye-app:"
    journalctl -u samureye-app --since "5 minutes ago" --no-pager | grep -i -E "(error|fail|tenant)" | tail -10 || echo "Nenhum erro recente encontrado"
fi

# Verificar logs de arquivos se existirem
LOG_DIRS=("/var/log/samureye" "/opt/samureye/logs" "/home/samureye/logs")
for log_dir in "${LOG_DIRS[@]}"; do
    if [ -d "$log_dir" ]; then
        info "Logs em $log_dir:"
        find "$log_dir" -name "*.log" -mtime -1 -exec tail -5 {} \; 2>/dev/null || echo "Nenhum log recente"
    fi
done

# ============================================================================
# 6. TESTE ESPECÍFICO DE CRIAÇÃO DE TENANT
# ============================================================================

log "🧪 Testando endpoint de criação de tenant..."

# Preparar payload de teste
TEST_PAYLOAD='{"name":"Test Tenant","description":"Tenant de teste para diagnóstico"}'

# Fazer requisição de teste
RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "$TEST_PAYLOAD" \
    "http://localhost:5000/api/tenants" \
    --connect-timeout 10 \
    --max-time 30 2>&1)

# Extrair status e body
HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

info "Teste de criação de tenant:"
echo "   • Status HTTP: $HTTP_STATUS"
echo "   • Response: $RESPONSE_BODY"

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
    log "✅ Endpoint de criação funcionando"
else
    error "❌ Endpoint de criação falhando"
    echo "   • Status: $HTTP_STATUS"
    echo "   • Body: $RESPONSE_BODY"
fi

# ============================================================================
# 7. VERIFICAÇÃO DE DEPENDÊNCIAS NODE.JS
# ============================================================================

log "📦 Verificando dependências Node.js..."

# Verificar se node_modules existe
if [ -d "/opt/samureye/node_modules" ]; then
    log "✅ node_modules existe"
    
    # Verificar dependências críticas
    CRITICAL_DEPS=("@neondatabase/serverless" "drizzle-orm" "express" "zod")
    
    for dep in "${CRITICAL_DEPS[@]}"; do
        if [ -d "/opt/samureye/node_modules/$dep" ]; then
            log "   ✅ Dependência '$dep' instalada"
        else
            error "   ❌ Dependência '$dep' AUSENTE"
        fi
    done
else
    error "❌ node_modules não existe"
    echo "   • Execute: cd /opt/samureye && npm install"
fi

# ============================================================================
# 8. RECOMENDAÇÕES DE CORREÇÃO
# ============================================================================

echo ""
log "🔧 RECOMENDAÇÕES DE CORREÇÃO:"
echo ""

if ! echo "$EXISTING_TABLES" | grep -q "^tenants$"; then
    error "PROBLEMA CRÍTICO: Schema do banco não foi criado"
    echo "   • Execute: cd /opt/samureye && npm run db:push"
    echo "   • Ou execute novamente o install-hard-reset com correção"
fi

if [ ! -f "$ENV_FILE" ]; then
    error "PROBLEMA CRÍTICO: Arquivo .env ausente"
    echo "   • Recrie o arquivo .env com as variáveis necessárias"
fi

if ! systemctl is-active --quiet samureye-app 2>/dev/null; then
    error "PROBLEMA: Serviço da aplicação inativo"
    echo "   • Execute: systemctl start samureye-app"
    echo "   • Execute: systemctl enable samureye-app"
fi

echo ""
log "✅ DIAGNÓSTICO CONCLUÍDO"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "   1. Analise os erros encontrados acima"
echo "   2. Execute as correções recomendadas"
echo "   3. Se necessário, execute o install-hard-reset corrigido"
echo "   4. Teste novamente a criação de tenant"
echo ""

exit 0