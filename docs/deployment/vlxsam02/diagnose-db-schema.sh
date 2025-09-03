#!/bin/bash

# =============================================================================
# DIAGNÓSTICO SCHEMA BANCO DE DADOS - vlxsam02
# =============================================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK") echo -e "${GREEN}✅ $message${NC}" ;;
        "FAIL") echo -e "${RED}❌ $message${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠️ $message${NC}" ;;
        "INFO") echo -e "${BLUE}ℹ️ $message${NC}" ;;
    esac
}

echo "============================================="
echo "DIAGNÓSTICO SCHEMA BANCO DE DADOS - vlxsam02"
echo "============================================="

# Configurações
POSTGRES_HOST="172.24.1.153"
POSTGRES_PORT="5432"
POSTGRES_DB="samureye"
POSTGRES_USER="samureye_user"
POSTGRES_PASSWORD="samureye_secure_2024"
WORKING_DIR="/opt/samureye"

export PGPASSWORD="$POSTGRES_PASSWORD"
export DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"

echo ""
print_status "INFO" "Configurações:"
echo "   Host: $POSTGRES_HOST"
echo "   Port: $POSTGRES_PORT"
echo "   Database: $POSTGRES_DB"
echo "   User: $POSTGRES_USER"

echo ""
print_status "INFO" "1. VERIFICANDO CONECTIVIDADE POSTGRESQL"

# Teste conectividade
if ping -c 1 -W 5 "$POSTGRES_HOST" >/dev/null 2>&1; then
    print_status "OK" "Host $POSTGRES_HOST respondendo"
else
    print_status "FAIL" "Host $POSTGRES_HOST não responde"
    exit 1
fi

if timeout 10 nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    print_status "OK" "PostgreSQL acessível em $POSTGRES_HOST:$POSTGRES_PORT"
else
    print_status "FAIL" "PostgreSQL não acessível em $POSTGRES_HOST:$POSTGRES_PORT"
    exit 1
fi

if psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
    print_status "OK" "Autenticação PostgreSQL funcionando"
else
    print_status "FAIL" "Falha na autenticação PostgreSQL"
    exit 1
fi

echo ""
print_status "INFO" "2. VERIFICANDO TABELAS EXISTENTES"

# Listar tabelas existentes
echo "Tabelas existentes no banco:"
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;" -t | while read table; do
    if [ -n "$table" ]; then
        echo "   - $(echo $table | xargs)"
    fi
done

# Verificar tabelas críticas
critical_tables=("tenants" "users" "collectors")
missing_tables=()

for table in "${critical_tables[@]}"; do
    if psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1 FROM $table LIMIT 1;" >/dev/null 2>&1; then
        print_status "OK" "Tabela '$table' existe e acessível"
    else
        print_status "FAIL" "Tabela '$table' não existe ou inacessível"
        missing_tables+=("$table")
    fi
done

echo ""
print_status "INFO" "3. VERIFICANDO CONFIGURAÇÃO DRIZZLE"

cd "$WORKING_DIR" 2>/dev/null || {
    print_status "FAIL" "Diretório $WORKING_DIR não encontrado"
    exit 1
}

if [ -f "package.json" ]; then
    print_status "OK" "package.json encontrado"
    if grep -q '"db:push"' package.json; then
        print_status "OK" "Script db:push configurado"
    else
        print_status "WARN" "Script db:push não encontrado"
    fi
else
    print_status "FAIL" "package.json não encontrado"
fi

if [ -f "drizzle.config.ts" ]; then
    print_status "OK" "drizzle.config.ts encontrado"
else
    print_status "FAIL" "drizzle.config.ts não encontrado"
fi

if [ -d "node_modules" ]; then
    print_status "OK" "node_modules existe"
    if [ -f "node_modules/.bin/drizzle-kit" ]; then
        print_status "OK" "drizzle-kit instalado"
    else
        print_status "WARN" "drizzle-kit não encontrado"
    fi
else
    print_status "WARN" "node_modules não existe"
fi

echo ""
print_status "INFO" "4. TESTANDO COMANDOS DRIZZLE"

# Teste db:push
echo "Testando npm run db:push..."
if npm run db:push --dry-run 2>/dev/null; then
    print_status "OK" "npm run db:push disponível"
else
    print_status "WARN" "npm run db:push falhou no teste"
fi

# Teste drizzle-kit
echo "Testando drizzle-kit..."
if command -v npx >/dev/null 2>&1; then
    if npx drizzle-kit --help >/dev/null 2>&1; then
        print_status "OK" "drizzle-kit via npx disponível"
    else
        print_status "WARN" "drizzle-kit via npx falhou"
    fi
fi

echo ""
print_status "INFO" "5. RESUMO DO DIAGNÓSTICO"

if [ ${#missing_tables[@]} -eq 0 ]; then
    print_status "OK" "Todas as tabelas críticas existem"
    echo ""
    echo "✅ SCHEMA ESTÁ OK - Não é necessário fazer db:push"
else
    print_status "WARN" "Tabelas faltando: ${missing_tables[*]}"
    echo ""
    echo "🔧 RECOMENDAÇÃO: Executar db:push para criar tabelas"
    echo ""
    echo "COMANDOS PARA CORREÇÃO:"
    echo "   cd $WORKING_DIR"
    echo "   export DATABASE_URL=\"$DATABASE_URL\""
    echo "   npm run db:push --force"
    echo ""
    echo "OU execute o hard-reset completo do vlxsam02:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
fi

echo ""
echo "============================================="