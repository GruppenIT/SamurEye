#!/bin/bash

# ============================================================================
# SAMUREYE FIX ADMIN REDIRECT - CORREÇÃO DO REDIRECIONAMENTO PÓS-LOGIN
# ============================================================================
# Corrige o redirecionamento após login admin usando window.location.href
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; }

# Configurações
APP_USER="samureye"
WORKING_DIR="/opt/samureye/SamurEye"
SERVICE_NAME="samureye-app"

log "🔧 CORREÇÃO - Redirecionamento Admin após Login"

# Parar serviço
log "⏸️ Parando aplicação..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# Backup do arquivo original
log "💾 Fazendo backup do AdminLogin.tsx..."
cp "$WORKING_DIR/client/src/pages/AdminLogin.tsx" "$WORKING_DIR/client/src/pages/AdminLogin.tsx.backup-$(date +%Y%m%d_%H%M%S)"

log "📝 Corrigindo redirecionamento pós-login..."

# Corrigir o redirecionamento no AdminLogin
cat > /tmp/redirect_fix.js << 'EOF'
const fs = require('fs');

const filePath = '/opt/samureye/SamurEye/client/src/pages/AdminLogin.tsx';
let content = fs.readFileSync(filePath, 'utf8');

// Substituir o setLocation por window.location.href
const oldRedirect = 'setLocation("/admin/dashboard");';
const newRedirect = `// Force refresh of admin auth status after successful login
        window.location.href = "/admin/dashboard";`;

if (content.includes(oldRedirect)) {
    content = content.replace(oldRedirect, newRedirect);
    fs.writeFileSync(filePath, content, 'utf8');
    console.log('✅ Redirecionamento corrigido');
} else {
    console.log('⚠️ Redirecionamento já pode ter sido corrigido');
}
EOF

# Executar correção
node /tmp/redirect_fix.js

# Limpar arquivo temporário
rm /tmp/redirect_fix.js

log "🔨 Fazendo rebuild da aplicação..."
cd "$WORKING_DIR"

# Build da aplicação
sudo -u "$APP_USER" npm run build

log "🚀 Reiniciando aplicação..."
systemctl start "$SERVICE_NAME"

# Aguardar inicialização
sleep 10

# Verificar status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Aplicação reiniciada com sucesso"
    
    log "📋 NOVA EXPERIÊNCIA DO USUÁRIO:"
    echo "════════════════════════════════════════"
    echo "1. Acesse: http://172.24.1.152:5000/admin"
    echo "2. Faça login com admin@samureye.com.br / SamurEye2024!"
    echo "3. Agora será redirecionado corretamente para o dashboard"
    echo "4. Pode criar tenants normalmente"
    echo "════════════════════════════════════════"
    
else
    error "❌ Falha ao reiniciar aplicação"
    journalctl -u "$SERVICE_NAME" --no-pager -l | tail -10
fi

log "🔧 Correção de redirecionamento concluída!"