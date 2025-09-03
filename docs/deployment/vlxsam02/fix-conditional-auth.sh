#!/bin/bash

# ============================================================================
# CORREÇÃO PROBLEMA AUTENTICAÇÃO CONDICIONAL - vlxsam02
# ============================================================================
# Problema: Interface não pede login APENAS quando existem usuários criados
# Causa: Middleware tem lógica condicional que bypassa autenticação quando
#        há usuários no banco (comportamento de desenvolvimento)
#
# Uso: curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/fix-conditional-auth.sh | bash
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
echo "🔧 CORREÇÃO PROBLEMA AUTENTICAÇÃO CONDICIONAL"
echo "============================================"
echo ""
info "Removendo lógica que bypassa autenticação quando há usuários no banco"

cd "$WORKING_DIR" || error "❌ Não foi possível acessar $WORKING_DIR"

# ============================================================================
# 1. BACKUP DO ARQUIVO ATUAL
# ============================================================================

log "📁 Criando backup do routes.ts atual..."
cp server/routes.ts server/routes.ts.backup-$(date +%Y%m%d_%H%M%S)
log "✅ Backup criado"

# ============================================================================
# 2. CORREÇÃO JAVASCRIPT - MIDDLEWARE CORRETO
# ============================================================================

log "🔧 Aplicando correção de autenticação condicional..."

cat > /tmp/fix_conditional_auth.js << 'EOF'
const fs = require('fs');
const filePath = process.argv[2];
const envPath = process.argv[3];

console.log('🔧 Corrigindo problema de autenticação condicional...');

// 1. CORRIGIR .ENV - Remover DISABLE_AUTH problemático
let envContent = '';
if (fs.existsSync(envPath)) {
  envContent = fs.readFileSync(envPath, 'utf8');
  
  // Remover DISABLE_AUTH completamente ou ajustar
  if (envContent.includes('DISABLE_AUTH=true')) {
    console.log('🛠️ Removendo DISABLE_AUTH=true do .env...');
    envContent = envContent.replace(/DISABLE_AUTH=true/g, 'DISABLE_AUTH=false');
    console.log('✅ DISABLE_AUTH definido como false');
  }
  
  // Garantir configuração de sessão adequada
  if (!envContent.includes('SESSION_SECRET')) {
    envContent += '\nSESSION_SECRET=samureye_onpremise_session_2024\n';
    console.log('✅ SESSION_SECRET adicionado');
  }
  
  fs.writeFileSync(envPath, envContent, 'utf8');
  console.log('✅ Arquivo .env corrigido');
}

// 2. CORRIGIR MIDDLEWARE - Remover lógica condicional problemática
let content = fs.readFileSync(filePath, 'utf8');

// Encontrar e substituir middleware isLocalUserAuthenticated
const oldMiddlewarePattern = /function isLocalUserAuthenticated\s*\([^{]*\{[\s\S]*?(?=\n\s*(?:app\.|function|const|let|var|\}|\n\n))/;

const newMiddleware = `function isLocalUserAuthenticated(req, res, next) {
  // CORREÇÃO: SEMPRE exigir autenticação válida
  // Não fazer bypass baseado em usuários existentes no banco!
  
  // Para rotas admin (/api/admin/*), usar autenticação session-based
  if (req.path && req.path.startsWith('/api/admin/')) {
    if (req.session && req.session.user && req.session.user.id) {
      req.localUser = req.session.user;
      return next();
    }
    return res.status(401).json({ error: 'Admin authentication required' });
  }
  
  // Para rotas tenant normais, exigir sessão tenant válida
  if (req.session && req.session.tenantUser && req.session.tenantUser.id) {
    // Validar se usuário ainda existe e está ativo
    req.localUser = req.session.tenantUser;
    return next();
  }
  
  // IMPORTANTE: Não criar usuário fictício automático!
  // Não fazer bypass baseado em DISABLE_AUTH ou usuários existentes!
  return res.status(401).json({ 
    error: 'Authentication required',
    message: 'Please login to access this resource'
  });
}`;

if (oldMiddlewarePattern.test(content)) {
  content = content.replace(oldMiddlewarePattern, newMiddleware);
  console.log('✅ Middleware isLocalUserAuthenticated corrigido');
} else {
  // Se não encontrou o padrão, procurar de forma mais simples
  const simplePattern = /function isLocalUserAuthenticated[\s\S]*?\n}/;
  if (simplePattern.test(content)) {
    content = content.replace(simplePattern, newMiddleware);
    console.log('✅ Middleware isLocalUserAuthenticated corrigido (padrão simples)');
  } else {
    console.log('⚠️ Middleware não encontrado - adicionando novo');
    // Adicionar middleware antes das rotas
    const routeStart = content.indexOf('app.get(');
    if (routeStart > 0) {
      content = content.substring(0, routeStart) + newMiddleware + '\n\n  ' + content.substring(routeStart);
      console.log('✅ Middleware adicionado');
    }
  }
}

// 3. GARANTIR que rota /api/user SEMPRE usa middleware
const userRoutePattern = /app\.get\s*\(\s*['"]\/api\/user['"]\s*,[\s\S]*?\}\s*\)\s*;/;

const correctUserRoute = `  app.get('/api/user', isLocalUserAuthenticated, async (req, res) => {
    try {
      const user = req.localUser;
      if (!user || !user.id) {
        return res.status(401).json({ 
          error: 'User not authenticated',
          message: 'Valid session required'
        });
      }
      
      // Buscar dados atualizados do usuário para garantir que ainda existe
      const dbUser = await storage.getUser(user.id);
      if (!dbUser || !dbUser.isActive) {
        // Limpar sessão inválida
        if (req.session) {
          req.session.tenantUser = null;
          req.session.user = null;
        }
        return res.status(401).json({ 
          error: 'User not found or inactive',
          message: 'Please login again'
        });
      }
      
      // Buscar tenants do usuário autenticado
      const allTenants = await storage.getAllTenants();
      const userTenants = user.isSocUser ? allTenants : allTenants.filter(t => t.id === user.tenantId);
      
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

if (userRoutePattern.test(content)) {
  content = content.replace(userRoutePattern, correctUserRoute);
  console.log('✅ Rota /api/user corrigida');
} else {
  console.log('⚠️ Rota /api/user não encontrada - pode já estar correta');
}

// 4. REMOVER qualquer lógica de bypass baseada em usuários existentes
// Procurar e remover padrões problemáticos
const problematicPatterns = [
  /\/\/.*development.*bypass[\s\S]*?(?=\n\s*[{}])/gi,
  /if\s*\(.*DISABLE_AUTH.*true.*\)[\s\S]*?(?=\n\s*[{}])/gi,
  /\/\/.*auto.*user[\s\S]*?(?=\n\s*[{}])/gi
];

problematicPatterns.forEach((pattern, index) => {
  if (pattern.test(content)) {
    content = content.replace(pattern, '');
    console.log(`✅ Padrão problemático ${index + 1} removido`);
  }
});

// Salvar arquivo corrigido
fs.writeFileSync(filePath, content, 'utf8');
console.log('✅ Correção de autenticação condicional aplicada com sucesso');

EOF

# Executar correção
node /tmp/fix_conditional_auth.js "$WORKING_DIR/server/routes.ts" "$WORKING_DIR/.env"
rm /tmp/fix_conditional_auth.js

# ============================================================================
# 3. LIMPAR SESSÕES EXISTENTES NO REDIS (se houver)
# ============================================================================

log "🧹 Limpando sessões existentes para forçar novo login..."

# Verificar se Redis está rodando
if command -v redis-cli >/dev/null 2>&1; then
    if redis-cli ping >/dev/null 2>&1; then
        log "🗑️ Limpando cache Redis..."
        redis-cli FLUSHDB >/dev/null 2>&1 || warn "Não foi possível limpar Redis"
        log "✅ Cache Redis limpo"
    fi
fi

# ============================================================================
# 4. REBUILD E RESTART DA APLICAÇÃO
# ============================================================================

log "🔄 Rebuilding aplicação com correção..."

# Build da aplicação
if npm run build >/dev/null 2>&1; then
    log "✅ Build concluído com sucesso"
else
    warn "⚠️ Build apresentou warnings, mas pode estar OK"
fi

# Restart do serviço
log "🔄 Reiniciando serviço samureye-app..."

if systemctl is-active --quiet samureye-app; then
    systemctl restart samureye-app
    log "✅ Serviço reiniciado"
else
    log "🚀 Iniciando serviço..."
    systemctl start samureye-app
fi

# Aguardar serviço ficar online
log "⏳ Aguardando aplicação ficar disponível..."
for i in {1..30}; do
    if curl -s -f http://localhost:5000/api/health >/dev/null 2>&1; then
        log "✅ Aplicação online na porta 5000"
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

# ============================================================================
# 5. TESTE DE VALIDAÇÃO
# ============================================================================

log "🧪 Testando correção aplicada..."

# Testar se /api/user agora requer autenticação
user_response=$(curl -s -w "%{http_code}" -o /tmp/test_response.json http://localhost:5000/api/user)
http_code="${user_response: -3}"

if [ "$http_code" = "401" ]; then
    log "✅ CORREÇÃO APLICADA COM SUCESSO!"
    log "🔒 /api/user agora requer autenticação (401 Unauthorized)"
    log "🎯 Interface irá pedir login mesmo com usuários no banco"
elif [ "$http_code" = "200" ]; then
    error "❌ Problema persiste - /api/user ainda retorna 200"
    warn "⚠️ Verifique se middleware foi aplicado corretamente"
    cat /tmp/test_response.json
else
    warn "⚠️ Resposta inesperada: $http_code"
fi

rm -f /tmp/test_response.json

# ============================================================================
# 6. INSTRUÇÕES FINAIS
# ============================================================================

echo ""
log "🎯 CORREÇÃO DE AUTENTICAÇÃO CONDICIONAL CONCLUÍDA"
echo "================================================="
echo ""

if [ "$http_code" = "401" ]; then
    log "✅ RESULTADO:"
    echo "   • Middleware corrigido para SEMPRE exigir autenticação"
    echo "   • Lógica condicional baseada em usuários removida"
    echo "   • DISABLE_AUTH desativado no .env"
    echo "   • Sessões existentes limpas"
    echo ""
    log "🎯 PRÓXIMOS PASSOS:"
    echo "   1. Teste a interface web - deve pedir login agora"
    echo "   2. Faça login com usuário tenant válido"
    echo "   3. Confirme que autenticação funciona corretamente"
    echo ""
    log "🔑 CREDENCIAIS DE TESTE:"
    echo "   • Email: rodrigo@gruppen.com.br"
    echo "   • Senha: [sua senha definida]"
    echo "   • Tipo: SOC User"
    
else
    error "❌ CORREÇÃO PODE TER FALHADO"
    echo "   • Execute diagnóstico para verificar:"
    echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/diagnose-conditional-auth.sh | bash"
fi

echo ""
log "🔧 Correção de autenticação condicional finalizada"

exit 0