#!/bin/bash

# Script para testar instalação do vlxsam02 após execução do install.sh

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "🧪 Testando instalação do vlxsam02..."

echo ""
echo "=== TESTE DE SERVIÇOS ==="

# Verificar serviço
log "📊 Status do serviço samureye-app:"
systemctl is-active samureye-app >/dev/null 2>&1 && {
    log "✅ Serviço está ativo"
    systemctl status samureye-app --no-pager -l | head -10
} || {
    log "❌ Serviço não está ativo"
    systemctl status samureye-app --no-pager -l || true
}

echo ""
echo "=== TESTE DE APIs ==="

# Aguardar um pouco para garantir que a aplicação esteja rodando
sleep 3

# Testar health endpoint
log "🔍 Testando /api/health..."
if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
    log "✅ Health Check: OK"
    curl -s http://localhost:5000/api/health
else
    log "❌ Health Check: FALHA"
fi

echo ""

# Testar endpoint de usuário (deve retornar erro 401)
log "🔍 Testando /api/user (esperado: erro 401)..."
USER_RESPONSE=$(curl -s http://localhost:5000/api/user 2>&1 || true)
if echo "$USER_RESPONSE" | grep -q "autenticado\|401\|Unauthorized"; then
    log "✅ API User: OK (erro 401 esperado)"
    echo "$USER_RESPONSE"
else
    log "⚠️ API User: Resposta inesperada"
    echo "$USER_RESPONSE"
fi

echo ""

# Testar se não está retornando HTML em vez de JSON
log "🔍 Verificando se APIs retornam JSON (não HTML)..."
CONTENT_TYPE=$(curl -s -I http://localhost:5000/api/user 2>/dev/null | grep -i content-type | head -1 || echo "")
if echo "$CONTENT_TYPE" | grep -q "application/json"; then
    log "✅ Content-Type correto: JSON"
else
    log "⚠️ Content-Type pode estar incorreto:"
    echo "$CONTENT_TYPE"
fi

echo ""
echo "=== TESTE DE CONFIGURAÇÕES ==="

# Verificar arquivo .env
log "📁 Verificando arquivo .env..."
if [ -f "/etc/samureye/.env" ]; then
    log "✅ Arquivo .env existe"
    
    # Verificar permissões
    OWNER=$(stat -c '%U:%G' /etc/samureye/.env)
    PERMS=$(stat -c '%a' /etc/samureye/.env)
    
    if [ "$OWNER" = "samureye:samureye" ] && [ "$PERMS" = "644" ]; then
        log "✅ Permissões corretas: $OWNER ($PERMS)"
    else
        log "⚠️ Permissões incorretas: $OWNER ($PERMS)"
    fi
    
    # Verificar URLs importantes
    if grep -q "http://172.24.1.152:5000" /etc/samureye/.env; then
        log "✅ URLs locais configuradas"
    else
        log "⚠️ URLs podem estar incorretas"
    fi
    
    # Verificar se há problemas de sintaxe
    if bash -n /etc/samureye/.env 2>/dev/null; then
        log "✅ Sintaxe do .env está correta"
    else
        log "❌ Problema de sintaxe no .env:"
        bash -n /etc/samureye/.env 2>&1 || true
    fi
else
    log "❌ Arquivo .env não encontrado"
fi

echo ""
echo "=== TESTE DE FERRAMENTAS ==="

# Verificar ferramentas instaladas
TOOLS=("nmap" "nuclei" "masscan" "wscat")
for tool in "${TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        log "✅ $tool: Instalado"
    else
        log "❌ $tool: Não encontrado"
    fi
done

echo ""
echo "=== TESTE DE CONECTIVIDADE ==="

# Testar conectividade com vlxsam03
log "🔗 Testando conectividade com vlxsam03 (172.24.1.153)..."
if ping -c 1 172.24.1.153 >/dev/null 2>&1; then
    log "✅ Conectividade vlxsam03: OK"
else
    log "❌ Conectividade vlxsam03: FALHA"
fi

echo ""
echo "=== TESTE DE LOGS ==="

# Verificar logs recentes
log "📋 Verificando logs recentes do serviço..."
if journalctl -u samureye-app --since "5 minutes ago" --no-pager -q 2>/dev/null | grep -q "serving on port 5000"; then
    log "✅ Aplicação iniciada corretamente"
else
    log "⚠️ Verificar logs - aplicação pode não ter iniciado corretamente"
    echo "Últimas 10 linhas do log:"
    journalctl -u samureye-app --no-pager -n 10 || true
fi

echo ""
echo "=== RESUMO ==="

# Status geral
if systemctl is-active samureye-app >/dev/null 2>&1; then
    if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
        log "🎉 INSTALAÇÃO OK - Serviço ativo e API funcionando"
    else
        log "⚠️ INSTALAÇÃO PARCIAL - Serviço ativo mas API com problemas"
    fi
else
    log "❌ INSTALAÇÃO COM PROBLEMAS - Serviço não está ativo"
fi

echo ""
log "🔧 Para corrigir problemas, use:"
echo "   sudo /path/to/fix-installation.sh"
echo "   sudo journalctl -u samureye-app -f"
echo ""