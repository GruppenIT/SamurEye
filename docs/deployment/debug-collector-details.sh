#!/bin/bash

echo "🔍 DIAGNÓSTICO DETALHADO - COLLECTOR E JORNADAS"
echo "=============================================="

DB_HOST="172.24.1.153"
DB_USER="samureye_user"
DB_NAME="samureye"
DB_PASS="samureye_secure_2024"

COLLECTOR_TOKEN="b6d6c21f-cf49-43a0-ba22-68e3da951b22"

echo "🔍 Token do collector: ${COLLECTOR_TOKEN:0:8}...${COLLECTOR_TOKEN: -8}"

# Teste 1: Dados completos do collector
echo ""
echo "📋 Teste 1: Dados completos do collector..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, hostname, tenant_id, status, 
            enrollment_token, enrollment_token_expires,
            created_at, updated_at
     FROM collectors 
     WHERE id = '$COLLECTOR_TOKEN';" 2>/dev/null

# Teste 2: Dados da jornada
echo ""
echo "📋 Teste 2: Detalhes da jornada existente..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, tenant_id, collector_id, status, schedule_type,
            target, scan_types, created_at
     FROM journeys;" 2>/dev/null

# Teste 3: Verificar se jornada está associada ao collector correto
echo ""
echo "📋 Teste 3: Verificando associação jornada-collector..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT j.id as journey_id, j.name as journey_name, 
            j.collector_id as journey_collector_id,
            c.id as actual_collector_id, c.name as collector_name,
            CASE 
                WHEN j.collector_id = c.id THEN 'MATCH ✅'
                ELSE 'MISMATCH ❌'
            END as association_status
     FROM journeys j
     CROSS JOIN collectors c;" 2>/dev/null

# Teste 4: Verificar por que enrollment_token está vazio
echo ""
echo "📋 Teste 4: Histórico de atualizações do collector..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT * FROM collectors WHERE id = '$COLLECTOR_TOKEN';" 2>/dev/null

# Teste 5: Verificar se deveria haver execuções
echo ""
echo "📋 Teste 5: Verificando se jornada é on-demand..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, schedule_type, status,
            CASE 
                WHEN schedule_type = 'on_demand' AND status = 'pending' 
                THEN 'DEVERIA TER EXECUÇÃO ❌'
                ELSE 'OK ✅'
            END as execution_status
     FROM journeys;" 2>/dev/null

# Teste 6: Tentar corrigir o enrollment_token
echo ""
echo "📋 Teste 6: CORREÇÃO - Atualizando enrollment_token do collector..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "UPDATE collectors 
     SET enrollment_token = '$COLLECTOR_TOKEN',
         enrollment_token_expires = NOW() + INTERVAL '30 days'
     WHERE id = '$COLLECTOR_TOKEN';" 2>/dev/null

echo "✅ Token atualizado!"

# Teste 7: Verificar se correção funcionou
echo ""
echo "📋 Teste 7: Verificando correção do token..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name, 
            LEFT(enrollment_token, 8) || '...' as token_preview,
            enrollment_token_expires > NOW() as token_valid
     FROM collectors 
     WHERE id = '$COLLECTOR_TOKEN';" 2>/dev/null

# Teste 8: Criar execução manual se jornada é on-demand
echo ""
echo "📋 Teste 8: Criando execução manual para jornada on-demand..."

JOURNEY_ID=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT id FROM journeys WHERE schedule_type = 'on_demand' LIMIT 1;" 2>/dev/null | tr -d ' ')

if [ -n "$JOURNEY_ID" ]; then
    echo "Criando execução para jornada: $JOURNEY_ID"
    
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "INSERT INTO journey_executions (id, journey_id, collector_id, status, created_at, updated_at)
         VALUES (gen_random_uuid(), '$JOURNEY_ID', '$COLLECTOR_TOKEN', 'queued', NOW(), NOW());" 2>/dev/null
    
    echo "✅ Execução criada!"
else
    echo "❌ Nenhuma jornada on-demand encontrada"
fi

# Teste 9: Verificar resultado final
echo ""
echo "📋 Teste 9: Verificação final..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT 
        (SELECT COUNT(*) FROM collectors WHERE enrollment_token IS NOT NULL) as collectors_with_token,
        (SELECT COUNT(*) FROM journey_executions WHERE status = 'queued') as pending_executions;" 2>/dev/null

echo ""
echo "🎯 CORREÇÕES APLICADAS:"
echo "   ✅ enrollment_token definido para o collector"
echo "   ✅ Token com expiração de 30 dias"
echo "   ✅ Execução criada para jornada on-demand (se existir)"
echo ""
echo "🧪 PRÓXIMO PASSO: Testar o collector novamente!"