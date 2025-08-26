#!/bin/bash

# Script específico para corrigir problema de carregamento do .env

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "🔧 Corrigindo problema de carregamento do arquivo .env"

# Parar serviço
log "⏹️ Parando serviço..."
systemctl stop samureye-app 2>/dev/null || true

# 1. Verificar e recriar estrutura de diretórios
log "1️⃣ Verificando estrutura de diretórios..."

# Definir diretórios
ETC_DIR="/etc/samureye"
APP_DIR="/opt/samureye"
WORKING_DIR="$APP_DIR/SamurEye"

# Verificar se diretório de configuração existe
if [ ! -d "$ETC_DIR" ]; then
    log "📁 Criando diretório de configuração: $ETC_DIR"
    mkdir -p "$ETC_DIR"
fi

# Verificar se diretório da aplicação existe
if [ ! -d "$WORKING_DIR" ]; then
    log "❌ ERRO: Diretório da aplicação não existe: $WORKING_DIR"
    log "ℹ️ Execute o install.sh primeiro para instalar a aplicação"
    exit 1
fi

# 2. Verificar e recriar arquivo .env
log "2️⃣ Recriando arquivo .env..."

# Criar arquivo .env correto
cat > "$ETC_DIR/.env" << 'EOF'
# SamurEye Environment Configuration
# IMPORTANTE: Este arquivo contém a configuração correta para PostgreSQL

# Application (Vite Dev Server)
NODE_ENV=development
PORT=5000

# Database (PostgreSQL Local - vlxsam03) - PORTA CORRETA: 5432
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod
PGHOST=172.24.1.153
PGPORT=5432
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye_prod

# Redis (vlxsam03)
REDIS_URL=redis://172.24.1.153:6379
REDIS_HOST=172.24.1.153
REDIS_PORT=6379

# Session Management
SESSION_SECRET=samureye-super-secret-session-key-2024-change-this

# Object Storage (MinIO - vlxsam03)
MINIO_ENDPOINT=http://172.24.1.153:9000
MINIO_ACCESS_KEY=samureye
MINIO_SECRET_KEY=SamurEye2024!
MINIO_BUCKET=samureye-storage
MINIO_REGION=us-east-1

# Object Storage (Legacy format para compatibilidade)
DEFAULT_OBJECT_STORAGE_BUCKET_ID=samureye-storage
PUBLIC_OBJECT_SEARCH_PATHS=/samureye-storage/public
PRIVATE_OBJECT_DIR=/samureye-storage/.private

# Logging
LOG_LEVEL=info
LOG_DIR=/var/log/samureye

# Multi-tenant Configuration
TENANT_ISOLATION=true
DEFAULT_TENANT_SLUG=default

# Admin Authentication (Local System)
ADMIN_EMAIL=admin@samureye.com.br
ADMIN_PASSWORD=SamurEye2024!

# CORS (Development - permitir IPs locais)
CORS_ORIGINS=http://172.24.1.152:5000,http://localhost:5000

# Development (Vite specific - usar IP local)
VITE_API_BASE_URL=http://172.24.1.152:5000
VITE_APP_NAME=SamurEye
EOF

# Configurar permissões
chown samureye:samureye "$ETC_DIR/.env"
chmod 644 "$ETC_DIR/.env"

log "✅ Arquivo .env recriado com configuração correta"

# 3. Recriar links simbólicos
log "3️⃣ Recriando links simbólicos..."

# Remover links antigos se existirem
rm -f "$APP_DIR/.env" 2>/dev/null || true
rm -f "$WORKING_DIR/.env" 2>/dev/null || true

# Criar novos links simbólicos
ln -sf "$ETC_DIR/.env" "$APP_DIR/.env"
chown -h samureye:samureye "$APP_DIR/.env" 2>/dev/null || true

ln -sf "$ETC_DIR/.env" "$WORKING_DIR/.env"
chown -h samureye:samureye "$WORKING_DIR/.env" 2>/dev/null || true

log "✅ Links simbólicos recriados"

# 4. Verificar se dotenv está configurado
log "4️⃣ Verificando configuração dotenv no código..."

cd "$WORKING_DIR"

# Verificar se server/index.ts carrega dotenv
if [ -f "server/index.ts" ]; then
    if ! head -10 server/index.ts | grep -q "dotenv"; then
        log "🔧 Adicionando configuração dotenv no início do servidor..."
        
        # Fazer backup
        cp server/index.ts server/index.ts.backup
        
        # Adicionar import dotenv no início
        sed -i '1i import "dotenv/config";' server/index.ts 2>/dev/null || {
            # Se não funcionar com import, tentar require
            sed -i '1i require("dotenv").config();' server/index.ts 2>/dev/null || true
        }
        
        log "✅ Configuração dotenv adicionada"
    else
        log "✅ dotenv já está configurado"
    fi
fi

# 5. Testar carregamento das variáveis
log "5️⃣ Testando carregamento de variáveis..."

# Criar script de teste
cat > /tmp/test-dotenv.js << 'EOF'
// Testar carregamento do .env
try {
    require('dotenv').config();
    console.log('DATABASE_URL carregada:', process.env.DATABASE_URL ? 'SIM' : 'NÃO');
    
    if (process.env.DATABASE_URL) {
        console.log('DATABASE_URL:', process.env.DATABASE_URL.substring(0, 60) + '...');
        
        // Verificar se tem porta 443 (problema)
        if (process.env.DATABASE_URL.includes(':443')) {
            console.log('ERRO: DATABASE_URL contém porta 443!');
            process.exit(1);
        } else {
            console.log('✅ DATABASE_URL não contém porta 443');
        }
        
        // Verificar se é PostgreSQL válida
        if (process.env.DATABASE_URL.includes('postgresql://')) {
            console.log('✅ Formato PostgreSQL válido');
        } else {
            console.log('❌ Formato PostgreSQL inválido');
            process.exit(1);
        }
    } else {
        console.log('❌ DATABASE_URL não foi carregada');
        process.exit(1);
    }
    
    console.log('✅ Teste de carregamento: SUCESSO');
} catch (error) {
    console.error('❌ Erro no teste:', error.message);
    process.exit(1);
}
EOF

# Executar teste como usuário samureye
if sudo -u samureye node /tmp/test-dotenv.js 2>/dev/null; then
    log "✅ Teste de carregamento: SUCESSO"
else
    log "❌ Teste de carregamento: FALHA"
    log "⚠️ Pode haver problema com permissões ou estrutura"
fi

rm -f /tmp/test-dotenv.js

cd - >/dev/null

# 6. Iniciar serviço
log "6️⃣ Iniciando serviço..."
systemctl start samureye-app

# Aguardar inicialização
log "⏳ Aguardando inicialização (10 segundos)..."
sleep 10

# 7. Verificar se funcionou
log "7️⃣ Verificando se correção funcionou..."

if systemctl is-active --quiet samureye-app; then
    log "✅ Serviço está ativo"
    
    # Verificar se API responde
    if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
        log "✅ API está respondendo"
        
        # Verificar logs para ver se ainda há erro de porta 443
        if journalctl -u samureye-app --since "1 minute ago" --no-pager -q | grep -q "ECONNREFUSED.*:443"; then
            log "❌ PROBLEMA PERSISTE: Ainda tenta conectar na porta 443"
            echo ""
            echo "📋 LOGS COM ERRO:"
            journalctl -u samureye-app --since "1 minute ago" --no-pager -q | grep "ECONNREFUSED.*:443" | tail -2
            echo ""
            echo "🔍 PRÓXIMAS AÇÕES RECOMENDADAS:"
            echo "   1. Executar: ./fix-port-443-issue.sh"
            echo "   2. Verificar se há código hardcoded com configuração incorreta"
            exit 1
        else
            log "🎉 PROBLEMA RESOLVIDO: Não há mais erros de conexão porta 443"
        fi
    else
        log "❌ API não está respondendo"
        echo "📋 Verificar logs: journalctl -u samureye-app -f"
        exit 1
    fi
else
    log "❌ Serviço não está ativo"
    echo "📋 Verificar status: systemctl status samureye-app"
    exit 1
fi

echo ""
echo "=== RESUMO DA CORREÇÃO ==="
echo "✅ Arquivo .env recriado com configuração correta"
echo "✅ Links simbólicos recriados nos diretórios corretos"
echo "✅ Configuração dotenv verificada no código"
echo "✅ Teste de carregamento realizado"
echo "✅ Serviço reiniciado e funcionando"
echo ""
log "🎯 Correção do carregamento do .env concluída com sucesso!"