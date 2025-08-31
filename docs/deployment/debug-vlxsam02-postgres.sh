#!/bin/bash
# Debug específico para problema PostgreSQL vlxsam02 -> vlxsam03

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔍 Debug PostgreSQL vlxsam02 → vlxsam03"
echo "======================================="

# Verificar conectividade de rede
log "🌐 Testando conectividade de rede..."

if ping -c 2 vlxsam03 >/dev/null 2>&1; then
    log "✅ vlxsam03 acessível via ping"
else
    log "❌ vlxsam03 não responde ao ping"
    exit 1
fi

# Testar porta PostgreSQL
log "🔌 Testando porta PostgreSQL 5432..."

if timeout 5 bash -c "</dev/tcp/vlxsam03/5432" 2>/dev/null; then
    log "✅ Porta 5432 acessível"
else
    log "❌ Porta 5432 não acessível"
fi

# Verificar se postgresql-client está instalado
log "📦 Verificando cliente PostgreSQL..."

if command -v psql >/dev/null 2>&1; then
    log "✅ psql instalado: $(psql --version)"
else
    log "📦 Instalando postgresql-client..."
    apt-get update >/dev/null 2>&1
    apt-get install -y postgresql-client >/dev/null 2>&1
    log "✅ postgresql-client instalado"
fi

# Testar conexão com diferentes URLs
log "🔐 Testando diferentes URLs de conexão..."

URLS=(
    "postgresql://samureye:SamurEye2024%21@vlxsam03:5432/samureye"
    "postgresql://samureye:SamurEye2024!@vlxsam03:5432/samureye"
    "postgresql://postgres:SamurEye2024%21@vlxsam03:5432/samureye"
    "postgresql://postgres:SamurEye2024!@vlxsam03:5432/samureye"
)

for url in "${URLS[@]}"; do
    log "🧪 Testando: $url"
    if echo "SELECT version();" | psql "$url" >/dev/null 2>&1; then
        log "✅ SUCESSO com: $url"
        WORKING_URL="$url"
        break
    else
        log "❌ Falhou"
    fi
done

if [ -n "$WORKING_URL" ]; then
    log "🎯 URL funcional encontrada: $WORKING_URL"
    
    # Verificar schema
    log "📋 Verificando tabelas disponíveis..."
    echo "\\dt" | psql "$WORKING_URL" 2>/dev/null || log "Erro ao listar tabelas"
    
    # Verificar collectors
    log "👥 Verificando collectors cadastrados..."
    echo "SELECT id, name, tenant_id, status FROM collectors LIMIT 5;" | psql "$WORKING_URL" 2>/dev/null || log "Tabela collectors não existe"
    
else
    log "❌ Nenhuma URL funcionou - verificar credenciais"
fi

# Verificar aplicação SamurEye
log "🖥️ Verificando aplicação SamurEye..."

APP_DIR="/opt/samureye/SamurEye"
if [ -f "$APP_DIR/.env" ]; then
    log "📄 Arquivo .env encontrado:"
    grep -E "DATABASE_URL|DB_" "$APP_DIR/.env" | sed 's/=.*/=***/' || log "Nenhuma config de DB no .env"
else
    log "⚠️ Arquivo .env não encontrado"
fi

# Verificar se app está usando DATABASE_URL correto
log "🔍 Verificando variáveis de ambiente do processo..."

PID=$(pgrep -f "samureye\|SamurEye" | head -1)
if [ -n "$PID" ]; then
    log "📍 Processo encontrado (PID: $PID)"
    if [ -f "/proc/$PID/environ" ]; then
        ENV_VARS=$(tr '\0' '\n' < "/proc/$PID/environ" | grep -E "DATABASE_URL|DB_" | sed 's/=.*/=***/')
        if [ -n "$ENV_VARS" ]; then
            log "🔧 Variáveis de ambiente do processo:"
            echo "$ENV_VARS"
        else
            log "⚠️ Nenhuma variável DATABASE_URL encontrada no processo"
        fi
    fi
else
    log "⚠️ Processo da aplicação não encontrado"
fi

# Verificar logs da aplicação
log "📝 Últimos logs da aplicação..."
journalctl -u samureye-app --since "5 minutes ago" | grep -E "(database|postgres|connection|error)" | tail -10 || log "Nenhum log relevante encontrado"

echo ""
log "💡 DIAGNÓSTICO COMPLETO"
echo "======================="

if [ -n "$WORKING_URL" ]; then
    echo "✅ PostgreSQL funcionando"
    echo "✅ Conectividade OK"
    echo "🔧 Problema: Aplicação pode estar usando URL incorreta"
    echo ""
    echo "🚀 SOLUÇÕES:"
    echo "1. Atualizar .env na aplicação:"
    echo "   echo 'DATABASE_URL=$WORKING_URL' >> $APP_DIR/.env"
    echo ""
    echo "2. Reiniciar aplicação:"
    echo "   systemctl restart samureye-app"
    echo ""
    echo "3. Verificar logs após restart:"
    echo "   journalctl -u samureye-app -f"
else
    echo "❌ PostgreSQL não acessível"
    echo "🔧 Problema: Credenciais ou configuração de rede"
    echo ""
    echo "🚀 SOLUÇÕES:"
    echo "1. Verificar PostgreSQL no vlxsam03:"
    echo "   systemctl status postgresql"
    echo ""
    echo "2. Verificar configuração pg_hba.conf"
    echo "3. Verificar firewall na porta 5432"
fi

exit 0