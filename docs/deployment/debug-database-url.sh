#!/bin/bash

echo "🔍 DIAGNÓSTICO DATABASE_URL - vlxsam02"
echo "==================================="

echo "📋 Verificando configuração do banco de dados..."

# Verificar arquivo .env
ENV_FILE="/opt/samureye/SamurEye/.env"
if [ -f "$ENV_FILE" ]; then
    echo ""
    echo "✅ Arquivo .env encontrado:"
    echo "📁 $ENV_FILE"
    echo ""
    echo "🔍 Configuração DATABASE_URL:"
    grep "DATABASE_URL" "$ENV_FILE" 2>/dev/null || echo "❌ DATABASE_URL não encontrado no .env"
    
    echo ""
    echo "🔍 Outras configurações de banco:"
    grep -E "(PG|DB|POSTGRES)" "$ENV_FILE" 2>/dev/null || echo "ℹ️ Nenhuma outra configuração de banco encontrada"
else
    echo "❌ Arquivo .env não encontrado em $ENV_FILE"
fi

# Verificar drizzle.config.ts
DRIZZLE_CONFIG="/opt/samureye/SamurEye/drizzle.config.ts"
if [ -f "$DRIZZLE_CONFIG" ]; then
    echo ""
    echo "✅ Arquivo drizzle.config.ts encontrado:"
    echo "📁 $DRIZZLE_CONFIG"
    echo ""
    echo "🔍 Configuração Drizzle:"
    cat "$DRIZZLE_CONFIG" 2>/dev/null
else
    echo "❌ Arquivo drizzle.config.ts não encontrado em $DRIZZLE_CONFIG"
fi

# Testar conectividade DATABASE_URL se existir
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE" 2>/dev/null
    
    if [ -n "$DATABASE_URL" ]; then
        echo ""
        echo "🧪 Testando conectividade com DATABASE_URL..."
        echo "🔗 URL (mascarada): ${DATABASE_URL//\/\/*/\/\/***:***@*}"
        
        # Extrair componentes da URL
        if [[ $DATABASE_URL =~ postgresql://([^:]+):([^@]+)@([^:]+):([^/]+)/(.+) ]]; then
            DB_USER="${BASH_REMATCH[1]}"
            DB_PASS="${BASH_REMATCH[2]}"
            DB_HOST="${BASH_REMATCH[3]}"
            DB_PORT="${BASH_REMATCH[4]}"
            DB_NAME="${BASH_REMATCH[5]}"
            
            echo "   • Host: $DB_HOST"
            echo "   • Port: $DB_PORT"
            echo "   • Database: $DB_NAME"
            echo "   • User: $DB_USER"
            
            # Testar conectividade
            if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" > /dev/null 2>&1; then
                echo "   ✅ Conectividade OK"
                
                # Verificar tabelas neste banco
                echo ""
                echo "📋 Tabelas encontradas neste banco:"
                PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
                    "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;" 2>/dev/null
                    
                # Verificar especificamente collectors
                COLLECTORS_EXISTS=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c \
                    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'collectors');" 2>/dev/null | tr -d ' ')
                
                if [ "$COLLECTORS_EXISTS" = "t" ]; then
                    echo "✅ Tabela collectors EXISTE neste banco"
                    
                    # Contar registros
                    COUNT=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c \
                        "SELECT COUNT(*) FROM collectors;" 2>/dev/null | tr -d ' ')
                    echo "📊 Collectors registrados: $COUNT"
                else
                    echo "❌ Tabela collectors NÃO EXISTE neste banco"
                fi
                
            else
                echo "   ❌ Falha na conectividade"
            fi
        else
            echo "❌ Formato de DATABASE_URL inválido"
        fi
    else
        echo "❌ DATABASE_URL não está definido"
    fi
fi

# Verificar se há um banco local PostgreSQL rodando
echo ""
echo "🔍 Verificando PostgreSQL local no vlxsam02..."
if systemctl is-active --quiet postgresql 2>/dev/null; then
    echo "⚠️ PostgreSQL está rodando LOCALMENTE no vlxsam02"
    echo "   Isso pode estar causando confusão no Drizzle"
    
    # Verificar se há tabelas no banco local
    if sudo -u postgres psql -d postgres -c "SELECT 1" > /dev/null 2>&1; then
        echo ""
        echo "📋 Verificando bancos locais..."
        sudo -u postgres psql -c "\l" 2>/dev/null | grep samureye || echo "   • Banco 'samureye' não existe localmente"
    fi
else
    echo "✅ PostgreSQL NÃO está rodando localmente (correto)"
fi

echo ""
echo "🎯 ANÁLISE:"
echo "💡 Compare os resultados:"
echo "   • DATABASE_URL aponta para: [visto acima]"
echo "   • vlxsam03 deveria ser: 172.24.1.153:5432"
echo "   • Se Drizzle encontra tabelas mas vlxsam03 não tem,"
echo "     então estão usando bancos diferentes!"