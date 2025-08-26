#!/bin/bash

# Script para diagnosticar problemas de conexão específicos

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

echo "🔍 DIAGNÓSTICO DE CONEXÃO - SamurEye vlxsam02"
echo "============================================="

WORKING_DIR="/opt/samureye/SamurEye"

# 1. Verificar se arquivo .env existe e está acessível
log "1️⃣ Verificando arquivo .env..."

if [ -f "$WORKING_DIR/.env" ]; then
    log "✅ Arquivo .env existe: $WORKING_DIR/.env"
    
    # Verificar se é um link simbólico
    if [ -L "$WORKING_DIR/.env" ]; then
        LINK_TARGET=$(readlink "$WORKING_DIR/.env")
        log "🔗 É um link simbólico para: $LINK_TARGET"
        
        if [ -f "$LINK_TARGET" ]; then
            log "✅ Arquivo de destino existe"
        else
            log "❌ Arquivo de destino não existe!"
        fi
    else
        log "📄 É um arquivo regular"
    fi
    
    # Verificar conteúdo básico
    if grep -q "DATABASE_URL" "$WORKING_DIR/.env"; then
        DATABASE_URL=$(grep "DATABASE_URL" "$WORKING_DIR/.env" | cut -d'=' -f2- | tr -d '"'"'"' ')
        log "📋 DATABASE_URL encontrada: ${DATABASE_URL:0:50}..."
        
        # Verificar se contém porta 443 (problema conhecido)
        if echo "$DATABASE_URL" | grep -q ":443"; then
            log "❌ PROBLEMA: DATABASE_URL contém porta 443!"
        else
            log "✅ DATABASE_URL não contém porta 443"
        fi
        
        # Verificar se é PostgreSQL válida
        if echo "$DATABASE_URL" | grep -q "postgresql://"; then
            log "✅ Format PostgreSQL válido"
        else
            log "❌ Formato PostgreSQL inválido"
        fi
    else
        log "❌ DATABASE_URL não encontrada no .env"
    fi
else
    log "❌ Arquivo .env não existe: $WORKING_DIR/.env"
fi

# 2. Verificar se processo Node.js consegue acessar variáveis de ambiente
log ""
log "2️⃣ Testando carregamento de variáveis de ambiente..."

cd "$WORKING_DIR" 2>/dev/null || {
    log "❌ Não foi possível acessar diretório: $WORKING_DIR"
    exit 1
}

# Criar um script Node.js temporário para testar
cat > /tmp/test-env.js << 'EOF'
require('dotenv').config();
console.log('DATABASE_URL loaded:', process.env.DATABASE_URL ? 'YES' : 'NO');
if (process.env.DATABASE_URL) {
    console.log('DATABASE_URL value:', process.env.DATABASE_URL.substring(0, 50) + '...');
    if (process.env.DATABASE_URL.includes(':443')) {
        console.log('ERROR: Contains port 443!');
        process.exit(1);
    }
}
EOF

# Testar como usuário samureye
if sudo -u samureye node /tmp/test-env.js 2>/dev/null; then
    log "✅ Node.js carrega variáveis de ambiente corretamente"
else
    log "❌ Node.js não consegue carregar variáveis de ambiente"
    
    # Testar sem dotenv (variáveis do sistema)
    if sudo -u samureye bash -c "cd $WORKING_DIR && DATABASE_URL=\$(grep DATABASE_URL .env 2>/dev/null | cut -d'=' -f2- | tr -d '\"') node -e \"console.log('Env var:', process.env.DATABASE_URL || 'NOT_FOUND')\""; then
        log "ℹ️ Variável pode estar sendo carregada de outra forma"
    fi
fi

rm -f /tmp/test-env.js

# 3. Verificar logs do serviço para erros específicos
log ""
log "3️⃣ Verificando logs recentes do serviço..."

if systemctl is-active --quiet samureye-app; then
    log "✅ Serviço está ativo"
else
    log "❌ Serviço não está ativo"
fi

# Procurar por erros específicos
log "🔍 Procurando por erros conhecidos nos logs:"

# Erro de conexão porta 443
if journalctl -u samureye-app --since "10 minutes ago" --no-pager -q | grep -q "ECONNREFUSED.*:443"; then
    log "❌ ENCONTRADO: Tentativa de conexão na porta 443"
    echo "Últimas ocorrências:"
    journalctl -u samureye-app --since "10 minutes ago" --no-pager -q | grep "ECONNREFUSED.*:443" | tail -3 | sed 's/^/   /'
else
    log "✅ Não há erros de conexão porta 443"
fi

# Erro de arquivo .env não encontrado
if journalctl -u samureye-app --since "10 minutes ago" --no-pager -q | grep -q "\.env.*not found\|ENOENT.*\.env"; then
    log "❌ ENCONTRADO: Arquivo .env não encontrado"
else
    log "✅ Não há erros de .env não encontrado"
fi

# Erro de variável DATABASE_URL
if journalctl -u samureye-app --since "10 minutes ago" --no-pager -q | grep -q "DATABASE_URL.*undefined\|DATABASE_URL.*not"; then
    log "❌ ENCONTRADO: Problema com DATABASE_URL"
else
    log "✅ Não há erros com DATABASE_URL"
fi

# 4. Testar conectividade com PostgreSQL
log ""
log "4️⃣ Testando conectividade PostgreSQL..."

if command -v psql >/dev/null 2>&1; then
    export PGPASSWORD=SamurEye2024!
    
    if psql -h 172.24.1.153 -U samureye -d samureye_prod -c "SELECT 1;" >/dev/null 2>&1; then
        log "✅ Conectividade PostgreSQL: OK"
    else
        log "❌ Conectividade PostgreSQL: FALHA"
        log "⚠️ Verifique se vlxsam03 está funcionando"
    fi
else
    log "⚠️ Cliente psql não instalado - não foi possível testar"
fi

# 5. Verificar configurações de rede
log ""
log "5️⃣ Verificando configuração de rede..."

# Verificar resolução DNS
if host 172.24.1.153 >/dev/null 2>&1; then
    log "✅ Resolução de IP: OK"
else
    log "⚠️ Problema com resolução de IP"
fi

# Verificar conectividade na porta 5432
if timeout 5 bash -c "echo >/dev/tcp/172.24.1.153/5432" 2>/dev/null; then
    log "✅ Conectividade porta 5432: OK"
else
    log "❌ Conectividade porta 5432: FALHA"
fi

# Verificar se não está tentando conectar na porta 443
if timeout 5 bash -c "echo >/dev/tcp/172.24.1.153/443" 2>/dev/null; then
    log "⚠️ Porta 443 está aberta (pode estar causando confusão)"
else
    log "✅ Porta 443 não está acessível (correto para PostgreSQL)"
fi

echo ""
echo "=== RESUMO DO DIAGNÓSTICO ==="

# Determinar problema principal
PROBLEMA_PRINCIPAL=""

if [ ! -f "$WORKING_DIR/.env" ]; then
    PROBLEMA_PRINCIPAL="Arquivo .env não existe"
elif journalctl -u samureye-app --since "10 minutes ago" --no-pager -q | grep -q "ECONNREFUSED.*:443"; then
    PROBLEMA_PRINCIPAL="Tentativa de conexão na porta 443 em vez de 5432"
elif ! systemctl is-active --quiet samureye-app; then
    PROBLEMA_PRINCIPAL="Serviço não está executando"
elif ! timeout 5 bash -c "echo >/dev/tcp/172.24.1.153/5432" 2>/dev/null; then
    PROBLEMA_PRINCIPAL="Não consegue conectar com PostgreSQL na porta 5432"
else
    PROBLEMA_PRINCIPAL="Problema não identificado - verifique logs detalhados"
fi

echo "🎯 Problema Principal: $PROBLEMA_PRINCIPAL"
echo ""

if [ "$PROBLEMA_PRINCIPAL" = "Tentativa de conexão na porta 443 em vez de 5432" ]; then
    echo "🔧 SOLUÇÃO RECOMENDADA:"
    echo "   ./fix-port-443-issue.sh"
elif [ "$PROBLEMA_PRINCIPAL" = "Arquivo .env não existe" ]; then
    echo "🔧 SOLUÇÃO RECOMENDADA:"
    echo "   ./fix-env-loading.sh"
elif [ "$PROBLEMA_PRINCIPAL" = "Não consegue conectar com PostgreSQL na porta 5432" ]; then
    echo "🔧 SOLUÇÃO RECOMENDADA:"
    echo "   Verificar se vlxsam03 está funcionando"
    echo "   ssh para vlxsam03 e executar: systemctl status postgresql"
fi

cd - >/dev/null