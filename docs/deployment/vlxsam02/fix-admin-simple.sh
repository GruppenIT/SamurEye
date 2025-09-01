#!/bin/bash

# ============================================================================
# SAMUREYE FIX ADMIN - SOLUÇÃO SIMPLES PARA AUTENTICAÇÃO ADMIN
# ============================================================================
# Configura automaticamente admin na sessão para ambiente on-premise
# ============================================================================

set -e

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }

log "🔧 CORREÇÃO AUTENTICAÇÃO ADMIN - MÉTODO SIMPLES"

# Fazer login admin
log "🔐 Fazendo login admin..."
curl -s -X POST "http://localhost:5000/api/admin/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@samureye.com.br","password":"SamurEye2024!"}' \
    -c /tmp/admin_session.txt >/dev/null

log "✅ Sessão admin criada"

# Testar acesso
log "🧪 Testando acesso aos tenants..."
RESULT=$(curl -s -b /tmp/admin_session.txt "http://localhost:5000/api/admin/tenants" || echo "ERRO")

if [[ "$RESULT" == *"ERRO"* ]] || [[ "$RESULT" == *"Acesso negado"* ]]; then
    log "❌ Ainda sem acesso"
else
    log "✅ Acesso funcionando!"
fi

log "📋 INSTRUÇÕES PARA O USUÁRIO:"
echo "════════════════════════════════════════"
echo "Para acessar o painel admin:"
echo ""
echo "1. Abra: http://172.24.1.152:5000/admin" 
echo "2. No console do navegador (F12), execute:"
echo ""
echo "   fetch('/api/admin/login', {"
echo "     method: 'POST',"
echo "     headers: {'Content-Type': 'application/json'},"
echo "     body: JSON.stringify({"
echo "       email: 'admin@samureye.com.br',"
echo "       password: 'SamurEye2024!'"
echo "     })"
echo "   }).then(() => location.reload())"
echo ""
echo "3. Recarregue a página"
echo "4. Agora pode criar tenants!"
echo ""
echo "Credenciais admin:"
echo "Email: admin@samureye.com.br"
echo "Senha: SamurEye2024!"
echo "════════════════════════════════════════"

# Cleanup
rm -f /tmp/admin_session.txt

log "🔧 Pronto!"