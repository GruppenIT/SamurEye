#!/bin/bash

echo "🔍 INVESTIGAÇÃO TABELA journey_executions"
echo "========================================"

DB_HOST="172.24.1.153"
DB_USER="samureye_user"
DB_NAME="samureye"
DB_PASS="samureye_secure_2024"

COLLECTOR_ID="b6d6c21f-cf49-43a0-ba22-68e3da951b22"

echo "🔍 Collector ID: ${COLLECTOR_ID:0:8}...${COLLECTOR_ID: -8}"

# Teste 1: Estrutura da tabela
echo ""
echo "📋 Teste 1: Estrutura da tabela journey_executions..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "\d journey_executions;" 2>/dev/null

# Teste 2: Constraints e índices
echo ""
echo "📋 Teste 2: Constraints da tabela..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT conname, contype, pg_get_constraintdef(oid) as definition
     FROM pg_constraint 
     WHERE conrelid = 'journey_executions'::regclass;" 2>/dev/null

# Teste 3: Verificar se jornada existe
echo ""
echo "📋 Teste 3: Verificando jornada existente..."
JOURNEY_ID=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT id FROM journeys LIMIT 1;" 2>/dev/null | tr -d ' ')

echo "Jornada ID: $JOURNEY_ID"

if [ -n "$JOURNEY_ID" ]; then
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT id, name, collector_id, tenant_id, status 
         FROM journeys WHERE id = '$JOURNEY_ID';" 2>/dev/null
fi

# Teste 4: Inserção manual detalhada
echo ""
echo "📋 Teste 4: Inserção manual com verbose..."

if [ -n "$JOURNEY_ID" ]; then
    echo "Tentando inserir execução passo a passo..."
    
    # 4.1: Verificar se já existe
    echo ""
    echo "4.1: Verificando execuções existentes..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT COUNT(*) as total FROM journey_executions;" 2>/dev/null
    
    # 4.2: Inserção simples
    echo ""
    echo "4.2: Tentando inserção simples..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "INSERT INTO journey_executions (id, journey_id, collector_id, status, created_at, updated_at)
         VALUES ('test-exec-001', '$JOURNEY_ID', '$COLLECTOR_ID', 'queued', NOW(), NOW());" 2>&1
    
    # 4.3: Verificar se inseriu
    echo ""
    echo "4.3: Verificando após inserção..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT COUNT(*) as total_after FROM journey_executions;" 2>/dev/null
    
    # 4.4: Tentar com gen_random_uuid
    echo ""
    echo "4.4: Tentando com gen_random_uuid()..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "INSERT INTO journey_executions (id, journey_id, collector_id, status, created_at, updated_at)
         VALUES (gen_random_uuid(), '$JOURNEY_ID', '$COLLECTOR_ID', 'queued', NOW(), NOW());" 2>&1
    
    # 4.5: Verificar novamente
    echo ""
    echo "4.5: Verificando após segunda inserção..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT COUNT(*) as total_final FROM journey_executions;" 2>/dev/null
    
    # 4.6: Mostrar todos os registros
    echo ""
    echo "4.6: Mostrando todos os registros..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT * FROM journey_executions;" 2>/dev/null
    
    # 4.7: Testar rollback/autocommit
    echo ""
    echo "4.7: Verificando configurações de transação..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SHOW autocommit;" 2>/dev/null
        
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT current_setting('transaction_isolation');" 2>/dev/null
fi

# Teste 5: Verificar permissões
echo ""
echo "📋 Teste 5: Verificando permissões do usuário..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT has_table_privilege('$DB_USER', 'journey_executions', 'INSERT') as can_insert,
            has_table_privilege('$DB_USER', 'journey_executions', 'SELECT') as can_select;" 2>/dev/null

# Teste 6: Verificar triggers
echo ""
echo "📋 Teste 6: Verificando triggers na tabela..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT tgname, tgtype, tgenabled 
     FROM pg_trigger 
     WHERE tgrelid = 'journey_executions'::regclass;" 2>/dev/null

echo ""
echo "🎯 INVESTIGAÇÃO COMPLETA!"
echo "   📊 Se inserções falharam: problema de constraint/foreign key"
echo "   📊 Se inserções passaram: problema de transação/rollback"
echo "   📊 Se contagem ainda 0: problema de isolation/commit"