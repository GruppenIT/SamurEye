#!/bin/bash

# Script para testar especificamente a conectividade PostgreSQL do vlxsam02 -> vlxsam03
# Foca em autenticação e problemas de credenciais

set -e

echo "=== Teste de Conectividade PostgreSQL vlxsam02 -> vlxsam03 ==="

# Variáveis
POSTGRES_HOST="172.24.1.153"
POSTGRES_PORT="5432"
DB_NAME="samureye_prod"
DB_USER="samureye"
DB_PASSWORD="SamurEye2024!"

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

echo "📊 Testando com credenciais:"
echo "   Host: $POSTGRES_HOST:$POSTGRES_PORT"
echo "   Banco: $DB_NAME"
echo "   Usuário: $DB_USER"
echo "   Senha: [OMITIDA]"
echo ""

# Teste 1: Conectividade básica de rede
print_status "INFO" "TESTE 1: Conectividade de rede..."
if timeout 5 bash -c "</dev/tcp/$POSTGRES_HOST/$POSTGRES_PORT" 2>/dev/null; then
    print_status "OK" "Porta PostgreSQL acessível"
else
    print_status "FAIL" "Porta PostgreSQL não acessível"
    exit 1
fi

# Teste 2: Instalar psql se necessário
if ! command -v psql >/dev/null 2>&1; then
    print_status "WARN" "psql não encontrado, instalando..."
    apt-get update && apt-get install -y postgresql-client
fi

# Teste 3: Conectividade PostgreSQL detalhada
print_status "INFO" "TESTE 2: Autenticação PostgreSQL..."

# Capturar saída detalhada
output=$(PGPASSWORD="$DB_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT current_user, current_database(), version();" 2>&1)
exit_code=$?

if [ $exit_code -eq 0 ]; then
    print_status "OK" "Conectividade PostgreSQL funcionando!"
    echo ""
    print_status "INFO" "Informações da conexão:"
    echo "$output" | grep -E "(current_user|current_database|PostgreSQL)"
    echo ""
else
    print_status "FAIL" "Falha na autenticação PostgreSQL"
    echo ""
    print_status "INFO" "Erro detalhado:"
    echo "$output"
    echo ""
    
    # Analisar tipo de erro
    if echo "$output" | grep -q "authentication failed"; then
        print_status "WARN" "Problema identificado: SENHA INCORRETA"
        print_status "INFO" "Soluções:"
        echo "   1. Verificar senha no vlxsam03"
        echo "   2. Executar no vlxsam03: bash docs/deployment/vlxsam03/fix-pg-user.sh"
        
    elif echo "$output" | grep -q "no pg_hba.conf entry"; then
        print_status "WARN" "Problema identificado: PG_HBA.CONF"
        print_status "INFO" "Soluções:"
        echo "   1. Executar no vlxsam03: bash docs/deployment/vlxsam03/fix-pg-hba.sh"
        echo "   2. Ou executar: bash docs/deployment/vlxsam03/fix-pg-user.sh (mais completo)"
        
    elif echo "$output" | grep -q "database.*does not exist"; then
        print_status "WARN" "Problema identificado: BANCO NÃO EXISTE"
        print_status "INFO" "Soluções:"
        echo "   1. Executar no vlxsam03: bash docs/deployment/vlxsam03/fix-pg-user.sh"
        
    elif echo "$output" | grep -q "role.*does not exist"; then
        print_status "WARN" "Problema identificado: USUÁRIO NÃO EXISTE"
        print_status "INFO" "Soluções:"
        echo "   1. Executar no vlxsam03: bash docs/deployment/vlxsam03/fix-pg-user.sh"
        
    else
        print_status "WARN" "Erro não identificado automaticamente"
        print_status "INFO" "Recomendação:"
        echo "   1. Executar diagnóstico completo no vlxsam03"
        echo "   2. Verificar logs PostgreSQL: journalctl -u postgresql -n 20"
    fi
    
    exit 1
fi

# Teste 4: Teste de permissões
print_status "INFO" "TESTE 3: Verificando permissões..."

# Testar criação de tabela temporária
perm_test=$(PGPASSWORD="$DB_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
CREATE TEMP TABLE test_permissions (id serial, data text);
INSERT INTO test_permissions (data) VALUES ('test');
SELECT COUNT(*) FROM test_permissions;
DROP TABLE test_permissions;
" 2>&1)
perm_exit_code=$?

if [ $perm_exit_code -eq 0 ]; then
    print_status "OK" "Permissões de escrita funcionando"
else
    print_status "WARN" "Problemas de permissões detectados"
    echo "$perm_test"
fi

# Teste 5: Verificar .env local
print_status "INFO" "TESTE 4: Verificando configuração local..."

if [ -f "/opt/samureye/.env" ] || [ -f "/etc/samureye/.env" ]; then
    env_file="/opt/samureye/.env"
    [ -f "/etc/samureye/.env" ] && env_file="/etc/samureye/.env"
    
    print_status "OK" "Arquivo .env encontrado: $env_file"
    
    # Verificar DATABASE_URL
    if grep -q "DATABASE_URL.*$POSTGRES_HOST" "$env_file"; then
        print_status "OK" "DATABASE_URL configurada corretamente"
        
        # Extrair e testar a URL
        db_url=$(grep "^DATABASE_URL=" "$env_file" | cut -d'=' -f2- | tr -d '"')
        print_status "INFO" "DATABASE_URL: $db_url"
        
        # Testar a URL (se possível)
        if echo "$db_url" | grep -q "$POSTGRES_HOST:$POSTGRES_PORT"; then
            print_status "OK" "URL aponta para o servidor correto"
        else
            print_status "WARN" "URL pode estar incorreta"
        fi
    else
        print_status "WARN" "DATABASE_URL não encontrada ou incorreta"
    fi
else
    print_status "WARN" "Arquivo .env não encontrado"
fi

# Teste 6: Teste do endpoint da aplicação
print_status "INFO" "TESTE 5: Verificando aplicação SamurEye..."

if systemctl is-active --quiet samureye-app; then
    print_status "OK" "Serviço samureye-app ativo"
    
    # Testar endpoint que usa banco
    sleep 2
    http_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/admin/tenants 2>/dev/null || echo "000")
    
    case "$http_response" in
        "200") print_status "OK" "Endpoint admin/tenants funcionando (200)" ;;
        "401") print_status "WARN" "Endpoint retorna 401 - problema de autenticação da aplicação" ;;
        "500") print_status "FAIL" "Endpoint retorna 500 - provavelmente problema de banco" ;;
        "000") print_status "FAIL" "Aplicação não responde" ;;
        *) print_status "WARN" "Endpoint retorna código $http_response" ;;
    esac
else
    print_status "FAIL" "Serviço samureye-app inativo"
fi

echo ""
print_status "INFO" "RESUMO DAS RECOMENDAÇÕES:"
echo ""
print_status "INFO" "Para corrigir problemas PostgreSQL (mais comum):"
echo "   # No vlxsam03:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam03/fix-pg-user.sh | sudo bash"
echo ""
print_status "INFO" "Para diagnóstico completo:"
echo "   # No vlxsam02:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/diagnose-pg-connection.sh | sudo bash"
echo ""
print_status "INFO" "Teste concluído"