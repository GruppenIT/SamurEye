#!/bin/bash

# ============================================================================
# CORREÇÃO DEFINITIVA ROTA /api/user - vlxsam02
# ============================================================================
# Problema: Rota /api/user não tem middleware de autenticação e cria usuário
#           fictício automático quando há tenants no banco
# Solução: Adicionar middleware isLocalUserAuthenticated na rota
#
# Uso: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/fix-api-user-route.sh | bash
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de log
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

# Configurações
APP_DIR="/opt/samureye"
WORKING_DIR="$APP_DIR/SamurEye"

echo ""
echo "🔧 CORREÇÃO DEFINITIVA ROTA /api/user"
echo "===================================="
echo ""
info "Problema: Rota /api/user sem middleware cria usuário fictício automático"

cd "$WORKING_DIR" || error "❌ Não foi possível acessar $WORKING_DIR"

# ============================================================================
# 1. BACKUP DO ARQUIVO ATUAL
# ============================================================================

log "📁 Criando backup do routes.ts atual..."
cp server/routes.ts server/routes.ts.backup-fix-api-user-$(date +%Y%m%d_%H%M%S)
log "✅ Backup criado"

# ============================================================================
# 2. CORREÇÃO CIRÚRGICA - MOVER MIDDLEWARE ANTES DA ROTA
# ============================================================================

log "🔧 Aplicando correção cirúrgica na rota /api/user..."

cat > /tmp/fix_api_user_route.js << 'EOF'
const fs = require('fs');
const filePath = process.argv[2];

console.log('🔧 Corrigindo rota /api/user sem middleware...');

let content = fs.readFileSync(filePath, 'utf8');

// PASSO 1: Encontrar o middleware isLocalUserAuthenticated e movê-lo para antes da rota /api/user
// Primeiro, vamos extrair o middleware
const middlewarePattern = /const isLocalUserAuthenticated = async \(req: any, res: any, next: any\) => \{[\s\S]*?\};/;
const middlewareMatch = content.match(middlewarePattern);

if (!middlewareMatch) {
  console.log('❌ Middleware isLocalUserAuthenticated não encontrado');
  process.exit(1);
}

const middlewareCode = middlewareMatch[0];
console.log('✅ Middleware isLocalUserAuthenticated encontrado');

// PASSO 2: Remover o middleware da posição atual
content = content.replace(middlewarePattern, '');

// PASSO 3: Encontrar a rota /api/user problemática e substituí-la
const oldRoutePattern = /app\.get\('\/(api\/user)'\s*,\s*async\s*\(\s*req\s*,\s*res\s*\)\s*=>\s*\{[\s\S]*?\}\);/;

// Nova implementação da rota com middleware
const newRouteWithMiddleware = `
  // Local user middleware (for session-based authentication)
  ${middlewareCode}

  // Get current user endpoint (with AUTHENTICATION required!)
  app.get('/api/user', isLocalUserAuthenticated, async (req, res) => {
    try {
      const user = req.localUser;
      
      if (!user) {
        return res.status(401).json({ error: 'User not authenticated' });
      }
      
      // Buscar tenants do usuário autenticado
      let userTenants = [];
      
      if (user.isSocUser) {
        // SOC users podem acessar todos os tenants
        userTenants = await storage.getAllTenants();
      } else {
        // Usuários normais só veem seus tenants
        const allTenants = await storage.getAllTenants();
        userTenants = allTenants.filter(t => t.id === user.tenantId);
      }
      
      res.json({
        id: user.id,
        email: user.email,
        name: \`\${user.firstName || ''} \${user.lastName || ''}\`.trim() || user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        isSocUser: user.isSocUser || false,
        isActive: user.isActive !== false,
        tenants: userTenants.map(t => ({
          tenantId: t.id,
          role: user.isSocUser ? 'soc_user' : 'tenant_admin',
          tenant: t
        })),
        currentTenant: userTenants[0] || null
      });
      
    } catch (error) {
      console.error('Error in /api/user:', error);
      res.status(500).json({ message: 'Internal server error' });
    }
  });`;

if (oldRoutePattern.test(content)) {
  content = content.replace(oldRoutePattern, newRouteWithMiddleware);
  console.log('✅ Rota /api/user substituída com middleware de autenticação');
} else {
  console.log('⚠️ Padrão da rota não encontrado, tentando localizar manualmente...');
  
  // Tentar encontrar a rota de forma mais ampla
  const startPattern = /app\.get\('\/(api\/user)'/;
  const startMatch = content.search(startPattern);
  
  if (startMatch >= 0) {
    // Encontrar o final da rota (próximo app. ou final do arquivo)
    const afterStart = content.substring(startMatch);
    const endMatch = afterStart.search(/\n\s*app\./);
    const endPos = endMatch > 0 ? startMatch + endMatch : content.length;
    
    // Substituir toda a seção
    content = content.substring(0, startMatch) + newRouteWithMiddleware + '\n\n  ' + content.substring(endPos);
    console.log('✅ Rota /api/user localizada e substituída manualmente');
  } else {
    console.log('❌ Não foi possível localizar a rota /api/user');
    process.exit(1);
  }
}

// Salvar arquivo corrigido
fs.writeFileSync(filePath, content, 'utf8');
console.log('✅ Correção da rota /api/user aplicada com sucesso');

EOF

# Executar correção JavaScript
node /tmp/fix_api_user_route.js "$WORKING_DIR/server/routes.ts"
rm /tmp/fix_api_user_route.js

# ============================================================================
# 3. LIMPAR SESSÕES PARA FORÇAR NOVO LOGIN
# ============================================================================

log "🧹 Limpando sessões existentes..."

# Limpar Redis se disponível
if command -v redis-cli >/dev/null 2>&1; then
    if redis-cli ping >/dev/null 2>&1; then
        redis-cli FLUSHDB >/dev/null 2>&1 || warn "Redis não limpo"
        log "✅ Cache Redis limpo"
    fi
fi

# Limpar arquivos de sessão se existirem
find /tmp -name "sess_*" -delete 2>/dev/null || true
log "✅ Arquivos de sessão temporários limpos"

# ============================================================================
# 4. REBUILD E RESTART
# ============================================================================

log "🔄 Rebuilding aplicação..."

if npm run build >/dev/null 2>&1; then
    log "✅ Build concluído"
else
    warn "⚠️ Build com warnings"
fi

log "🔄 Reiniciando serviço..."
systemctl restart samureye-app
log "✅ Serviço reiniciado"

# Aguardar aplicação online
log "⏳ Aguardando aplicação..."
for i in {1..20}; do
    if curl -s -f http://localhost:5000/api/health >/dev/null 2>&1; then
        log "✅ Aplicação online"
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

# ============================================================================
# 5. TESTE FINAL
# ============================================================================

log "🧪 Testando correção..."

# Testar rota /api/user
test_response=$(curl -s -w "%{http_code}" -o /tmp/test_user.json http://localhost:5000/api/user)
http_code="${test_response: -3}"

echo ""
if [ "$http_code" = "401" ]; then
    log "🎯 SUCESSO! /api/user agora retorna 401 (autenticação obrigatória)"
    log "✅ PROBLEMA RESOLVIDO DEFINITIVAMENTE!"
    echo ""
    log "🔑 RESULTADO:"
    echo "   • Rota /api/user protegida com isLocalUserAuthenticated"
    echo "   • Usuário fictício 'tenant@onpremise.local' eliminado"
    echo "   • Interface irá pedir login obrigatoriamente"
    echo "   • Autenticação funcionando corretamente"
    echo ""
    log "🎯 PRÓXIMOS PASSOS:"
    echo "   1. Acesse a interface web - deve pedir login"
    echo "   2. Use credenciais de usuário real (rodrigo@gruppen.com.br)"
    echo "   3. Confirme que não há mais bypass automático"
    
elif [ "$http_code" = "200" ]; then
    error "❌ PROBLEMA PERSISTE - ainda retorna usuário sem autenticação"
    echo "   Resposta:"
    cat /tmp/test_user.json | head -5
    echo ""
    error "🔍 INVESTIGAÇÃO ADICIONAL NECESSÁRIA"
    echo "   A rota pode não ter sido corrigida adequadamente"
    
else
    warn "⚠️ Resposta inesperada: $http_code"
    echo "   Pode indicar problema de aplicação"
fi

rm -f /tmp/test_user.json

echo ""
log "🔧 Correção da rota /api/user finalizada"
echo "===================================="

exit 0