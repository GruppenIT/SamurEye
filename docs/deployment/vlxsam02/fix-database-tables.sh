#!/bin/bash

# Script para criar/atualizar tabelas no banco PostgreSQL
# Resolve o erro "relation 'tenants' does not exist"

set -e

echo "=== Criando Tabelas do Banco SamurEye ==="

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK") echo -e "${GREEN}✅ $message${NC}" ;;
        "FAIL") echo -e "${RED}❌ $message${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "INFO") echo -e "ℹ️  $message" ;;
    esac
}

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    print_status "FAIL" "Este script deve ser executado como root"
    exit 1
fi

# Localizar o projeto SamurEye
PROJECT_DIRS=(
    "/opt/samureye/SamurEye"
    "/opt/samureye"
    "/etc/samureye/SamurEye"
    "/var/www/samureye"
    "/home/samureye/SamurEye"
)

PROJECT_DIR=""
for dir in "${PROJECT_DIRS[@]}"; do
    if [ -d "$dir" ] && [ -f "$dir/package.json" ]; then
        PROJECT_DIR="$dir"
        break
    fi
done

if [ -z "$PROJECT_DIR" ]; then
    print_status "FAIL" "Projeto SamurEye não encontrado"
    print_status "INFO" "Verificando se o serviço está rodando..."
    
    # Tentar encontrar pelo processo
    service_path=$(systemctl show -p ExecStart samureye-app 2>/dev/null | cut -d'=' -f2- | awk '{print $2}' | xargs dirname 2>/dev/null || echo "")
    if [ -n "$service_path" ] && [ -d "$service_path" ]; then
        PROJECT_DIR="$service_path"
        print_status "OK" "Projeto encontrado via serviço: $PROJECT_DIR"
    else
        exit 1
    fi
fi

print_status "OK" "Projeto encontrado: $PROJECT_DIR"

# Verificar se Node.js está disponível
if ! command -v node >/dev/null 2>&1; then
    print_status "WARN" "Node.js não encontrado, instalando..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Verificar se npm está disponível
if ! command -v npm >/dev/null 2>&1; then
    print_status "FAIL" "npm não disponível"
    exit 1
fi

# Navegar para o projeto
cd "$PROJECT_DIR"

# Verificar arquivos necessários
if [ ! -f "package.json" ]; then
    print_status "FAIL" "package.json não encontrado em $PROJECT_DIR"
    exit 1
fi

if [ ! -f "drizzle.config.ts" ]; then
    print_status "FAIL" "drizzle.config.ts não encontrado"
    exit 1
fi

# Verificar .env
env_file=""
for env_path in "/etc/samureye/.env" ".env"; do
    if [ -f "$env_path" ]; then
        env_file="$env_path"
        break
    fi
done

if [ -z "$env_file" ]; then
    print_status "FAIL" "Arquivo .env não encontrado"
    exit 1
fi

print_status "OK" "Usando .env: $env_file"

# Exportar variáveis de ambiente
set -a
source "$env_file"
set +a

# Verificar DATABASE_URL
if [ -z "$DATABASE_URL" ]; then
    print_status "FAIL" "DATABASE_URL não configurada"
    exit 1
fi

print_status "INFO" "DATABASE_URL: $DATABASE_URL"

# Verificar conectividade PostgreSQL
if ! command -v psql >/dev/null 2>&1; then
    print_status "WARN" "psql não encontrado, instalando..."
    apt-get update && apt-get install -y postgresql-client
fi

# Testar conexão
DB_HOST=$(echo "$DATABASE_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p')
DB_PORT=$(echo "$DATABASE_URL" | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
DB_USER=$(echo "$DATABASE_URL" | sed -n 's/.*\/\/\([^:]*\):.*/\1/p')
DB_PASSWORD=$(echo "$DATABASE_URL" | sed -n 's/.*\/\/[^:]*:\([^@]*\)@.*/\1/p')
DB_NAME=$(echo "$DATABASE_URL" | sed -n 's/.*\/\([^?]*\).*/\1/p')

print_status "INFO" "Testando conectividade PostgreSQL..."
if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
    print_status "OK" "Conectividade PostgreSQL funcionando"
else
    print_status "FAIL" "Falha na conectividade PostgreSQL"
    exit 1
fi

# Verificar se Drizzle está instalado
if [ ! -d "node_modules" ]; then
    print_status "WARN" "node_modules não encontrado, instalando dependências..."
    npm install
fi

# Verificar script db:push no package.json
if ! grep -q '"db:push"' package.json; then
    print_status "WARN" "Script db:push não encontrado no package.json"
    print_status "INFO" "Tentando executar drizzle-kit diretamente..."
    
    # Tentar diferentes comandos
    commands=(
        "npx drizzle-kit push:pg"
        "npx drizzle-kit push"
        "node_modules/.bin/drizzle-kit push:pg"
        "node_modules/.bin/drizzle-kit push"
    )
    
    success=false
    for cmd in "${commands[@]}"; do
        print_status "INFO" "Tentando: $cmd"
        if $cmd 2>&1 | tee /tmp/drizzle-output.log; then
            success=true
            break
        fi
    done
    
    if [ "$success" = false ]; then
        print_status "FAIL" "Nenhum comando Drizzle funcionou"
        print_status "INFO" "Última saída:"
        cat /tmp/drizzle-output.log
        exit 1
    fi
else
    # Usar script npm
    print_status "INFO" "Executando npm run db:push..."
    if npm run db:push; then
        print_status "OK" "Migração executada com sucesso"
    else
        print_status "WARN" "Erro na migração, tentando db:push --force..."
        if npm run db:push -- --force; then
            print_status "OK" "Migração forçada executada com sucesso"
        else
            print_status "FAIL" "Migração falhou mesmo com --force"
            exit 1
        fi
    fi
fi

# Verificar se as tabelas foram criadas
print_status "INFO" "Verificando tabelas criadas..."
tables=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public';" 2>/dev/null | tr -d ' ' | grep -v '^$')

if echo "$tables" | grep -q "tenants"; then
    print_status "OK" "Tabela 'tenants' criada com sucesso"
else
    print_status "FAIL" "Tabela 'tenants' não foi criada"
    exit 1
fi

if echo "$tables" | grep -q "users"; then
    print_status "OK" "Tabela 'users' criada com sucesso"
else
    print_status "WARN" "Tabela 'users' não encontrada"
fi

# Listar todas as tabelas criadas
print_status "INFO" "Tabelas encontradas no banco:"
echo "$tables" | while IFS= read -r table; do
    [ -n "$table" ] && echo "   - $table"
done

# Reiniciar o serviço para aplicar mudanças
print_status "INFO" "Reiniciando serviço samureye-app..."
systemctl restart samureye-app

sleep 3

if systemctl is-active --quiet samureye-app; then
    print_status "OK" "Serviço samureye-app reiniciado com sucesso"
else
    print_status "WARN" "Problemas no reinício do serviço"
    print_status "INFO" "Status do serviço:"
    systemctl status samureye-app --no-pager -l
fi

# Teste final
print_status "INFO" "Testando endpoint de criação de tenant..."
sleep 2

response=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:5000/api/admin/tenants \
    -H "Content-Type: application/json" \
    -d '{"name":"Teste Migração","description":"Teste após migração"}' 2>/dev/null || echo "000")

case "$response" in
    "200"|"201") print_status "OK" "Endpoint funcionando (código $response)" ;;
    "401") print_status "WARN" "Endpoint retorna 401 - normal, precisa autenticação" ;;
    "500") print_status "FAIL" "Endpoint ainda retorna 500 - verificar logs" ;;
    "000") print_status "FAIL" "Aplicação não responde" ;;
    *) print_status "WARN" "Endpoint retorna código $response" ;;
esac

echo ""
print_status "OK" "MIGRAÇÃO DE BANCO CONCLUÍDA!"
echo ""
print_status "INFO" "Próximos passos:"
echo "   1. Verificar logs: journalctl -u samureye-app -n 20"
echo "   2. Testar criação de tenant na interface web"
echo "   3. Verificar se erro 'relation tenants does not exist' foi resolvido"
echo ""