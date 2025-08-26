#!/bin/bash

# Script específico para corrigir problema de conexão na porta 443

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "🔧 Corrigindo problema específico da porta 443"

APP_DIR="/opt/samureye"
WORKING_DIR="$APP_DIR/SamurEye"

# Verificar se diretório da aplicação existe
if [ ! -d "$WORKING_DIR" ]; then
    log "❌ Diretório da aplicação não encontrado: $WORKING_DIR"
    log "ℹ️ Execute install.sh primeiro"
    exit 1
fi

# Parar serviço
log "⏹️ Parando serviço..."
systemctl stop samureye-app 2>/dev/null || true

# 1. Verificar e corrigir arquivo .env
log "1️⃣ Verificando arquivo .env..."
if [ ! -f "$WORKING_DIR/.env" ]; then
    log "🔗 Criando link para .env..."
    ln -sf /etc/samureye/.env "$WORKING_DIR/.env"
    chown -h samureye:samureye "$WORKING_DIR/.env" 2>/dev/null || true
fi

# Verificar conteúdo do .env
if [ -f "/etc/samureye/.env" ]; then
    if grep -q "DATABASE_URL.*5432" /etc/samureye/.env; then
        log "✅ DATABASE_URL correta no .env (porta 5432)"
    else
        log "❌ DATABASE_URL incorreta - corrigindo..."
        sed -i 's|DATABASE_URL=.*|DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod|' /etc/samureye/.env
        log "✅ DATABASE_URL corrigida"
    fi
else
    log "❌ Arquivo .env não encontrado - problema grave!"
    exit 1
fi

# 2. Procurar e corrigir configurações hardcoded
log "2️⃣ Verificando configurações hardcoded..."
cd "$WORKING_DIR"

FOUND_HARDCODED=false

# Procurar por :443 em arquivos de código
if find . -name "*.ts" -o -name "*.js" | xargs grep -l ":443" 2>/dev/null | head -1; then
    log "❌ Encontrada configuração hardcoded :443"
    FOUND_HARDCODED=true
    
    # Corrigir porta 443 para 5432
    find . -name "*.ts" -o -name "*.js" | xargs sed -i 's/:443/:5432/g' 2>/dev/null || true
    log "✅ Porta 443 substituída por 5432"
fi

# Procurar por HTTPS onde deveria ser PostgreSQL
if find . -name "*.ts" -o -name "*.js" | xargs grep -l "https://172.24.1.153" 2>/dev/null | head -1; then
    log "❌ Encontrada URL HTTPS incorreta"
    FOUND_HARDCODED=true
    
    # Corrigir HTTPS para PostgreSQL
    find . -name "*.ts" -o -name "*.js" | xargs sed -i 's|https://172.24.1.153[^"]*|postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod|g' 2>/dev/null || true
    log "✅ URLs HTTPS corrigidas para PostgreSQL"
fi

# Procurar por configurações específicas de conexão com a porta errada
if find . -name "*.ts" -o -name "*.js" | xargs grep -l "172.24.1.153.*443" 2>/dev/null | head -1; then
    log "❌ Encontrada IP:porta específica incorreta"
    FOUND_HARDCODED=true
    
    find . -name "*.ts" -o -name "*.js" | xargs sed -i 's/172\.24\.1\.153.*443/172.24.1.153:5432/g' 2>/dev/null || true
    log "✅ IP:porta corrigida"
fi

if [ "$FOUND_HARDCODED" = true ]; then
    log "⚠️ Configurações hardcoded encontradas e corrigidas"
else
    log "✅ Nenhuma configuração hardcoded encontrada"
fi

# 3. Verificar configuração do Node.js para carregar dotenv
log "3️⃣ Verificando configuração do dotenv..."
if [ -f "package.json" ]; then
    if grep -q '"dotenv"' package.json; then
        log "✅ dotenv está no package.json"
    else
        log "⚠️ dotenv não encontrado - aplicação pode não carregar .env"
    fi
fi

# Verificar se há configuração explícita de dotenv no código
if find . -name "*.ts" -o -name "*.js" | xargs grep -l "dotenv.config\|require.*dotenv" 2>/dev/null | head -1; then
    log "✅ Código configura dotenv explicitamente"
else
    log "⚠️ Código não configura dotenv explicitamente"
    
    # Verificar arquivo principal do servidor
    if [ -f "server/index.ts" ]; then
        if ! head -5 server/index.ts | grep -q "dotenv"; then
            log "🔧 Adicionando configuração dotenv no início do servidor..."
            sed -i '1i import "dotenv/config";' server/index.ts 2>/dev/null || {
                sed -i '1i require("dotenv").config();' server/index.ts 2>/dev/null || true
            }
            log "✅ Configuração dotenv adicionada"
        fi
    fi
fi

cd - >/dev/null

# 4. Limpar cache do Node.js
log "4️⃣ Limpando cache do Node.js..."
rm -rf "$WORKING_DIR/node_modules/.cache" 2>/dev/null || true
rm -rf "$WORKING_DIR/.next" 2>/dev/null || true
rm -rf "$WORKING_DIR/dist" 2>/dev/null || true

# 5. Iniciar serviço
log "🚀 Iniciando serviço..."
systemctl start samureye-app

# Aguardar inicialização
log "⏳ Aguardando inicialização (15 segundos)..."
sleep 15

# 6. Verificar se o problema foi resolvido
log "🧪 Testando conexão pós-correção..."

# Verificar se API responde
if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
    log "✅ API está respondendo"
    
    # Verificar logs para ver se ainda há erro de porta 443
    if journalctl -u samureye-app --since "2 minutes ago" --no-pager -q | grep -q "ECONNREFUSED.*:443"; then
        log "❌ PROBLEMA PERSISTE: Ainda tenta conectar na porta 443"
        echo ""
        echo "📋 LOGS COM ERRO:"
        journalctl -u samureye-app --since "2 minutes ago" --no-pager -q | grep "ECONNREFUSED.*:443" | tail -3
        echo ""
        echo "🔍 PRÓXIMAS AÇÕES RECOMENDADAS:"
        echo "   1. Verificar se há outras configurações hardcoded"
        echo "   2. Reinstalar aplicação completamente (install.sh)"
        echo "   3. Verificar conectividade com vlxsam03"
        exit 1
    else
        log "🎉 PROBLEMA RESOLVIDO: Não há mais erros de conexão porta 443"
        
        # Testar endpoint específico que estava falhando
        RESPONSE=$(curl -s http://localhost:5000/api/system/settings 2>&1 || echo "ERRO")
        if echo "$RESPONSE" | grep -q "systemName\|SamurEye"; then
            log "✅ Endpoint /api/system/settings funcionando corretamente"
        else
            log "⚠️ Endpoint ainda pode ter problemas, mas não é mais o erro da porta 443"
        fi
    fi
else
    log "❌ API não está respondendo"
    log "📋 Verificar logs: journalctl -u samureye-app -f"
    exit 1
fi

echo ""
echo "=== RESUMO DA CORREÇÃO ==="
echo "✅ Arquivo .env verificado e corrigido"
echo "✅ Configurações hardcoded removidas"
echo "✅ Configuração dotenv verificada"
echo "✅ Cache limpo e serviço reiniciado"
echo "✅ Problema da porta 443 resolvido"
echo ""
log "🎯 Correção específica da porta 443 concluída com sucesso!"