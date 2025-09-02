#!/bin/bash

# ============================================================================
# SAMUREYE FIX ADMIN FRONTEND - CORREÇÃO DEFINITIVA DA AUTENTICAÇÃO
# ============================================================================
# Corrige o endpoint /api/admin/me para verificar sessão real
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

log "🔧 CORREÇÃO DEFINITIVA - Frontend Admin Authentication"

# Parar serviço
log "⏸️ Parando aplicação..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# Backup do arquivo original
log "💾 Fazendo backup do routes.ts..."
cp "$WORKING_DIR/server/routes.ts" "$WORKING_DIR/server/routes.ts.backup-$(date +%Y%m%d_%H%M%S)"

log "📝 Corrigindo endpoint /api/admin/me..."

# Corrigir o endpoint /api/admin/me para verificar sessão real
cat > /tmp/admin_me_fix.js << 'EOF'
const fs = require('fs');

const filePath = '/opt/samureye/SamurEye/server/routes.ts';
let content = fs.readFileSync(filePath, 'utf8');

// Substituir o endpoint /api/admin/me
const oldEndpoint = `  // Check admin authentication status - Public for on-premise
  app.get('/api/admin/me', async (req, res) => {
    try {
      // In on-premise environment, always allow admin access
      res.json({ 
        isAuthenticated: true, 
        email: 'admin@onpremise.local',
        isAdmin: true 
      });
    } catch (error) {
      res.status(500).json({ message: 'Erro na verificação de autenticação' });
    }
  });`;

const newEndpoint = `  // Check admin authentication status - Fixed for on-premise
  app.get('/api/admin/me', async (req, res) => {
    try {
      // Check if admin session exists (proper authentication check)
      const adminUser = (req.session as any)?.adminUser;
      
      if (adminUser?.isAdmin) {
        res.json({ 
          isAuthenticated: true, 
          email: adminUser.email || 'admin@onpremise.local',
          isAdmin: true 
        });
      } else {
        res.json({ 
          isAuthenticated: false,
          isAdmin: false 
        });
      }
    } catch (error) {
      res.status(500).json({ message: 'Erro na verificação de autenticação' });
    }
  });`;

content = content.replace(oldEndpoint, newEndpoint);
fs.writeFileSync(filePath, content, 'utf8');
console.log('✅ Endpoint /api/admin/me corrigido');
EOF

# Executar correção
node /tmp/admin_me_fix.js

# Limpar arquivo temporário
rm /tmp/admin_me_fix.js

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
    
    log "🧪 Testando novo comportamento..."
    
    # Testar endpoint sem autenticação
    UNAUTH_RESPONSE=$(curl -s "http://localhost:5000/api/admin/me" | jq -r '.isAuthenticated' 2>/dev/null || echo "error")
    
    if [ "$UNAUTH_RESPONSE" = "false" ]; then
        log "✅ Endpoint /api/admin/me agora retorna corretamente isAuthenticated: false"
        
        log "🔐 Testando login admin..."
        # Fazer login e testar
        curl -s -X POST "http://localhost:5000/api/admin/login" \
            -H "Content-Type: application/json" \
            -d '{"email":"admin@samureye.com.br","password":"SamurEye2024!"}' \
            -c /tmp/admin_session_test.txt >/dev/null
        
        # Testar endpoint com autenticação
        AUTH_RESPONSE=$(curl -s -b /tmp/admin_session_test.txt "http://localhost:5000/api/admin/me" | jq -r '.isAuthenticated' 2>/dev/null || echo "error")
        
        if [ "$AUTH_RESPONSE" = "true" ]; then
            log "✅ Após login, endpoint retorna corretamente isAuthenticated: true"
            log "✅ CORREÇÃO APLICADA COM SUCESSO!"
        else
            warn "⚠️ Login não está funcionando corretamente"
        fi
        
        # Cleanup
        rm -f /tmp/admin_session_test.txt
        
    else
        warn "⚠️ Endpoint ainda retorna isAuthenticated incorretamente"
    fi
    
    log "📋 NOVA EXPERIÊNCIA DO USUÁRIO:"
    echo "════════════════════════════════════════"
    echo "1. Acesse: http://172.24.1.152:5000/admin"
    echo "2. Agora verá tela de LOGIN (não mais direto dashboard)"
    echo "3. Credenciais:"
    echo "   Email: admin@samureye.com.br"
    echo "   Senha: SamurEye2024!"
    echo "4. Após login, poderá criar tenants normalmente"
    echo "════════════════════════════════════════"
    
else
    error "❌ Falha ao reiniciar aplicação"
    journalctl -u "$SERVICE_NAME" --no-pager -l | tail -10
fi

log "🔧 Correção definitiva concluída!"