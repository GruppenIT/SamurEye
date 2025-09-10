#!/bin/bash

echo "🔍 DIAGNÓSTICO AVANÇADO: Autenticação Collector On-Premise"
echo "==========================================================="

ENV_FILE="/opt/samureye/SamurEye/.env"

# 1. Verificar se a aplicação está rodando
echo ""
echo "1️⃣ Verificando serviço..."
if systemctl is-active --quiet samureye-app; then
    echo "✅ Serviço samureye-app está ativo"
    echo "   Status: $(systemctl status samureye-app --no-pager -l | grep Active)"
else
    echo "❌ Serviço samureye-app não está ativo"
    echo "   Status: $(systemctl status samureye-app --no-pager -l | grep Active)"
fi

# 2. Verificar DATABASE_URL que a aplicação está usando
echo ""
echo "2️⃣ Verificando configuração do banco..."
if [ -f "$ENV_FILE" ]; then
    echo "✅ Arquivo .env encontrado"
    DATABASE_URL=$(grep "^DATABASE_URL=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')
    echo "   DATABASE_URL: ${DATABASE_URL:0:50}..."
else
    echo "❌ Arquivo .env não encontrado: $ENV_FILE"
fi

# 3. Testar conexão da aplicação ao banco
echo ""
echo "3️⃣ Testando conexão ao banco..."
if [[ $DATABASE_URL =~ postgresql://([^:]+):([^@]+)@([^:]+):([^/]+)/(.+) ]]; then
    DB_USER="${BASH_REMATCH[1]}"
    DB_PASS="${BASH_REMATCH[2]}"
    DB_HOST="${BASH_REMATCH[3]}"
    DB_PORT="${BASH_REMATCH[4]}"
    DB_NAME="${BASH_REMATCH[5]}"
    
    export PGPASSWORD="${DB_PASS}"
    if timeout 5 psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1; then
        echo "✅ Conexão ao banco PostgreSQL OK"
        
        # Verificar dados do collector
        echo ""
        echo "4️⃣ Verificando dados do collector no banco..."
        psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "
        SELECT 
            'Collector vlxsam04:' as info,
            id,
            name,
            CASE 
                WHEN enrollment_token IS NULL THEN 'NULL'
                WHEN enrollment_token = '' THEN 'EMPTY'
                ELSE substring(enrollment_token, 1, 8) || '...'
            END as token_preview,
            status,
            created_at
        FROM collectors 
        WHERE name = 'vlxsam04' OR id LIKE '%vlxsam04%';
        " 2>/dev/null
        
    else
        echo "❌ Falha na conexão ao PostgreSQL"
        echo "   Host: ${DB_HOST}:${DB_PORT}"
        echo "   User: ${DB_USER}"
        echo "   DB: ${DB_NAME}"
    fi
else
    echo "❌ Erro ao analisar DATABASE_URL"
fi

# 5. Testar endpoint da aplicação com dados reais
echo ""
echo "5️⃣ Testando endpoint da aplicação..."

# Pegar token real do banco se possível
if [ -n "$DB_HOST" ]; then
    export PGPASSWORD="${DB_PASS}"
    REAL_TOKEN=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT enrollment_token FROM collectors WHERE name = 'vlxsam04' LIMIT 1;" 2>/dev/null | tr -d ' ')
    
    if [ -n "$REAL_TOKEN" ]; then
        echo "🔑 Token encontrado no banco: ${REAL_TOKEN:0:8}..."
        
        echo ""
        echo "   Testando /collector-api/journeys/pending..."
        RESPONSE=$(curl -s "http://localhost:5000/collector-api/journeys/pending?collector_id=vlxsam04&token=${REAL_TOKEN}" 2>/dev/null)
        echo "   Resposta: ${RESPONSE:0:100}"
        
        # Se retornou array, testar endpoint de data
        if [[ "$RESPONSE" == "["* ]]; then
            echo ""
            echo "   Testando /collector-api/journeys/test/data..."
            DATA_RESPONSE=$(curl -s "http://localhost:5000/collector-api/journeys/test/data?collector_id=vlxsam04&token=${REAL_TOKEN}" 2>/dev/null)
            echo "   Resposta: ${DATA_RESPONSE:0:100}"
        fi
    else
        echo "❌ Token não encontrado no banco"
    fi
fi

# 6. Verificar logs da aplicação
echo ""
echo "6️⃣ Logs recentes da aplicação..."
if journalctl -u samureye-app --no-pager -l -n 10 >/dev/null 2>&1; then
    echo "📋 Últimas 10 linhas dos logs:"
    journalctl -u samureye-app --no-pager -l -n 10 | tail -10
else
    echo "❌ Não foi possível acessar logs do systemd"
fi

echo ""
echo "=========================================="
echo "🏁 DIAGNÓSTICO AVANÇADO CONCLUÍDO"