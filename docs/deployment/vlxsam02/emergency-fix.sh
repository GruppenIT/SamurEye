#!/bin/bash

# SCRIPT DE CORREÇÃO EMERGENCIAL - vlxsam02
# Usar quando a aplicação está rodando mas a instalação está incompleta

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "🚨 CORREÇÃO EMERGENCIAL - vlxsam02"
log "Problema detectado: Aplicação rodando sem instalação completa"

# Parar serviço atual
log "⏹️ Parando serviço atual..."
systemctl stop samureye-app 2>/dev/null || true

# Verificar se diretórios básicos existem
log "📁 Verificando estrutura de diretórios..."
if [ ! -d "/opt/samureye" ]; then
    log "❌ PROBLEMA CONFIRMADO: Diretório /opt/samureye não existe!"
    log "✅ SOLUÇÃO: Executar instalação completa"
    
    echo ""
    echo "==============================================="
    echo "🔧 DIAGNÓSTICO COMPLETO:"
    echo "==============================================="
    echo "❌ Aplicação está executando sem código fonte"
    echo "❌ Arquivo .env não foi criado"
    echo "❌ Estrutura de diretórios incompleta"
    echo "❌ Configuração de banco incorreta"
    echo ""
    echo "📋 CAUSA RAIZ:"
    echo "   O script install.sh não foi executado corretamente"
    echo "   ou foi interrompido durante a instalação."
    echo ""
    echo "✅ SOLUÇÃO RECOMENDADA:"
    echo "   1. Executar o script de instalação completo:"
    echo "      bash install.sh"
    echo ""
    echo "   2. O script install.sh funcionará como 'reset'"
    echo "      e criará toda a estrutura necessária"
    echo ""
    echo "==============================================="
    
    # Criar um .env temporário para evitar mais erros
    log "🔧 Criando configuração mínima temporária..."
    mkdir -p /etc/samureye
    cat > /etc/samureye/.env << 'EOF'
# CONFIGURAÇÃO TEMPORÁRIA - EXECUTAR install.sh
NODE_ENV=development
PORT=5000
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod
EOF
    
    log "⚠️ Arquivo .env temporário criado em /etc/samureye/.env"
    log "⚠️ IMPORTANTE: Executar install.sh para instalação completa"
    
else
    log "✅ Diretório /opt/samureye existe - problema diferente"
fi

# Verificar arquivo .env
if [ ! -f "/etc/samureye/.env" ]; then
    log "❌ Arquivo .env não existe"
    log "🔧 Criando arquivo .env básico..."
    
    mkdir -p /etc/samureye
    cat > /etc/samureye/.env << 'EOF'
# SamurEye Application - Environment Variables
# Servidor: vlxsam02 (172.24.1.152) 

# Application (Vite Dev Server)
NODE_ENV=development
PORT=5000

# Database (PostgreSQL Local - vlxsam03)
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod
PGHOST=172.24.1.153
PGPORT=5432
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye_prod

# Frontend URLs
FRONTEND_URL=http://172.24.1.152:5000
VITE_API_BASE_URL=http://172.24.1.152:5000
CORS_ORIGINS=http://172.24.1.152:5000

# Delinea Secret Server
DELINEA_BASE_URL=https://gruppenztna.secretservercloud.com/SecretServer
DELINEA_RULE_NAME=SamurEye_Access_Rule
DELINEA_USERNAME=samureye-integration
DELINEA_DOMAIN=GRUPPENZT
DELINEA_GRANT_TYPE=password

# Object Storage
PUBLIC_OBJECT_SEARCH_PATHS=/samureye-bucket/public
PRIVATE_OBJECT_DIR=/samureye-bucket/.private

# Security
SESSION_SECRET=SamurEye2024SecretKeyForSessionManagement
JWT_SECRET=SamurEye2024JWTSecretForTokenSigning

# Logging
LOG_LEVEL=info
LOG_DIR=/opt/samureye/logs
EOF
    
    # Definir permissões corretas
    chown samureye:samureye /etc/samureye/.env 2>/dev/null || true
    chmod 644 /etc/samureye/.env
    
    log "✅ Arquivo .env criado com configurações básicas"
else
    log "✅ Arquivo .env existe"
fi

# Tentar iniciar serviço
log "🚀 Tentando iniciar serviço..."
if systemctl start samureye-app 2>/dev/null; then
    log "✅ Serviço iniciado"
    
    # Aguardar um pouco
    sleep 3
    
    # Testar API
    if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
        log "✅ API funcionando temporariamente"
        echo ""
        echo "🎉 CORREÇÃO TEMPORÁRIA APLICADA COM SUCESSO!"
        echo ""
        echo "⚠️ IMPORTANTE:"
        echo "   Esta é uma correção TEMPORÁRIA"
        echo "   Execute install.sh para instalação completa:"
        echo "   bash install.sh"
    else
        log "❌ API ainda não funciona - problema mais complexo"
        echo ""
        echo "❌ CORREÇÃO TEMPORÁRIA NÃO RESOLVEU O PROBLEMA"
        echo ""
        echo "📋 PRÓXIMOS PASSOS:"
        echo "   1. Executar instalação completa: bash install.sh"
        echo "   2. Verificar logs: journalctl -u samureye-app -f"
    fi
else
    log "❌ Falha ao iniciar serviço"
    echo ""
    echo "❌ SERVIÇO NÃO PODE SER INICIADO"
    echo ""
    echo "📋 SOLUÇÃO OBRIGATÓRIA:"
    echo "   Execute a instalação completa: bash install.sh"
fi

echo ""
log "🔧 Correção emergencial concluída"