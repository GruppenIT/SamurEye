#!/bin/bash

# Script para corrigir usuário PostgreSQL no vlxsam03
# Cria/recria o usuário samureye com as permissões corretas

set -e

echo "=== Configurando usuário PostgreSQL no vlxsam03 ==="

# Variáveis
DB_USER="samureye"
DB_PASSWORD="SamurEye2024!"
DB_NAME="samureye_prod"

# Cores para output
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

# Verificar se PostgreSQL está rodando
if ! systemctl is-active --quiet postgresql; then
    print_status "FAIL" "PostgreSQL não está rodando"
    exit 1
fi

print_status "INFO" "Configurando usuário PostgreSQL: $DB_USER"

# Função para executar comandos PostgreSQL
run_psql() {
    local command="$1"
    sudo -u postgres psql -c "$command"
}

# Função para verificar se usuário existe
user_exists() {
    local count=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_user WHERE usename='$DB_USER';" | tr -d ' ')
    [ "$count" -eq "1" ]
}

# Função para verificar se banco existe
db_exists() {
    local count=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_database WHERE datname='$DB_NAME';" | tr -d ' ')
    [ "$count" -eq "1" ]
}

# Verificar e criar banco se não existir
if db_exists; then
    print_status "OK" "Banco '$DB_NAME' já existe"
else
    print_status "INFO" "Criando banco '$DB_NAME'..."
    run_psql "CREATE DATABASE $DB_NAME;"
    print_status "OK" "Banco '$DB_NAME' criado"
fi

# Verificar e configurar usuário
if user_exists; then
    print_status "WARN" "Usuário '$DB_USER' já existe - atualizando senha e permissões..."
    run_psql "ALTER USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
    print_status "OK" "Senha do usuário '$DB_USER' atualizada"
else
    print_status "INFO" "Criando usuário '$DB_USER'..."
    run_psql "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
    print_status "OK" "Usuário '$DB_USER' criado"
fi

# Conceder permissões
print_status "INFO" "Configurando permissões para '$DB_USER'..."

run_psql "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
run_psql "ALTER USER $DB_USER CREATEDB;"

# Conectar ao banco específico e conceder permissões em esquemas
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;"

print_status "OK" "Permissões configuradas para '$DB_USER'"

# Testar conectividade
print_status "INFO" "Testando conectividade..."
if PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
    print_status "OK" "Teste de conectividade local funcionando"
else
    print_status "FAIL" "Teste de conectividade local falhando"
    exit 1
fi

# Verificar configuração pg_hba.conf
print_status "INFO" "Verificando configuração pg_hba.conf..."
PG_HBA_FILE="/etc/postgresql/16/main/pg_hba.conf"

if [ -f "$PG_HBA_FILE" ]; then
    # Verificar se já existe regra para vlxsam02
    if grep -q "host.*$DB_NAME.*$DB_USER.*172.24.1.152" "$PG_HBA_FILE"; then
        print_status "OK" "Regra pg_hba.conf para vlxsam02 já existe"
    else
        print_status "WARN" "Adicionando regra pg_hba.conf para vlxsam02..."
        
        # Backup
        cp "$PG_HBA_FILE" "${PG_HBA_FILE}.backup.$(date +%Y%m%d%H%M)"
        
        # Adicionar regra
        sed -i '/# IPv4 local connections:/a\
# Allow vlxsam02 to connect to samureye_prod\
host    '"$DB_NAME"'    '"$DB_USER"'        172.24.1.152/32         md5' "$PG_HBA_FILE"
        
        # Recarregar PostgreSQL
        systemctl reload postgresql
        print_status "OK" "Regra pg_hba.conf adicionada e PostgreSQL recarregado"
    fi
fi

# Teste final de conectividade remota
print_status "INFO" "Aguardando recarregamento do PostgreSQL..."
sleep 3

print_status "INFO" "Testando conectividade remota do vlxsam02..."
# Este teste será feito do vlxsam02, mas vamos simular localmente primeiro
if PGPASSWORD="$DB_PASSWORD" psql -h 172.24.1.153 -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
    print_status "OK" "Conectividade remota funcionando"
else
    local error_output=$(PGPASSWORD="$DB_PASSWORD" psql -h 172.24.1.153 -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" 2>&1 || true)
    print_status "WARN" "Conectividade remota com problemas: $error_output"
fi

echo ""
print_status "OK" "CONFIGURAÇÃO POSTGRESQL CONCLUÍDA!"
echo ""
print_status "INFO" "Configuração aplicada:"
echo "   - Usuário: $DB_USER"
echo "   - Banco: $DB_NAME" 
echo "   - Senha: [CONFIGURADA]"
echo "   - Permissões: ALL PRIVILEGES"
echo "   - pg_hba.conf: 172.24.1.152/32 permitido"
echo ""
print_status "INFO" "Teste no vlxsam02:"
echo "   PGPASSWORD='$DB_PASSWORD' psql -h 172.24.1.153 -U $DB_USER -d $DB_NAME"
echo ""