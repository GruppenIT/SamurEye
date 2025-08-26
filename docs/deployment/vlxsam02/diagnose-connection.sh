#!/bin/bash

# Script para diagnosticar problema de conexão porta 443 vs 5432

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "🔍 DIAGNÓSTICO: Problema de conexão porta 443"

echo ""
echo "=== VERIFICAÇÃO DO ARQUIVO .env ==="
if [ -f "/etc/samureye/.env" ]; then
    log "✅ Arquivo .env existe"
    echo "DATABASE_URL configurada:"
    grep "DATABASE_URL" /etc/samureye/.env
    echo ""
    echo "Variáveis de banco:"
    grep -E "^PG" /etc/samureye/.env
else
    log "❌ Arquivo .env não encontrado"
fi

echo ""
echo "=== VERIFICAÇÃO DA APLICAÇÃO ==="

# Encontrar diretório da aplicação
APP_DIRS=("/opt/samureye/SamurEye" "/opt/samureye" "/home/samureye/SamurEye")
FOUND_DIR=""

for dir in "${APP_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        FOUND_DIR="$dir"
        break
    fi
done

if [ -n "$FOUND_DIR" ]; then
    log "✅ Aplicação encontrada em: $FOUND_DIR"
    cd "$FOUND_DIR"
    
    # Verificar se existe .env local
    if [ -f ".env" ]; then
        log "ℹ️ Arquivo .env local encontrado"
        if [ -L ".env" ]; then
            log "🔗 É um link simbólico para: $(readlink .env)"
        else
            log "⚠️ É um arquivo separado (pode estar causando conflito)"
            echo "DATABASE_URL no .env local:"
            grep "DATABASE_URL" .env 2>/dev/null || echo "Não encontrado"
        fi
    else
        log "❌ Arquivo .env local não existe"
        log "🔧 Criando link simbólico..."
        ln -sf /etc/samureye/.env .env
        log "✅ Link criado"
    fi
    
    # Verificar package.json
    if [ -f "package.json" ]; then
        log "📦 package.json encontrado"
        if grep -q '"dotenv"' package.json; then
            log "✅ dotenv está no package.json"
        else
            log "❌ dotenv não encontrado no package.json"
        fi
    fi
    
    # Verificar se há configuração hardcoded
    log "🔍 Procurando configurações hardcoded..."
    if find . -name "*.ts" -o -name "*.js" | xargs grep -l "172.24.1.153:443" 2>/dev/null; then
        log "❌ ENCONTRADA configuração hardcoded para porta 443!"
        echo "Arquivos com configuração incorreta:"
        find . -name "*.ts" -o -name "*.js" | xargs grep -l "172.24.1.153:443" 2>/dev/null
    else
        log "✅ Não há configuração hardcoded para porta 443"
    fi
    
    # Verificar outras configurações de conexão
    if find . -name "*.ts" -o -name "*.js" | xargs grep -l "DATABASE_URL\|ConnectionString" 2>/dev/null; then
        log "ℹ️ Arquivos que usam DATABASE_URL:"
        find . -name "*.ts" -o -name "*.js" | xargs grep -l "DATABASE_URL\|ConnectionString" 2>/dev/null | head -3
    fi
    
else
    log "❌ Aplicação não encontrada em nenhum diretório esperado"
    echo "Diretórios verificados:"
    for dir in "${APP_DIRS[@]}"; do
        echo "  - $dir"
    done
fi

echo ""
echo "=== VERIFICAÇÃO DO SYSTEMD ==="

SERVICE_FILE="/etc/systemd/system/samureye-app.service"
if [ -f "$SERVICE_FILE" ]; then
    log "✅ Arquivo systemd encontrado"
    
    echo "WorkingDirectory:"
    grep "WorkingDirectory" "$SERVICE_FILE" 2>/dev/null || echo "Não configurado"
    
    echo "Environment:"
    grep "Environment" "$SERVICE_FILE" 2>/dev/null || echo "Não configurado"
    
    echo "ExecStart:"
    grep "ExecStart" "$SERVICE_FILE" 2>/dev/null || echo "Não encontrado"
    
else
    log "❌ Arquivo systemd não encontrado"
fi

echo ""
echo "=== TESTE DE CONECTIVIDADE ==="

log "🔗 Testando conectividade PostgreSQL (porta 5432)..."
if nc -z 172.24.1.153 5432 2>/dev/null; then
    log "✅ Porta 5432 acessível"
else
    log "❌ Porta 5432 não acessível"
fi

log "🔗 Testando conectividade porta 443..."
if nc -z 172.24.1.153 443 2>/dev/null; then
    log "✅ Porta 443 acessível (mas não deveria usar)"
else
    log "❌ Porta 443 não acessível (normal)"
fi

echo ""
echo "=== LOGS RECENTES ==="
log "📋 Últimos erros de conexão:"
journalctl -u samureye-app --since "5 minutes ago" --no-pager -q 2>/dev/null | grep -E "(ECONNREFUSED|:443|:5432)" | tail -3

echo ""
echo "=== DIAGNÓSTICO COMPLETO ==="

# Identificar causa mais provável
if [ -f "/etc/samureye/.env" ]; then
    if find "$FOUND_DIR" -name "*.ts" -o -name "*.js" 2>/dev/null | xargs grep -l "172.24.1.153:443" 2>/dev/null >/dev/null; then
        echo "🎯 CAUSA PROVÁVEL: Configuração hardcoded no código"
        echo "   Solução: Remover configuração hardcoded e usar variáveis de ambiente"
    elif [ ! -f "$FOUND_DIR/.env" ]; then
        echo "🎯 CAUSA PROVÁVEL: Aplicação não consegue ler .env"
        echo "   Solução: Criar link simbólico para /etc/samureye/.env"
    elif ! nc -z 172.24.1.153 5432 2>/dev/null; then
        echo "🎯 CAUSA PROVÁVEL: vlxsam03 não acessível"
        echo "   Solução: Verificar conectividade de rede e serviços no vlxsam03"
    else
        echo "🎯 CAUSA PROVÁVEL: Problema de carregamento das variáveis"
        echo "   Solução: Verificar configuração do dotenv ou reiniciar aplicação"
    fi
else
    echo "🎯 CAUSA PROVÁVEL: Arquivo .env não existe"
    echo "   Solução: Executar script de instalação completo"
fi

echo ""
log "🔧 Para corrigir, use:"
echo "   1. bash fix-env-loading.sh    # Corrigir carregamento do .env"
echo "   2. bash install.sh            # Reinstalação completa"
echo "   3. journalctl -u samureye-app -f  # Monitorar logs"