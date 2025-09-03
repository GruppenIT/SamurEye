#!/bin/bash

# ============================================================================
# SCRIPT DIAGNÓSTICO - TOKEN ENROLLMENT vlxsam02  
# ============================================================================
# Investiga por que o token de enrollment não está sendo exibido na interface
# Testa endpoint POST /api/collectors e verifica response JSON
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
echo "🔍 DIAGNÓSTICO - TOKEN ENROLLMENT"
echo "================================="
echo "Sistema: vlxsam02 ($(hostname))"
echo "Problema: Token de enrollment vazio na interface"
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
    echo "   • Execute: systemctl start samureye-app"
    exit 1
fi

# Verificar se aplicação responde
if curl -s --connect-timeout 5 http://localhost:5000/api/health >/dev/null 2>&1; then
    log "✅ Aplicação responde na porta 5000"
else
    error "❌ Aplicação não responde na porta 5000"
    echo "   • Verifique logs: journalctl -u samureye-app -f"
    exit 1
fi

# ============================================================================
# 2. VERIFICAR BANCO DE DADOS E TABELAS
# ============================================================================

log "🗄️ Verificando conectividade e schema do banco..."

DB_HOST="192.168.100.153"
DB_PORT="5432"
DB_NAME="samureye"
DB_USER="samureye"
DB_PASS="samureye_secure_2024"

# Testar conectividade
if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
    log "✅ Conectividade com PostgreSQL OK"
else
    error "❌ Falha na conectividade PostgreSQL"
    exit 1
fi

# Verificar estrutura da tabela collectors
log "📋 Verificando estrutura da tabela 'collectors'..."
COLLECTOR_COLUMNS=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'collectors' ORDER BY column_name;" 2>/dev/null | tr -d ' ')

REQUIRED_COLUMNS=("enrollment_token" "enrollment_token_expires" "id" "name" "tenant_id" "status")

for column in "${REQUIRED_COLUMNS[@]}"; do
    if echo "$COLLECTOR_COLUMNS" | grep -q "^$column$"; then
        log "   ✅ Coluna 'collectors.$column' existe"
    else
        error "   ❌ Coluna 'collectors.$column' AUSENTE"
    fi
done

# ============================================================================
# 3. TESTE DIRETO DO ENDPOINT POST /api/collectors
# ============================================================================

log "🧪 Testando endpoint POST /api/collectors..."

# Primeiro, verificar se podemos acessar o endpoint sem autenticação
info "Testando acesso sem autenticação (deve falhar com 401):"
UNAUTH_RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    --data '{"name":"test-collector","hostname":"test"}' \
    "http://localhost:5000/api/collectors" \
    --connect-timeout 10 \
    --max-time 30 2>&1)

UNAUTH_STATUS=$(echo $UNAUTH_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
echo "   • Status sem auth: $UNAUTH_STATUS (esperado: 401)"

if [ "$UNAUTH_STATUS" != "401" ]; then
    warn "⚠️ Endpoint deveria retornar 401 sem autenticação"
fi

# ============================================================================
# 4. SIMULAR CRIAÇÃO DE COLLECTOR COM AUTENTICAÇÃO MOCADA
# ============================================================================

log "🔧 Simulando criação de collector com dados de teste..."

# Criar um collector diretamente no banco para testar
TEST_COLLECTOR_NAME="diagnostic-test-$(date +%s)"
TEST_TENANT_ID=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT id FROM tenants LIMIT 1;" 2>/dev/null | tr -d ' ')

if [ -n "$TEST_TENANT_ID" ] && [ "$TEST_TENANT_ID" != "" ]; then
    log "✅ Tenant encontrado: $TEST_TENANT_ID"
    
    # Inserir collector de teste diretamente no banco
    TEST_TOKEN="test-token-$(date +%s)"
    TEST_EXPIRES=$(date -d '+15 minutes' '+%Y-%m-%d %H:%M:%S')
    
    info "Inserindo collector de teste no banco..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
    INSERT INTO collectors (
        id, tenant_id, name, hostname, status, 
        enrollment_token, enrollment_token_expires, 
        created_at, updated_at
    ) VALUES (
        gen_random_uuid(), 
        '$TEST_TENANT_ID', 
        '$TEST_COLLECTOR_NAME', 
        'diagnostic-host', 
        'enrolling',
        '$TEST_TOKEN',
        '$TEST_EXPIRES',
        NOW(),
        NOW()
    );" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "✅ Collector de teste inserido com sucesso"
        
        # Buscar o collector inserido
        INSERTED_DATA=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT id, name, enrollment_token, enrollment_token_expires 
        FROM collectors 
        WHERE name = '$TEST_COLLECTOR_NAME';" 2>/dev/null)
        
        if [ -n "$INSERTED_DATA" ]; then
            log "✅ Dados do collector inserido:"
            echo "$INSERTED_DATA" | while read line; do
                echo "   • $line"
            done
        fi
        
        # Remover collector de teste
        info "Removendo collector de teste..."
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM collectors WHERE name = '$TEST_COLLECTOR_NAME';" >/dev/null 2>&1
    else
        error "❌ Falha ao inserir collector de teste"
    fi
else
    error "❌ Nenhum tenant encontrado no banco"
fi

# ============================================================================
# 5. VERIFICAR LOGS DA APLICAÇÃO
# ============================================================================

log "📝 Analisando logs recentes da aplicação..."

# Verificar logs do systemd
if systemctl is-active --quiet samureye-app 2>/dev/null; then
    info "Últimos logs do serviço samureye-app:"
    journalctl -u samureye-app --since "5 minutes ago" --no-pager | tail -20 || echo "Nenhum log recente encontrado"
fi

# ============================================================================
# 6. VERIFICAR CÓDIGO FONTE ATUAL
# ============================================================================

log "🔍 Verificando configurações do código..."

APP_DIR="/opt/samureye"
if [ -d "$APP_DIR" ]; then
    log "✅ Diretório da aplicação existe: $APP_DIR"
    
    # Verificar se shared/schema.ts existe e tem as configurações corretas
    SCHEMA_FILE="$APP_DIR/shared/schema.ts"
    if [ -f "$SCHEMA_FILE" ]; then
        log "✅ Arquivo schema.ts existe"
        
        # Verificar se enrollmentToken não está sendo omitido
        if grep -q "enrollmentToken.*true" "$SCHEMA_FILE"; then
            error "❌ enrollmentToken está sendo omitido no insertCollectorSchema"
            echo "   • Linha encontrada:"
            grep -n "enrollmentToken.*true" "$SCHEMA_FILE" | head -3
        elif grep -q "enrollmentToken" "$SCHEMA_FILE"; then
            log "✅ enrollmentToken está presente no schema"
        else
            warn "⚠️ enrollmentToken não encontrado no schema"
        fi
    else
        error "❌ Arquivo schema.ts não encontrado"
    fi
    
    # Verificar se server/routes.ts tem o endpoint correto
    ROUTES_FILE="$APP_DIR/server/routes.ts"
    if [ -f "$ROUTES_FILE" ]; then
        log "✅ Arquivo routes.ts existe"
        
        # Verificar se o endpoint POST /api/collectors está implementado
        if grep -q "app.post.*\/api\/collectors" "$ROUTES_FILE"; then
            log "✅ Endpoint POST /api/collectors encontrado"
            
            # Verificar se está retornando o enrollmentToken
            if grep -A 10 -B 5 "enrollmentToken" "$ROUTES_FILE" | grep -q "res.json"; then
                log "✅ enrollmentToken está sendo retornado no response"
            else
                warn "⚠️ enrollmentToken pode não estar sendo retornado"
            fi
        else
            error "❌ Endpoint POST /api/collectors não encontrado"
        fi
    else
        error "❌ Arquivo routes.ts não encontrado"
    fi
else
    error "❌ Diretório da aplicação não existe: $APP_DIR"
fi

# ============================================================================
# 7. RECOMENDAÇÕES DE CORREÇÃO
# ============================================================================

echo ""
log "🔧 RECOMENDAÇÕES DE CORREÇÃO:"
echo ""

error "PROBLEMA IDENTIFICADO: Token de enrollment não está sendo exibido"
echo ""

echo "🔍 POSSÍVEIS CAUSAS:"
echo "   1. enrollmentToken sendo omitido no insertCollectorSchema"
echo "   2. Token não sendo gerado corretamente no backend"
echo "   3. Token não sendo retornado no response JSON"
echo "   4. Frontend não recebendo o token corretamente"
echo ""

echo "🔧 CORREÇÕES SUGERIDAS:"
echo "   1. Verificar shared/schema.ts - remover omit do enrollmentToken"
echo "   2. Verificar server/routes.ts - garantir que token está no response"
echo "   3. Verificar logs da aplicação durante criação de collector"
echo "   4. Testar manualmente o endpoint com curl"
echo ""

echo "📋 PRÓXIMOS PASSOS:"
echo "   1. Execute a correção específica para token enrollment"
echo "   2. Reinicie a aplicação"
echo "   3. Teste novamente na interface"
echo ""

log "✅ DIAGNÓSTICO CONCLUÍDO"
echo ""
echo "🔧 CORREÇÃO DISPONÍVEL:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/fix-enrollment-token-issue.sh | bash"
echo ""

exit 0