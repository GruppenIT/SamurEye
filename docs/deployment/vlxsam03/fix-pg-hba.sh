#!/bin/bash

# Script para corrigir configuração pg_hba.conf no vlxsam03
# Permite conexões do vlxsam02 (172.24.1.152) ao banco samureye_prod

set -e

echo "=== Configurando pg_hba.conf para permitir conexões do vlxsam02 ==="

# Variáveis
PG_VERSION="16"
PG_HBA_FILE="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"
VLXSAM02_IP="172.24.1.152"

# Função para verificar se a regra já existe
check_existing_rule() {
    if grep -q "host.*samureye_prod.*samureye.*${VLXSAM02_IP}" "$PG_HBA_FILE"; then
        echo "✅ Regra para vlxsam02 já existe no pg_hba.conf"
        return 0
    else
        echo "❌ Regra para vlxsam02 não encontrada no pg_hba.conf"
        return 1
    fi
}

# Função para backup do arquivo original
backup_pg_hba() {
    if [ ! -f "${PG_HBA_FILE}.backup.$(date +%Y%m%d)" ]; then
        echo "📋 Fazendo backup do pg_hba.conf..."
        cp "$PG_HBA_FILE" "${PG_HBA_FILE}.backup.$(date +%Y%m%d)"
        echo "✅ Backup criado: ${PG_HBA_FILE}.backup.$(date +%Y%m%d)"
    fi
}

# Função para adicionar regra de conexão
add_connection_rule() {
    echo "🔧 Adicionando regra para permitir conexão do vlxsam02..."
    
    # Adiciona a regra antes das regras locais
    sed -i '/# IPv4 local connections:/a\
# Allow vlxsam02 to connect to samureye_prod\
host    samureye_prod    samureye        172.24.1.152/32         md5' "$PG_HBA_FILE"
    
    echo "✅ Regra adicionada ao pg_hba.conf"
}

# Função para recarregar configuração PostgreSQL
reload_postgresql() {
    echo "🔄 Recarregando configuração PostgreSQL..."
    systemctl reload postgresql
    echo "✅ PostgreSQL recarregado"
}

# Função para testar conectividade
test_connection() {
    echo "🧪 Testando conectividade do vlxsam02..."
    
    # Testa se o usuário samureye pode conectar
    if sudo -u postgres psql -h localhost -d samureye_prod -U samureye -c "SELECT 1;" >/dev/null 2>&1; then
        echo "✅ Teste de conectividade local OK"
    else
        echo "⚠️  Teste de conectividade local falhou - verificar usuário/senha"
    fi
}

# Função principal
main() {
    echo "🚀 Iniciando correção do pg_hba.conf no vlxsam03"
    
    # Verificar se é root
    if [ "$EUID" -ne 0 ]; then
        echo "❌ Este script deve ser executado como root"
        exit 1
    fi
    
    # Verificar se PostgreSQL está rodando
    if ! systemctl is-active --quiet postgresql; then
        echo "❌ PostgreSQL não está rodando"
        exit 1
    fi
    
    # Verificar se arquivo pg_hba.conf existe
    if [ ! -f "$PG_HBA_FILE" ]; then
        echo "❌ Arquivo pg_hba.conf não encontrado: $PG_HBA_FILE"
        exit 1
    fi
    
    echo "📁 Arquivo pg_hba.conf: $PG_HBA_FILE"
    
    # Verificar se regra já existe
    if check_existing_rule; then
        echo "ℹ️  Configuração já está correta"
        reload_postgresql
        test_connection
        exit 0
    fi
    
    # Fazer backup
    backup_pg_hba
    
    # Adicionar regra
    add_connection_rule
    
    # Recarregar PostgreSQL
    reload_postgresql
    
    # Testar conectividade
    test_connection
    
    echo ""
    echo "✅ CONCLUÍDO: pg_hba.conf configurado com sucesso!"
    echo ""
    echo "📋 Configuração adicionada:"
    echo "   host    samureye_prod    samureye        172.24.1.152/32         md5"
    echo ""
    echo "🔄 Para verificar se está funcionando, teste no vlxsam02:"
    echo "   psql -h 172.24.1.153 -U samureye -d samureye_prod"
    echo ""
}

# Executar função principal
main "$@"