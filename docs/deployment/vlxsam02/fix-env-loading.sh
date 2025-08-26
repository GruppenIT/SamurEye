#!/bin/bash

# Script para corrigir carregamento do arquivo .env no vlxsam02

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "🔧 Corrigindo carregamento do arquivo .env"

APP_DIR="/opt/samureye/SamurEye"

# Verificar se aplicação existe
if [ ! -d "$APP_DIR" ]; then
    log "❌ Aplicação não encontrada em $APP_DIR"
    log "ℹ️ Execute install.sh primeiro"
    exit 1
fi

log "📁 Aplicação encontrada em: $APP_DIR"

# Verificar arquivo .env principal
if [ -f "/etc/samureye/.env" ]; then
    log "✅ Arquivo .env encontrado em /etc/samureye/.env"
    
    # Criar link simbólico no diretório da aplicação
    log "🔗 Criando link simbólico para .env..."
    ln -sf /etc/samureye/.env "$APP_DIR/.env"
    
    # Ajustar permissões
    chown -h samureye:samureye "$APP_DIR/.env" 2>/dev/null || true
    
    log "✅ Link simbólico criado: $APP_DIR/.env -> /etc/samureye/.env"
else
    log "❌ Arquivo .env não encontrado em /etc/samureye/.env"
    exit 1
fi

# Verificar se há arquivo package.json e se usa dotenv
if [ -f "$APP_DIR/package.json" ]; then
    log "📦 Verificando configuração do Node.js..."
    
    # Verificar se dotenv está instalado
    if grep -q '"dotenv"' "$APP_DIR/package.json"; then
        log "✅ dotenv encontrado no package.json"
    else
        log "⚠️ dotenv não encontrado - pode precisar ser adicionado"
    fi
fi

# Verificar configuração do systemd
SERVICE_FILE="/etc/systemd/system/samureye-app.service"
if [ -f "$SERVICE_FILE" ]; then
    log "🔧 Verificando configuração do systemd..."
    
    # Verificar se WorkingDirectory está correto
    if grep -q "WorkingDirectory=$APP_DIR" "$SERVICE_FILE"; then
        log "✅ WorkingDirectory correto no systemd"
    else
        log "⚠️ WorkingDirectory pode estar incorreto"
        
        # Mostrar configuração atual
        echo "Configuração atual:"
        grep -n "WorkingDirectory" "$SERVICE_FILE" 2>/dev/null || echo "WorkingDirectory não encontrado"
    fi
    
    # Verificar se Environment está configurado
    if grep -q "Environment.*NODE_ENV" "$SERVICE_FILE"; then
        log "✅ Environment configurado no systemd"
    else
        log "⚠️ Environment pode não estar configurado"
    fi
fi

# Testar se o arquivo .env é lido corretamente
log "🧪 Testando carregamento do .env..."
cd "$APP_DIR"

# Criar script de teste temporário
cat > /tmp/test-env.js << 'EOF'
require('dotenv').config();
console.log('NODE_ENV:', process.env.NODE_ENV);
console.log('DATABASE_URL:', process.env.DATABASE_URL ? 'Configurado' : 'NÃO encontrado');
console.log('PGHOST:', process.env.PGHOST || 'NÃO encontrado');
console.log('PGPORT:', process.env.PGPORT || 'NÃO encontrado');
EOF

if command -v node >/dev/null 2>&1; then
    log "📋 Resultado do teste:"
    node /tmp/test-env.js 2>/dev/null || {
        log "❌ Erro ao testar carregamento do .env"
        log "ℹ️ Pode ser necessário instalar dotenv ou configurar carregamento manual"
    }
    rm -f /tmp/test-env.js
else
    log "⚠️ Node.js não encontrado no PATH"
fi

# Reiniciar serviço para aplicar mudanças
log "🔄 Reiniciando serviço..."
systemctl restart samureye-app

# Aguardar inicialização
sleep 3

# Verificar status
if systemctl is-active --quiet samureye-app; then
    log "✅ Serviço reiniciado com sucesso"
    
    # Testar API
    if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
        log "✅ API respondendo corretamente"
        
        # Verificar se erro de conexão persiste
        log "🔍 Verificando logs recentes..."
        if journalctl -u samureye-app --since "1 minute ago" --no-pager -q | grep -q "ECONNREFUSED.*:443"; then
            log "❌ Erro de conexão porta 443 ainda presente"
            log "ℹ️ Problema pode ser na configuração da aplicação, não no .env"
        else
            log "✅ Erro de conexão corrigido"
        fi
    else
        log "❌ API ainda não responde"
    fi
else
    log "❌ Falha ao reiniciar serviço"
    log "📋 Verificar logs: journalctl -u samureye-app -f"
fi

log "🔧 Correção do .env concluída"