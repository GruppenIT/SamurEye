#!/bin/bash

# Script para diagnosticar problemas de conectividade PostgreSQL do vlxsam02 -> vlxsam03
# Identifica rapidamente problemas de pg_hba.conf, rede, usuário, etc.

set -e

echo "=== Diagnóstico de Conectividade PostgreSQL vlxsam02 -> vlxsam03 ==="

# Variáveis
VLXSAM03_IP="172.24.1.153"
PG_PORT="5432"
DB_NAME="samureye_prod"
DB_USER="samureye"
DB_PASSWORD="SamurEye2024!"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para print colorido
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

# Teste 1: Conectividade de rede
test_network() {
    echo ""
    echo "🌐 TESTE 1: Conectividade de Rede"
    echo "================================"
    
    if ping -c 3 "$VLXSAM03_IP" >/dev/null 2>&1; then
        print_status "OK" "Ping para vlxsam03 ($VLXSAM03_IP) funcionando"
    else
        print_status "FAIL" "Ping para vlxsam03 ($VLXSAM03_IP) falhando"
        return 1
    fi
    
    if nc -z "$VLXSAM03_IP" "$PG_PORT" 2>/dev/null; then
        print_status "OK" "Porta PostgreSQL ($PG_PORT) acessível"
    else
        print_status "FAIL" "Porta PostgreSQL ($PG_PORT) não acessível"
        return 1
    fi
}

# Teste 2: Conectividade PostgreSQL básica
test_pg_connection() {
    echo ""
    echo "🐘 TESTE 2: Conectividade PostgreSQL"
    echo "==================================="
    
    # Testar com psql se disponível
    if command -v psql >/dev/null 2>&1; then
        print_status "INFO" "Testando conexão PostgreSQL com psql..."
        
        # Tentar conectar (vai falhar se pg_hba.conf não permitir)
        if PGPASSWORD="$DB_PASSWORD" psql -h "$VLXSAM03_IP" -p "$PG_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
            print_status "OK" "Conexão PostgreSQL funcionando"
        else
            print_status "FAIL" "Conexão PostgreSQL falhando - provavelmente pg_hba.conf"
            
            # Tentar identificar o erro específico
            local error_output=$(PGPASSWORD="$DB_PASSWORD" psql -h "$VLXSAM03_IP" -p "$PG_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" 2>&1 || true)
            
            if echo "$error_output" | grep -q "no pg_hba.conf entry"; then
                print_status "WARN" "Erro identificado: pg_hba.conf não permite conexão"
                print_status "INFO" "Execute no vlxsam03: docs/deployment/vlxsam03/fix-pg-hba.sh"
            elif echo "$error_output" | grep -q "authentication failed"; then
                print_status "WARN" "Erro identificado: Usuário/senha incorretos"
            elif echo "$error_output" | grep -q "database.*does not exist"; then
                print_status "WARN" "Erro identificado: Banco 'samureye_prod' não existe"
            else
                print_status "WARN" "Erro não identificado: $error_output"
            fi
            
            return 1
        fi
    else
        print_status "WARN" "psql não encontrado, instalando..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y postgresql-client
        fi
    fi
}

# Teste 3: Verificar variáveis de ambiente
test_env_vars() {
    echo ""
    echo "🔧 TESTE 3: Variáveis de Ambiente"
    echo "================================"
    
    if [ -f "/opt/samureye/.env" ]; then
        print_status "OK" "Arquivo .env encontrado"
        
        local db_url=$(grep "^DATABASE_URL=" /opt/samureye/.env | cut -d'=' -f2- | tr -d '"')
        if [ -n "$db_url" ]; then
            print_status "OK" "DATABASE_URL configurada"
            print_status "INFO" "DATABASE_URL: $db_url"
            
            # Verificar se a URL aponta para vlxsam03
            if echo "$db_url" | grep -q "$VLXSAM03_IP"; then
                print_status "OK" "DATABASE_URL aponta para vlxsam03"
            else
                print_status "WARN" "DATABASE_URL não aponta para vlxsam03"
            fi
        else
            print_status "FAIL" "DATABASE_URL não encontrada no .env"
        fi
    else
        print_status "FAIL" "Arquivo .env não encontrado em /opt/samureye/"
    fi
}

# Teste 4: Status do serviço SamurEye
test_service_status() {
    echo ""
    echo "🔧 TESTE 4: Status do Serviço SamurEye"
    echo "====================================="
    
    if systemctl is-active --quiet samureye-app; then
        print_status "OK" "Serviço samureye-app ativo"
    else
        print_status "FAIL" "Serviço samureye-app inativo"
    fi
    
    # Verificar logs recentes
    print_status "INFO" "Últimos logs do serviço:"
    journalctl -u samureye-app --no-pager -n 5 --since "5 minutes ago" | grep -E "(error|Error|ERROR|FATAL)" || print_status "OK" "Nenhum erro recente nos logs"
}

# Teste 5: Conectividade HTTP da aplicação
test_app_connectivity() {
    echo ""
    echo "🌐 TESTE 5: Conectividade HTTP da Aplicação"
    echo "==========================================="
    
    if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
        print_status "OK" "Endpoint /api/health respondendo"
    else
        print_status "FAIL" "Endpoint /api/health não respondendo"
    fi
    
    # Testar endpoint que usa banco (admin stats)
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/admin/stats 2>/dev/null || echo "000")
    case "$response" in
        "200") print_status "OK" "Endpoint /api/admin/stats funcionando (200)" ;;
        "500") print_status "FAIL" "Endpoint /api/admin/stats com erro de servidor (500) - provavelmente banco" ;;
        "000") print_status "FAIL" "Aplicação não está respondendo" ;;
        *) print_status "WARN" "Endpoint /api/admin/stats retornou código: $response" ;;
    esac
}

# Função para sugerir soluções
suggest_solutions() {
    echo ""
    echo "🔧 SOLUÇÕES RECOMENDADAS"
    echo "========================"
    
    print_status "INFO" "Se o erro é 'no pg_hba.conf entry':"
    echo "   1. Execute no vlxsam03: bash docs/deployment/vlxsam03/fix-pg-hba.sh"
    echo ""
    
    print_status "INFO" "Se a rede não funciona:"
    echo "   1. Verificar firewall nos servidores"
    echo "   2. Verificar se PostgreSQL está rodando no vlxsam03"
    echo ""
    
    print_status "INFO" "Se o serviço está falhando:"
    echo "   1. Reiniciar: systemctl restart samureye-app"
    echo "   2. Verificar logs: journalctl -u samureye-app -f"
    echo ""
}

# Função principal
main() {
    echo "🚀 Iniciando diagnóstico de conectividade PostgreSQL"
    echo "📅 $(date)"
    echo "🖥️  vlxsam02 -> vlxsam03 (${VLXSAM03_IP}:${PG_PORT})"
    
    local tests_passed=0
    local total_tests=5
    
    # Executar testes
    test_network && ((tests_passed++)) || true
    test_pg_connection && ((tests_passed++)) || true
    test_env_vars && ((tests_passed++)) || true
    test_service_status && ((tests_passed++)) || true
    test_app_connectivity && ((tests_passed++)) || true
    
    echo ""
    echo "📊 RESUMO DOS TESTES"
    echo "==================="
    echo "Testes aprovados: $tests_passed/$total_tests"
    
    if [ "$tests_passed" -eq "$total_tests" ]; then
        print_status "OK" "Todos os testes passaram - sistema funcionando!"
    else
        print_status "WARN" "Alguns testes falharam - verificar soluções abaixo"
        suggest_solutions
    fi
    
    echo ""
    print_status "INFO" "Diagnóstico concluído"
}

# Executar função principal
main "$@"