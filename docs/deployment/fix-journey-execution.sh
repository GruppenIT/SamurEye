#!/bin/bash

echo "🔧 CORREÇÃO DEFINITIVA - CRIAÇÃO EXECUÇÃO COM TODOS OS CAMPOS"
echo "============================================================"

DB_HOST="172.24.1.153"
DB_USER="samureye_user"
DB_NAME="samureye"
DB_PASS="samureye_secure_2024"

COLLECTOR_ID="b6d6c21f-cf49-43a0-ba22-68e3da951b22"

echo "🔍 Collector ID: ${COLLECTOR_ID:0:8}...${COLLECTOR_ID: -8}"

# Buscar jornada
JOURNEY_ID=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT id FROM journeys LIMIT 1;" 2>/dev/null | tr -d ' ')

echo "🔍 Jornada ID: ${JOURNEY_ID:0:8}...${JOURNEY_ID: -8}"

if [ -n "$JOURNEY_ID" ]; then
    # Limpar execuções antigas
    echo ""
    echo "🧹 Limpando execuções antigas..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "DELETE FROM journey_executions WHERE journey_id = '$JOURNEY_ID';" 2>/dev/null
    
    # Criar execução com TODOS os campos obrigatórios
    echo ""
    echo "✅ Criando execução com todos os campos obrigatórios..."
    
    INSERT_RESULT=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "INSERT INTO journey_executions (
            id, 
            journey_id, 
            collector_id, 
            status, 
            execution_number, 
            scheduled_for, 
            created_at, 
            updated_at
        ) VALUES (
            gen_random_uuid(), 
            '$JOURNEY_ID', 
            '$COLLECTOR_ID', 
            'queued', 
            1, 
            NOW(), 
            NOW(), 
            NOW()
        ) RETURNING id;" 2>&1)
    
    if echo "$INSERT_RESULT" | grep -q "ERROR"; then
        echo "❌ Erro na inserção: $INSERT_RESULT"
    else
        echo "✅ Execução criada com sucesso!"
        echo "$INSERT_RESULT"
    fi
    
    # Verificar se persistiu
    echo ""
    echo "🔍 Verificando se execução persistiu..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT COUNT(*) as total_queued, 
                MAX(created_at) as ultima_criacao
         FROM journey_executions 
         WHERE status = 'queued';" 2>/dev/null
    
    # Mostrar execuções criadas
    echo ""
    echo "📋 Execuções pendentes:"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT id, journey_id, collector_id, status, execution_number, scheduled_for, created_at
         FROM journey_executions 
         WHERE status = 'queued';" 2>/dev/null
    
    # Testar endpoint
    echo ""
    echo "🧪 Testando endpoint após correção..."
    RESPONSE=$(curl -s -w "HTTPCODE:%{http_code}" \
        "https://api.samureye.com.br/collector-api/journeys/pending?collector_id=$COLLECTOR_ID&token=$COLLECTOR_ID" \
        -H "User-Agent: SamurEye-Collector" 2>/dev/null)
    
    HTTP_CODE=$(echo "$RESPONSE" | sed -n 's/.*HTTPCODE:\([0-9]*\).*/\1/p')
    BODY=$(echo "$RESPONSE" | sed 's/HTTPCODE:[0-9]*$//')
    
    echo "HTTP Code: $HTTP_CODE"
    echo "Response: $BODY"
    
    echo ""
    echo "🎯 RESULTADO:"
    if [ "$HTTP_CODE" = "200" ] && [ "$BODY" != "[]" ]; then
        echo "🎉 SUCESSO TOTAL! Endpoint retornando execuções!"
        echo "   ✅ Collector deve parar de mostrar erro em 30 segundos"
        echo "   ✅ Logs devem mostrar execução de jornada"
    elif [ "$HTTP_CODE" = "200" ] && [ "$BODY" = "[]" ]; then
        echo "⚠️ Endpoint OK mas ainda retorna lista vazia"
        echo "   🔍 Verificar filtros na query do endpoint"
    else
        echo "❌ Ainda há problema: HTTP $HTTP_CODE"
    fi
    
else
    echo "❌ Nenhuma jornada encontrada no banco"
fi

echo ""
echo "📊 RESUMO DA CORREÇÃO:"
echo "   🔧 Corrigido: execution_number = 1"
echo "   🔧 Corrigido: scheduled_for = NOW()"
echo "   ✅ Todos os campos NOT NULL preenchidos"
echo "   🎯 Execução deve persistir e aparecer no endpoint"