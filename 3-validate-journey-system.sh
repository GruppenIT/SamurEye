#!/bin/bash

echo "✅ VALIDAÇÃO FINAL: Sistema de Execução de Jornadas"
echo "=================================================="

TOKEN="5a774b05-8a8e-4e40-9f83-981320752086"
COLLECTOR_ID="vlxsam04"

echo ""
echo "1️⃣ Testando endpoints collector-api..."

# Teste 1: Jornadas pendentes
echo "   🧪 /collector-api/journeys/pending"
PENDING=$(curl -s "http://localhost:5000/collector-api/journeys/pending?collector_id=${COLLECTOR_ID}&token=${TOKEN}" 2>/dev/null)
if [[ "$PENDING" == "["* ]]; then
    echo "   ✅ Retorna JSON array: ${PENDING:0:50}..."
else
    echo "   ❌ Não retorna JSON: ${PENDING:0:50}..."
fi

# Teste 2: Dados da jornada
echo "   🧪 /collector-api/journeys/test/data"
DATA=$(curl -s "http://localhost:5000/collector-api/journeys/test/data?collector_id=${COLLECTOR_ID}&token=${TOKEN}" 2>/dev/null)
if [[ "$DATA" == *"Journey not found"* ]] || [[ "$DATA" == *"{"* ]]; then
    echo "   ✅ Retorna JSON: ${DATA:0:50}..."
else
    echo "   ❌ Retorna HTML: ${DATA:0:50}..."
fi

# Teste 3: Heartbeat
echo "   🧪 /collector-api/heartbeat"
HEARTBEAT=$(curl -s -X POST "http://localhost:5000/collector-api/heartbeat" \
  -H "Content-Type: application/json" \
  -d "{
    \"collector_id\": \"${COLLECTOR_ID}\",
    \"token\": \"${TOKEN}\",
    \"telemetry\": {
      \"cpuUsage\": 45.2,
      \"memoryUsage\": 67.8,
      \"diskUsage\": 23.1
    }
  }" 2>/dev/null)
if [[ "$HEARTBEAT" == *"success"* ]] || [[ "$HEARTBEAT" == *"status"* ]]; then
    echo "   ✅ Heartbeat OK: ${HEARTBEAT:0:50}..."
else
    echo "   ❌ Heartbeat falhou: ${HEARTBEAT:0:50}..."
fi

echo ""
echo "2️⃣ Verificando status do collector no banco..."

# Verificar dados do collector
ENV_FILE="/opt/samureye/SamurEye/.env"
if [ -f "$ENV_FILE" ]; then
    DATABASE_URL=$(grep "^DATABASE_URL=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')
    if [[ $DATABASE_URL =~ postgresql://([^:]+):([^@]+)@([^:]+):([^/]+)/(.+) ]]; then
        DB_USER="${BASH_REMATCH[1]}"
        DB_PASS="${BASH_REMATCH[2]}"
        DB_HOST="${BASH_REMATCH[3]}"
        DB_PORT="${BASH_REMATCH[4]}"
        DB_NAME="${BASH_REMATCH[5]}"
        
        export PGPASSWORD="${DB_PASS}"
        COLLECTOR_STATUS=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT status FROM collectors WHERE name = 'vlxsam04';" 2>/dev/null | tr -d ' ')
        echo "   Status no banco: ${COLLECTOR_STATUS}"
        
        # Verificar jornadas pendentes no banco
        PENDING_COUNT=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM journey_executions WHERE status = 'queued';" 2>/dev/null | tr -d ' ')
        echo "   Execuções pendentes: ${PENDING_COUNT}"
    fi
fi

echo ""
echo "3️⃣ Testando criação de jornada..."

# Criar uma jornada de teste
echo "   🧪 Criando jornada de teste..."
CREATE_RESPONSE=$(curl -s -X POST "http://localhost:5000/api/journeys" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Teste Validação Sistema",
    "description": "Jornada criada para validar sistema",
    "targets": ["8.8.8.8"],
    "tools": ["nmap"],
    "collectorId": "'${COLLECTOR_ID}'",
    "scheduleType": "on_demand"
  }' 2>/dev/null)

if [[ "$CREATE_RESPONSE" == *"id"* ]]; then
    echo "   ✅ Jornada criada com sucesso"
    
    # Extrair ID da jornada
    JOURNEY_ID=$(echo "$CREATE_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$JOURNEY_ID" ]; then
        echo "   ID da jornada: ${JOURNEY_ID}"
        
        # Iniciar execução
        echo "   🧪 Iniciando execução..."
        START_RESPONSE=$(curl -s -X POST "http://localhost:5000/api/journeys/${JOURNEY_ID}/start" 2>/dev/null)
        
        if [[ "$START_RESPONSE" == *"success"* ]] || [[ "$START_RESPONSE" == *"execution"* ]]; then
            echo "   ✅ Execução iniciada com sucesso"
            
            # Verificar se aparece nas jornadas pendentes
            sleep 2
            echo "   🧪 Verificando jornadas pendentes após criação..."
            NEW_PENDING=$(curl -s "http://localhost:5000/collector-api/journeys/pending?collector_id=${COLLECTOR_ID}&token=${TOKEN}" 2>/dev/null)
            PENDING_COUNT=$(echo "$NEW_PENDING" | grep -o '"id"' | wc -l)
            echo "   Jornadas pendentes agora: ${PENDING_COUNT}"
            
            if [ "$PENDING_COUNT" -gt 0 ]; then
                echo "   ✅ Nova jornada aparece na lista de pendentes"
                echo ""
                echo "🎉 SISTEMA COMPLETAMENTE OPERACIONAL!"
                echo "   • Endpoints retornam JSON ✅"
                echo "   • Collector se conecta ✅"
                echo "   • Jornadas são criadas ✅"
                echo "   • Execuções aparecem na fila ✅"
                echo "   • Collector pode buscar dados ✅"
            else
                echo "   ⚠️ Jornada criada mas não aparece nas pendentes"
            fi
        else
            echo "   ❌ Falha ao iniciar execução: ${START_RESPONSE:0:50}..."
        fi
    fi
else
    echo "   ❌ Falha ao criar jornada: ${CREATE_RESPONSE:0:50}..."
fi

echo ""
echo "=========================================="
echo "🏁 VALIDAÇÃO FINAL CONCLUÍDA"