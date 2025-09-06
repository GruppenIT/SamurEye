#!/bin/bash

echo "🔍 TESTE SIMPLES - CONECTIVIDADE E DADOS"
echo "========================================"

DB_HOST="172.24.1.153"
DB_USER="samureye_user"
DB_NAME="samureye"
DB_PASS="samureye_secure_2024"

echo "🧪 Teste 1: Conectividade básica..."
if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 'Conectividade OK' as teste;" 2>/dev/null; then
    echo "✅ Conectividade funcionando"
else
    echo "❌ Falha na conectividade"
    echo "   Testando credenciais alternativas..."
    
    # Testar com usuário 'samureye' e senha 'SamurEye2024!'
    if PGPASSWORD="SamurEye2024!" psql -h "$DB_HOST" -U "samureye" -d "$DB_NAME" -c "SELECT 'Conectividade OK' as teste;" 2>/dev/null; then
        echo "✅ Conectividade OK com usuário 'samureye'"
        DB_USER="samureye"
        DB_PASS="SamurEye2024!"
    else
        echo "❌ Falha total na conectividade"
        exit 1
    fi
fi

echo ""
echo "🔍 Teste 2: Contagem de tabelas..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT COUNT(*) as total_tabelas FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null

echo ""
echo "🔍 Teste 3: Contagem de collectors..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT COUNT(*) as total_collectors FROM collectors;" 2>/dev/null

echo ""
echo "🔍 Teste 4: Listar todos os collectors (simples)..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT id, name FROM collectors;" 2>/dev/null

echo ""
echo "🔍 Teste 5: Primeiros 8 chars dos tokens..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT LEFT(enrollment_token, 8) as token_preview, name, status FROM collectors;" 2>/dev/null

echo ""
echo "🔍 Teste 6: Verificar token atual do collector vlxsam04..."
if [ -f "/etc/samureye-collector/.env" ]; then
    source /etc/samureye-collector/.env
    echo "Token atual no .env: ${COLLECTOR_TOKEN:0:8}...${COLLECTOR_TOKEN: -8}"
    
    # Buscar por este token
    echo ""
    echo "Buscando este token no banco..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT id, name, tenant_id, status FROM collectors WHERE enrollment_token = '$COLLECTOR_TOKEN';" 2>/dev/null
else
    echo "❌ Arquivo .env do collector não encontrado"
fi

echo ""
echo "🔍 Teste 7: Contar tenants e jornadas..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT 
        (SELECT COUNT(*) FROM tenants) as total_tenants,
        (SELECT COUNT(*) FROM journeys) as total_journeys,
        (SELECT COUNT(*) FROM journey_executions) as total_executions;" 2>/dev/null