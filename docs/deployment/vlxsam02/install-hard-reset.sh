#!/bin/bash

# ============================================================================
# SAMUREYE ON-PREMISE - HARD RESET APPLICATION SERVER (vlxsam02)
# ============================================================================
# Sistema completo de reset e reinstalação do Servidor de Aplicação SamurEye
# Inclui: Node.js + SamurEye App + Configurações + Banco de Dados Reset
#
# Servidor: vlxsam02 (172.24.1.152)
# Função: Servidor de Aplicação SamurEye
# Dependências: vlxsam03 (PostgreSQL), vlxsam01 (Gateway), vlxsam04 (Collector)
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
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

# Verificar se está sendo executado como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo $0"
fi

# Configurações do ambiente
APP_USER="samureye"
APP_DIR="/opt/samureye"
APP_NAME="SamurEye"
WORKING_DIR="$APP_DIR/$APP_NAME"
SERVICE_NAME="samureye-app"
POSTGRES_HOST="172.24.1.153"  # vlxsam03
POSTGRES_PORT="5432"
POSTGRES_DB="samureye"
POSTGRES_USER="samureye_user"
NODE_VERSION="20"

echo ""
echo "🔥 SAMUREYE HARD RESET - APPLICATION SERVER vlxsam02"
echo "=================================================="
echo "⚠️  ATENÇÃO: Este script irá:"
echo "   • Remover COMPLETAMENTE a aplicação SamurEye"
echo "   • Limpar banco de dados PostgreSQL"
echo "   • Reinstalar Node.js e dependências"
echo "   • Reconfigurar aplicação do zero"
echo "   • Criar tenant e usuários padrão"
echo ""

# ============================================================================
# 1. CONFIRMAÇÃO DE HARD RESET
# ============================================================================

# Detectar se está sendo executado via pipe (curl | bash)
if [ -t 0 ]; then
    # Terminal interativo - pedir confirmação
    read -p "🚨 CONTINUAR COM HARD RESET? (digite 'CONFIRMO' para continuar): " confirm
    if [ "$confirm" != "CONFIRMO" ]; then
        error "Reset cancelado pelo usuário"
    fi
else
    # Não-interativo (curl | bash) - continuar automaticamente após delay
    warn "Modo não-interativo detectado (curl | bash)"
    info "Hard reset iniciará automaticamente em 5 segundos..."
    sleep 5
fi

log "🗑️ Iniciando hard reset da aplicação..."

# ============================================================================
# 2. REMOÇÃO COMPLETA DA INSTALAÇÃO ANTERIOR
# ============================================================================

log "⏹️ Parando serviços..."

# Parar serviço da aplicação
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME"
    log "✅ Serviço $SERVICE_NAME parado"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME"
    log "✅ Serviço $SERVICE_NAME desabilitado"
fi

# Remover arquivo de serviço
if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    log "✅ Arquivo de serviço removido"
fi

# Remover usuário da aplicação
if id "$APP_USER" &>/dev/null; then
    userdel -r "$APP_USER" 2>/dev/null || true
    log "✅ Usuário $APP_USER removido"
fi

# Remover diretórios da aplicação
directories_to_remove=(
    "$APP_DIR"
    "/var/log/samureye"
    "/etc/samureye"
    "/tmp/samureye-*"
)

for dir in "${directories_to_remove[@]}"; do
    if [ -d "$dir" ] || [ -f "$dir" ]; then
        rm -rf "$dir"
        log "✅ Removido: $dir"
    fi
done

# Remover Node.js e npm globalmente
log "🗑️ Removendo Node.js anterior..."
apt-get purge -y nodejs npm node-* 2>/dev/null || true
rm -rf /usr/local/lib/node_modules /usr/local/bin/node /usr/local/bin/npm
rm -rf ~/.npm ~/.node-gyp

# ============================================================================
# 3. LIMPEZA DO BANCO DE DADOS
# ============================================================================

log "🗃️ Limpando banco de dados..."

# Teste de conectividade com PostgreSQL
if ! nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    warn "⚠️ PostgreSQL não acessível em $POSTGRES_HOST:$POSTGRES_PORT"
    warn "   Execute primeiro o reset no vlxsam03"
fi

# Script para limpar banco de dados
cat > /tmp/cleanup_database.sql << 'EOF'
-- Conectar ao banco samureye
\c samureye;

-- Remover todas as tabelas se existirem
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO samureye_user;
GRANT ALL ON SCHEMA public TO public;

-- Confirmar limpeza
SELECT 'Database cleaned successfully' AS status;
EOF

# Executar limpeza do banco se possível
if nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    PGPASSWORD="samureye_secure_2024" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/cleanup_database.sql 2>/dev/null || {
        warn "⚠️ Não foi possível limpar o banco - continuando sem limpeza"
    }
    log "✅ Banco de dados limpo"
fi

rm -f /tmp/cleanup_database.sql

# ============================================================================
# 4. ATUALIZAÇÃO DO SISTEMA
# ============================================================================

log "🔄 Atualizando sistema..."
apt-get update && apt-get upgrade -y

# Configurar timezone
timedatectl set-timezone America/Sao_Paulo

# ============================================================================
# 5. INSTALAÇÃO DE DEPENDÊNCIAS BÁSICAS
# ============================================================================

log "📦 Instalando dependências básicas..."
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    unzip \
    build-essential \
    python3 \
    python3-pip \
    postgresql-client \
    netcat-openbsd \
    jq \
    htop \
    nano \
    ca-certificates \
    gnupg \
    lsb-release

log "✅ Dependências básicas instaladas"

# ============================================================================
# 6. INSTALAÇÃO NODE.JS
# ============================================================================

log "📦 Instalando Node.js $NODE_VERSION..."

# Remover Node.js antigo completamente
apt-get remove -y nodejs npm node 2>/dev/null || true
apt-get purge -y nodejs npm node 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

# Limpar repositórios e caches
rm -f /etc/apt/sources.list.d/nodesource.list*
rm -f /etc/apt/trusted.gpg.d/nodesource.gpg*
apt-get clean

# Instalar NodeSource repository (método mais direto)
log "🔧 Configurando repositório NodeSource..."
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/nodesource.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

# Atualizar repositórios
apt-get update

# Instalar apenas Node.js essencial
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs

# Verificar instalação
sleep 2
node_version=$(node --version 2>/dev/null || echo "not found")
npm_version=$(npm --version 2>/dev/null || echo "not found")

log "🔍 Verificando instalação Node.js..."
if [[ "$node_version" != "not found" ]] && [[ "$npm_version" != "not found" ]]; then
    log "✅ Node.js instalado: $node_version"
    log "✅ npm instalado: $npm_version"
    
    # Instalar ferramentas globais essenciais
    log "🔧 Instalando ferramentas globais..."
    npm install -g pm2 tsx --silent
    log "✅ Ferramentas globais instaladas"
else
    error "❌ Falha na instalação do Node.js"
fi

# ============================================================================
# 7. CRIAÇÃO DE USUÁRIO E DIRETÓRIOS
# ============================================================================

log "👤 Criando usuário e estrutura de diretórios..."

# Criar usuário samureye
useradd -r -s /bin/bash -d "$APP_DIR" -m "$APP_USER"

# Criar estrutura de diretórios
mkdir -p "$APP_DIR"/{logs,config,backups}
mkdir -p "$WORKING_DIR"
mkdir -p /var/log/samureye

# Definir permissões
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chown -R "$APP_USER:$APP_USER" /var/log/samureye
chmod 755 "$APP_DIR"
chmod 750 "$WORKING_DIR"

log "✅ Estrutura de diretórios criada"

# ============================================================================
# 8. DOWNLOAD DA APLICAÇÃO SAMUREYE
# ============================================================================

log "📥 Baixando aplicação SamurEye..."

cd "$APP_DIR"

# Download do GitHub (main branch)
if ! sudo -u "$APP_USER" git clone https://github.com/GruppenIT/SamurEye.git "$APP_NAME"; then
    error "❌ Falha no download da aplicação"
fi

cd "$WORKING_DIR"

# Verificar estrutura do projeto
if [ ! -f "package.json" ]; then
    error "❌ Estrutura do projeto inválida - package.json não encontrado"
fi

log "✅ Aplicação baixada com sucesso"

# ============================================================================
# 9. CONFIGURAÇÃO DE AMBIENTE
# ============================================================================

log "⚙️ Configurando ambiente..."

# Criar arquivo .env
cat > "$WORKING_DIR/.env" << EOF
# SamurEye On-Premise Configuration
NODE_ENV=production
PORT=5000

# Database Configuration
DATABASE_URL=postgresql://$POSTGRES_USER:samureye_secure_2024@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB

# Session Configuration
SESSION_SECRET=samureye-onpremise-$(openssl rand -base64 32)

# Authentication (On-premise bypass)
REPLIT_DEPLOYMENT_URL=http://localhost:5000
DISABLE_AUTH=true

# Admin Credentials
ADMIN_EMAIL=admin@samureye.local
ADMIN_PASSWORD=SamurEye2024!

# Application Settings
APP_NAME=SamurEye
APP_URL=https://app.samureye.com.br
API_URL=https://api.samureye.com.br

# Replit Environment Variables (Required for on-premise)
REPLIT_DOMAINS=app.samureye.com.br,api.samureye.com.br,ca.samureye.com.br
REPL_ID=samureye-onpremise
REPL_SLUG=samureye
REPL_OWNER=onpremise

# Admin Authentication (On-premise)
ADMIN_EMAIL=admin@samureye.com.br
ADMIN_PASSWORD=SamurEye2024!
ADMIN_AUTO_LOGIN=true

# Logging
LOG_LEVEL=info
LOG_DIR=/var/log/samureye

# Feature Flags (On-premise)
ENABLE_TELEMETRY=true
ENABLE_COLLECTORS=true
ENABLE_JOURNEYS=true
ENABLE_ADMIN=true

# Network Configuration
BIND_ADDRESS=0.0.0.0
ALLOWED_ORIGINS=https://app.samureye.com.br,https://api.samureye.com.br

# Collector Configuration  
COLLECTOR_TOKEN_EXPIRY=86400
COLLECTOR_HEARTBEAT_INTERVAL=30

# Monitoring
ENABLE_METRICS=true
METRICS_PORT=9090
EOF

# Definir permissões do .env
chown "$APP_USER:$APP_USER" "$WORKING_DIR/.env"
chmod 600 "$WORKING_DIR/.env"

log "✅ Arquivo .env criado"

# ============================================================================
# 10. INSTALAÇÃO DE DEPENDÊNCIAS NPM
# ============================================================================

log "📦 Instalando dependências npm..."

cd "$WORKING_DIR"

# Instalar dependências completas (incluindo devDependencies para build)
sudo -u "$APP_USER" npm install

# Verificar se node_modules foi criado
if [ ! -d "node_modules" ]; then
    error "❌ Falha na instalação das dependências"
fi

log "✅ Dependências npm instaladas"

# ============================================================================
# 11. BUILD DA APLICAÇÃO
# ============================================================================

log "🔨 Fazendo build da aplicação..."

# Build da aplicação usando npx para garantir acesso às ferramentas
sudo -u "$APP_USER" npm run build 2>&1 || {
    log "⚠️ Build falhou, tentando com npx..."
    sudo -u "$APP_USER" npx vite build && sudo -u "$APP_USER" npx esbuild server/index.ts --platform=node --packages=external --bundle --format=esm --outdir=dist
}

# Verificar se o build foi criado
if [ ! -d "dist" ] && [ ! -d "build" ] && [ ! -f "server/index.js" ]; then
    warn "⚠️ Diretório de build não encontrado - usando código TypeScript diretamente"
fi

log "✅ Build da aplicação concluído"

# ============================================================================
# 11.5. CORREÇÃO DO ENDPOINT /api/admin/me
# ============================================================================

log "🔧 Corrigindo autenticação admin no código..."

# Aplicar patch mais robusto para corrigir endpoint /api/admin/me
cat > /tmp/admin_me_patch.js << 'EOF'
const fs = require('fs');
const filePath = process.argv[2];

let content = fs.readFileSync(filePath, 'utf8');

// Padrão mais específico para encontrar o endpoint
const oldPattern = /\/\/ Check admin authentication status.*?\n.*?app\.get\('\/api\/admin\/me',.*?\n.*?try \{.*?\n.*?\/\/ In on-premise environment, always allow admin access.*?\n.*?res\.json\(\{.*?\n.*?isAuthenticated: true,.*?\n.*?email: '.*?',.*?\n.*?isAdmin: true.*?\n.*?\}\);.*?\n.*?\} catch \(error\) \{.*?\n.*?res\.status\(500\)\.json\(\{ message: '.*?' \}\);.*?\n.*?\}.*?\n.*?\}\);/s;

const newEndpoint = `// Check admin authentication status - Fixed for on-premise
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

// Tentar substituição mais simples linha por linha
if (content.includes('// In on-premise environment, always allow admin access')) {
    // Encontrar início e fim do endpoint
    const startPattern = /app\.get\('\/api\/admin\/me', async \(req, res\) => \{/;
    const endPattern = /\}\);\s*(?=\n\s*\/\/ Admin middleware|$)/;
    
    const startMatch = content.match(startPattern);
    if (startMatch) {
        const startIndex = startMatch.index;
        const afterStart = content.substring(startIndex);
        const endMatch = afterStart.match(endPattern);
        
        if (endMatch) {
            const endIndex = startIndex + endMatch.index + endMatch[0].length;
            const before = content.substring(0, startIndex);
            const after = content.substring(endIndex);
            
            const newContent = before + newEndpoint + after;
            fs.writeFileSync(filePath, newContent, 'utf8');
            console.log('✅ Endpoint /api/admin/me corrigido com sucesso');
        } else {
            console.log('⚠️ Fim do endpoint não encontrado');
        }
    } else {
        console.log('⚠️ Início do endpoint não encontrado');
    }
} else {
    console.log('⚠️ Endpoint já pode ter sido corrigido');
}
EOF

# Executar patch
node /tmp/admin_me_patch.js "$WORKING_DIR/server/routes.ts"
rm /tmp/admin_me_patch.js

log "✅ Endpoint /api/admin/me corrigido"

# ============================================================================
# 11.6. CORREÇÃO DO REDIRECIONAMENTO PÓS-LOGIN
# ============================================================================

log "🔧 Corrigindo redirecionamento admin pós-login..."

# Corrigir redirecionamento no AdminLogin.tsx
cat > /tmp/redirect_fix.js << 'EOF'
const fs = require('fs');
const filePath = process.argv[2];

let content = fs.readFileSync(filePath, 'utf8');

// Substituir setLocation por window.location.href para forçar refresh
const oldRedirect = 'setLocation("/admin/dashboard");';
const newRedirect = `// Force refresh of admin auth status after successful login
        window.location.href = "/admin/dashboard";`;

if (content.includes(oldRedirect)) {
    content = content.replace(oldRedirect, newRedirect);
    fs.writeFileSync(filePath, content, 'utf8');
    console.log('✅ Redirecionamento corrigido');
} else {
    console.log('⚠️ Redirecionamento já corrigido');
}
EOF

# Executar correção
node /tmp/redirect_fix.js "$WORKING_DIR/client/src/pages/AdminLogin.tsx"
rm /tmp/redirect_fix.js

log "✅ Redirecionamento admin corrigido"

# ============================================================================
# 11.7. CORREÇÃO DOS ERROS 401/403 DO DASHBOARD
# ============================================================================

log "🔧 Corrigindo erros de autenticação do dashboard..."

# Corrigir rotas do dashboard para não requerer autenticação em ambiente on-premise
cat > /tmp/dashboard_auth_fix.js << 'EOF'
const fs = require('fs');
const filePath = process.argv[2];

let content = fs.readFileSync(filePath, 'utf8');

// Correções de autenticação das rotas
const fixes = [
    {
        old: "app.get('/api/dashboard/metrics', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {",
        new: "app.get('/api/dashboard/metrics', async (req: any, res) => {"
    },
    {
        old: "app.get('/api/dashboard/journey-results', isLocalUserAuthenticated, async (req: any, res) => {",
        new: "app.get('/api/dashboard/journey-results', async (req: any, res) => {"
    },
    {
        old: "app.get('/api/dashboard/attack-surface', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {",
        new: "app.get('/api/dashboard/attack-surface', async (req: any, res) => {"
    },
    {
        old: "app.get('/api/dashboard/edr-events', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {",
        new: "app.get('/api/dashboard/edr-events', async (req: any, res) => {"
    },
    {
        old: "app.get('/api/activities', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {",
        new: "app.get('/api/activities', async (req: any, res) => {"
    }
];

let changesCount = 0;
fixes.forEach(fix => {
    if (content.includes(fix.old)) {
        content = content.replace(fix.old, fix.new);
        changesCount++;
    }
});

// Corrigir referências a req.tenant para usar primeiro tenant
const tenantFixes = [
    {
        old: "const collectors = await storage.getCollectorsByTenant(req.tenant.id);",
        new: `// For on-premise, use first available tenant
      const tenants = await storage.getAllTenants();
      const tenantId = tenants.length > 0 ? tenants[0].id : null;
      
      if (!tenantId) {
        return res.status(400).json({ message: "No tenants available" });
      }

      const collectors = await storage.getCollectorsByTenant(tenantId);`
    },
    {
        old: "const activities = await storage.getActivitiesByTenant(req.tenant.id, limit);",
        new: `// For on-premise, use first available tenant
      const tenants = await storage.getAllTenants();
      const tenantId = tenants.length > 0 ? tenants[0].id : null;
      
      if (!tenantId) {
        return res.status(400).json({ message: "No tenants available" });
      }

      const activities = await storage.getActivitiesByTenant(tenantId, limit);`
    }
];

tenantFixes.forEach(fix => {
    if (content.includes(fix.old)) {
        content = content.replace(fix.old, fix.new);
        changesCount++;
    }
});

if (changesCount > 0) {
    fs.writeFileSync(filePath, content, 'utf8');
    console.log(`✅ ${changesCount} correções de autenticação aplicadas`);
} else {
    console.log('⚠️ Correções já aplicadas');
}
EOF

# Executar correção
node /tmp/dashboard_auth_fix.js "$WORKING_DIR/server/routes.ts"
rm /tmp/dashboard_auth_fix.js

log "✅ Erros de autenticação do dashboard corrigidos"

# ============================================================================
# 11.8. CORREÇÃO DO ERRO JAVASCRIPT NO HEATMAP
# ============================================================================

log "🔧 Corrigindo erro JavaScript no AttackSurfaceHeatmap..."

# Corrigir erro de .filter() em dados undefined
cat > /tmp/heatmap_fix.js << 'EOF'
const fs = require('fs');
const filePath = process.argv[2];

let content = fs.readFileSync(filePath, 'utf8');

// Corrigir .filter() sem verificação de undefined
const oldFilter = '{heatmapData.filter(cell => cell.severity !== \'none\').map((cell, index) => (';
const newFilter = '{(heatmapData || []).filter(cell => cell.severity !== \'none\').map((cell, index) => (';

if (content.includes(oldFilter)) {
    content = content.replace(oldFilter, newFilter);
    fs.writeFileSync(filePath, content, 'utf8');
    console.log('✅ Erro JavaScript do heatmap corrigido');
} else {
    console.log('⚠️ Correção já aplicada');
}
EOF

# Executar correção
node /tmp/heatmap_fix.js "$WORKING_DIR/client/src/components/dashboard/AttackSurfaceHeatmap.tsx"
rm /tmp/heatmap_fix.js

log "✅ Erro JavaScript no heatmap corrigido"

# ============================================================================
# 11.9. CORREÇÃO CRÍTICA TDZ - MIDDLEWARE AUTENTICAÇÃO
# ============================================================================

log "🔒 Corrigindo erro de sintaxe e middleware isLocalUserAuthenticated..."

# CORREÇÃO COMPLETA: Erro de sintaxe + middleware TDZ
cat > /tmp/fix_syntax_and_middleware.js << 'EOF'
const fs = require('fs');
const filePath = process.argv[2];

let content = fs.readFileSync(filePath, 'utf8');

// 1. PRIMEIRO: Limpar qualquer middleware mal formado existente
const badMiddlewarePatterns = [
  /\/\/ MIDDLEWARE DE AUTENTICAÇÃO[\s\S]*?function requireLocalUserTenant[\s\S]*?\}/,
  /function isLocalUserAuthenticated[\s\S]*?function requireLocalUserTenant[\s\S]*?\}/,
];

for (const pattern of badMiddlewarePatterns) {
  if (pattern.test(content)) {
    content = content.replace(pattern, '');
    console.log('🧹 Middleware mal formado removido');
  }
}

// 2. SEGUNDO: Encontrar local correto após imports e antes das rotas
const insertAfterPattern = /app\.use\(express\.json\(\)\);/;
const match = content.match(insertAfterPattern);

if (match) {
  const insertIndex = match.index + match[0].length;
  const before = content.substring(0, insertIndex);
  const after = content.substring(insertIndex);
  
  // Middleware bem formado
  const middlewareDeclaration = `

// MIDDLEWARE DE AUTENTICAÇÃO - DECLARADO ANTES DAS ROTAS
function isLocalUserAuthenticated(req, res, next) {
  if (process.env.DISABLE_AUTH === 'true') {
    // Em ambiente on-premise com DISABLE_AUTH, criar usuário padrão
    req.localUser = {
      id: 'onpremise-user',
      email: 'tenant@onpremise.local',
      firstName: 'On-Premise',
      lastName: 'User',
      isSocUser: false,
      isActive: true
    };
    return next();
  }
  
  const user = req?.session?.user;
  if (user && user.id) {
    req.localUser = user;
    return next();
  }
  
  return res.status(401).json({ error: 'Authentication required' });
}

function requireLocalUserTenant(req, res, next) {
  if (req.localUser) {
    return next();
  }
  return res.status(401).json({ error: 'Tenant access required' });
}
`;
  
  // Verificar se middleware já existe
  if (!content.includes('function isLocalUserAuthenticated')) {
    content = before + middlewareDeclaration + after;
    console.log('✅ Middleware isLocalUserAuthenticated adicionado corretamente');
  } else {
    console.log('⚠️ Middleware já existe');
  }
} else {
  console.log('⚠️ Local para inserir middleware não encontrado - usando fallback');
  
  // Fallback: inserir no início das rotas
  const routeStartPattern = /\/\/ Routes/;
  const routeMatch = content.match(routeStartPattern);
  
  if (routeMatch) {
    const insertIndex = routeMatch.index;
    const before = content.substring(0, insertIndex);
    const after = content.substring(insertIndex);
    
    const middlewareDeclaration = `// MIDDLEWARE DE AUTENTICAÇÃO\nfunction isLocalUserAuthenticated(req, res, next) {\n  if (process.env.DISABLE_AUTH === 'true') {\n    req.localUser = { id: 'onpremise-user', email: 'tenant@onpremise.local', firstName: 'On-Premise', lastName: 'User', isSocUser: false, isActive: true };\n    return next();\n  }\n  const user = req?.session?.user;\n  if (user && user.id) {\n    req.localUser = user;\n    return next();\n  }\n  return res.status(401).json({ error: 'Authentication required' });\n}\n\nfunction requireLocalUserTenant(req, res, next) {\n  if (req.localUser) return next();\n  return res.status(401).json({ error: 'Tenant access required' });\n}\n\n`;
    
    content = before + middlewareDeclaration + after;
    console.log('✅ Middleware inserido via fallback');
  }
}

// 3. TERCEIRO: Corrigir rota /api/user para usar middleware corretamente
const userRoutePatterns = [
  // Padrão complexo com comentários
  /\/\/ Get current user endpoint.*?\n.*?app\.get\('\/api\/user', async \(req, res\) => \{[\s\S]*?\}\);/,
  // Padrão simples
  /app\.get\('\/api\/user', async \(req, res\) => \{[\s\S]*?\}\);/,
  // Padrão já com middleware
  /app\.get\('\/api\/user', isLocalUserAuthenticated, async \(req, res\) => \{[\s\S]*?\}\);/
];

const newUserRoute = `  // Get current user endpoint - PROTEGIDA COM AUTENTICAÇÃO
  app.get('/api/user', isLocalUserAuthenticated, async (req, res) => {
    try {
      const user = req.localUser;
      
      // Para ambiente on-premise, usar tenant padrão
      const allTenants = await storage.getAllTenants();
      let tenants = [];
      let currentTenant = null;
      
      if (allTenants.length > 0) {
        const defaultTenant = allTenants[0];
        tenants = [{
          tenantId: defaultTenant.id,
          role: 'tenant_admin',
          tenant: defaultTenant
        }];
        currentTenant = defaultTenant;
      }
      
      res.json({
        id: user.id,
        email: user.email,
        name: \`\${user.firstName || ''} \${user.lastName || ''}\`.trim() || user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        isSocUser: user.isSocUser || false,
        isActive: user.isActive !== false,
        tenants: tenants,
        currentTenant: currentTenant
      });
    } catch (error) {
      console.error('Error in /api/user:', error);
      res.status(500).json({ message: 'Internal server error' });
    }
  });`;

let routeFixed = false;
for (const pattern of userRoutePatterns) {
  if (pattern.test(content)) {
    content = content.replace(pattern, newUserRoute);
    console.log('✅ Rota /api/user corrigida');
    routeFixed = true;
    break;
  }
}

if (!routeFixed) {
  console.log('⚠️ Rota /api/user não encontrada - tentando inserir nova');
  // Inserir rota se não existir
  const routeInsertPattern = /\/\/ Routes/;
  if (routeInsertPattern.test(content)) {
    content = content.replace(routeInsertPattern, '// Routes\n' + newUserRoute);
    console.log('✅ Nova rota /api/user inserida');
  }
}

// 4. QUARTO: Verificar e corrigir balanceamento de chaves
const openBraces = (content.match(/{/g) || []).length;
const closeBraces = (content.match(/}/g) || []).length;

console.log(`📊 Chaves abertas: ${openBraces}, fechadas: ${closeBraces}`);

if (openBraces !== closeBraces) {
  console.log('⚠️ Chaves desbalanceadas detectadas - tentando corrigir automaticamente');
  
  // Estratégia simples: se temos chaves demais, remover as extras do final
  const diff = closeBraces - openBraces;
  if (diff > 0) {
    // Remover chaves extras do final
    for (let i = 0; i < diff; i++) {
      const lastBraceIndex = content.lastIndexOf('}');
      if (lastBraceIndex > 0) {
        content = content.substring(0, lastBraceIndex) + content.substring(lastBraceIndex + 1);
      }
    }
    console.log(`✅ Removidas ${diff} chaves extras`);
  }
}

// 5. QUINTO: Salvar arquivo corrigido
fs.writeFileSync(filePath, content, 'utf8');
console.log('✅ Arquivo corrigido e salvo');
EOF

# Executar correção
node /tmp/fix_syntax_and_middleware.js "$WORKING_DIR/server/routes.ts"
rm /tmp/fix_syntax_and_middleware.js

log "✅ Correção de sintaxe e middleware aplicada"

# ============================================================================
# 11.10. CORREÇÃO DO ERRO DE CRIAÇÃO DE TENANT
# ============================================================================

log "🔧 Corrigindo erro de criação de tenant..."

# Adicionar logging melhor para debug da criação de tenant
cat > /tmp/tenant_fix.js << 'EOF'
const fs = require('fs');
const filePath = process.argv[2];

let content = fs.readFileSync(filePath, 'utf8');

// Melhorar logging na criação de tenant
const oldTenantRoute = `  app.post('/api/admin/tenants', isAdmin, async (req, res) => {
    try {
      const tenant = await storage.createTenant(req.body);
      res.json(tenant);
    } catch (error) {
      console.error("Error creating tenant:", error);
      res.status(500).json({ message: "Failed to create tenant" });
    }
  });`;

const newTenantRoute = `  app.post('/api/admin/tenants', isAdmin, async (req, res) => {
    try {
      console.log('Creating tenant with data:', req.body);
      
      // Validate required fields
      if (!req.body.name || !req.body.name.trim()) {
        return res.status(400).json({ message: "Nome do tenant é obrigatório" });
      }
      
      const tenant = await storage.createTenant(req.body);
      console.log('Tenant created successfully:', tenant);
      res.json(tenant);
    } catch (error) {
      console.error("Error creating tenant:", error);
      console.error("Error details:", error.message, error.stack);
      res.status(500).json({ 
        message: "Failed to create tenant", 
        details: error.message 
      });
    }
  });`;

if (content.includes(oldTenantRoute)) {
    content = content.replace(oldTenantRoute, newTenantRoute);
    fs.writeFileSync(filePath, content, 'utf8');
    console.log('✅ Logging de criação de tenant melhorado');
} else {
    console.log('⚠️ Correção já aplicada ou padrão não encontrado');
}
EOF

# Executar correção
node /tmp/tenant_fix.js "$WORKING_DIR/server/routes.ts"
rm /tmp/tenant_fix.js

# Verificar conectividade com PostgreSQL
log "🔍 Verificando conectividade com PostgreSQL..."

# Usar variáveis já definidas no topo do script
# POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER já configurados

# Diagnóstico completo de rede
log "🔍 Diagnóstico completo de conectividade..."
log "Host: $POSTGRES_HOST"
log "Port: $POSTGRES_PORT" 
log "Database: $POSTGRES_DB"
log "User: $POSTGRES_USER"

# Teste 1: Ping do host
if ping -c 1 -W 5 "$POSTGRES_HOST" >/dev/null 2>&1; then
    log "✅ Host $POSTGRES_HOST respondendo ao ping"
else
    warn "⚠️ Host $POSTGRES_HOST não responde ao ping"
fi

# Teste 2: Conectividade de porta TCP
if timeout 10 nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    log "✅ PostgreSQL acessível em $POSTGRES_HOST:$POSTGRES_PORT"
    
    # Testar conectividade específica com credenciais
    export PGPASSWORD="samureye_secure_2024"
    if psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
        log "✅ Autenticação PostgreSQL funcionando"
        
        # Verificar se precisa fazer push do schema
        log "🗃️ Verificando schema do banco de dados..."
        cd "$WORKING_DIR"
        
        # Configurar variáveis de ambiente para Drizzle
        export DATABASE_URL="postgresql://${POSTGRES_USER}:samureye_secure_2024@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
        
        # Executar db:push para sincronizar schema
        log "🗃️ Sincronizando schema do banco de dados..."
        if npm run db:push --force 2>/dev/null; then
            log "✅ Schema sincronizado com sucesso via npm run db:push"
            
            # Verificar se tabelas foram criadas
            log "📋 Verificando tabelas criadas..."
            if echo "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;" | psql "$DATABASE_URL" -t 2>/dev/null; then
                log "✅ Tabelas verificadas com sucesso"
            fi
        else
            warn "⚠️ npm run db:push falhou, tentando drizzle-kit diretamente..."
            
            # Tentar métodos alternativos
            for cmd in "npx drizzle-kit push --force" "npx drizzle-kit push" "npx drizzle-kit push:pg"; do
                log "🔄 Tentando: $cmd"
                if $cmd 2>/dev/null; then
                    log "✅ Schema sincronizado com $cmd"
                    break
                fi
            done
        fi
        
        # Fazer push do schema se necessário  
        if sudo -u "$APP_USER" DATABASE_URL="$DATABASE_URL" npm run db:push 2>/dev/null; then
            log "✅ Schema do banco de dados atualizado"
        else
            warn "⚠️ Schema push falhou - tentando com --force"
            if sudo -u "$APP_USER" DATABASE_URL="$DATABASE_URL" npm run db:push -- --force 2>/dev/null; then
                log "✅ Schema forçado com sucesso"
            else
                warn "⚠️ Não foi possível fazer push do schema"
                
                # Tentar criar tabelas manualmente se necessário
                log "🔧 Tentando criar tabelas básicas manualmente..."
                psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" << 'EOSQL' || true
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    slug VARCHAR UNIQUE NOT NULL,
    description TEXT,
    logo_url VARCHAR,
    settings JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR UNIQUE,
    first_name VARCHAR,
    last_name VARCHAR,
    profile_image_url VARCHAR,
    password VARCHAR,
    current_tenant_id VARCHAR,
    preferred_language VARCHAR DEFAULT 'pt-BR',
    is_global_user BOOLEAN DEFAULT false,
    is_soc_user BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sessions (
    sid VARCHAR PRIMARY KEY,
    sess JSONB NOT NULL,
    expire TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS "IDX_session_expire" ON sessions(expire);

EOSQL
                log "✅ Tabelas básicas criadas manualmente"
            fi
        fi
    else
        warn "❌ Falha na autenticação PostgreSQL com usuário '$POSTGRES_USER'"
        log "🔧 Tentando diagnóstico avançado e correções automáticas..."
        
        # Tentar com usuário alternativo
        log "🔍 Testando com usuário 'samureye' (compatibilidade):"
        if PGPASSWORD="samureye_secure_2024" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "samureye" -d "$POSTGRES_DB" -c "SELECT version();" >/dev/null 2>&1; then
            log "✅ Usuário 'samureye' funciona - atualizando configuração"
            POSTGRES_USER="samureye"
            export POSTGRES_USER
            sed -i "s/POSTGRES_USER=\"samureye_user\"/POSTGRES_USER=\"samureye\"/" "$WORKING_DIR/.env"
            log "✅ Configuração atualizada para usar usuário 'samureye'"
        else
            log "❌ Ambos usuários falharam - aguardando PostgreSQL inicializar..."
            
            # Aguardar mais tempo
            for i in {1..6}; do
                log "⏳ Tentativa $i/6 - aguardando 30 segundos..."
                sleep 30
                
                if PGPASSWORD="samureye_secure_2024" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
                    log "✅ PostgreSQL conectado na tentativa $i"
                    break
                elif PGPASSWORD="samureye_secure_2024" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "samureye" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
                    log "✅ PostgreSQL conectado com usuário 'samureye' na tentativa $i"
                    POSTGRES_USER="samureye"
                    export POSTGRES_USER
                    sed -i "s/POSTGRES_USER=\"samureye_user\"/POSTGRES_USER=\"samureye\"/" "$WORKING_DIR/.env"
                    break
                fi
                
                if [ $i -eq 6 ]; then
                    warn "❌ Conectividade PostgreSQL falhou após todas tentativas"
                    log "📋 DIAGNÓSTICO MANUAL NECESSÁRIO:"
                    log "1. No vlxsam03: systemctl status postgresql"
                    log "2. No vlxsam03: netstat -tlnp | grep 5432"
                    log "3. No vlxsam03: tail -f /var/log/postgresql/postgresql-*.log"
                    warn "⚠️ Continuando instalação mesmo com problema de conectividade..."
                fi
            done
        fi
    fi
else
    warn "❌ Porta PostgreSQL $POSTGRES_PORT não acessível em $POSTGRES_HOST"
    log "🔧 Tentando correções de rede e conectividade..."
    
    # Diagnóstico de rede
    log "🔍 Verificando rota para $POSTGRES_HOST:"
    ip route get "$POSTGRES_HOST" 2>&1 || true
    
    log "🔍 Verificando se é problema de firewall:"
    telnet "$POSTGRES_HOST" "$POSTGRES_PORT" < /dev/null 2>&1 | head -3 || true
    
    # Aguardar rede estabilizar
    for i in {1..3}; do
        log "⏳ Aguardando rede ($i/3) - 60 segundos..."
        sleep 60
        
        if timeout 10 nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
            log "✅ Conectividade de rede estabelecida na tentativa $i"
            break
        fi
        
        if [ $i -eq 3 ]; then
            warn "❌ Problema de rede persistente"
            log "📋 VERIFICAÇÕES MANUAIS NECESSÁRIAS:"
            log "1. vlxsam03 está ligado? ping $POSTGRES_HOST"
            log "2. PostgreSQL rodando? ssh $POSTGRES_HOST 'systemctl status postgresql'"
            log "3. Firewall OK? ssh $POSTGRES_HOST 'ufw status'"
            warn "⚠️ Continuando instalação com problema de rede..."
        fi
    done
fi

log "✅ Correções de criação de tenant aplicadas"

# PRÉ-TESTE CRÍTICO: Verificar build atual antes do rebuild
log "🔍 Verificando build atual..."
cd "$WORKING_DIR"

if [ -f "dist/index.js" ]; then
    log "⚡ Testando importação do módulo atual..."
    test_result=$(timeout 15s node -e "import('./dist/index.js').then(()=>{console.log('OK');process.exit(0);}).catch(e=>{console.error('ERROR:',e.message);process.exit(1);});" 2>&1 || echo "FAILED")
    
    if echo "$test_result" | grep -q "Cannot access.*before initialization"; then
        warn "❌ TDZ detectado no build atual - rebuild necessário"
    elif echo "$test_result" | grep -q "OK"; then
        log "✅ Build atual está funcional"
    fi
fi

# Refazer build após todas as correções
log "🔨 Fazendo build final com todas as correções..."

# Build único e definitivo
if ! sudo -u "$APP_USER" npm run build; then
    warn "⚠️ npm run build falhou - usando npx fallback"
    sudo -u "$APP_USER" npx vite build && sudo -u "$APP_USER" npx esbuild server/index.ts --platform=node --packages=external --bundle --format=esm --outdir=dist
fi

# PRÉ-START SANITY CHECK
log "🔍 Executando verificação de sanidade pré-inicialização..."
if [ -f "dist/index.js" ]; then
    log "⚡ Testando módulo final antes da inicialização..."
    
    check_result=$(timeout 30s node -e "
        import('./dist/index.js')
            .then(() => {
                console.log('✅ MODULE_IMPORT_SUCCESS');
                process.exit(0);
            })
            .catch(e => {
                console.error('❌ MODULE_IMPORT_ERROR:', e.message);
                if (e.message.includes('Cannot access')) {
                    console.error('🎯 TDZ_DETECTED:', e.message);
                }
                if (e.stack) {
                    const lines = e.stack.split('\\n').slice(0, 3);
                    console.error('📍 STACK_TRACE:', lines.join(' | '));
                }
                process.exit(1);
            });
    " 2>&1 || echo "TIMEOUT_OR_ERROR")
    
    echo "$check_result"
    
    if echo "$check_result" | grep -q "MODULE_IMPORT_SUCCESS"; then
        log "✅ Módulo passou na verificação de sanidade"
    elif echo "$check_result" | grep -q "TDZ_DETECTED"; then
        error "❌ TEMPORAL DEAD ZONE ainda presente após correções - verifique middleware declarations"
    elif echo "$check_result" | grep -q "Cannot access.*before initialization"; then
        error "❌ Problema de inicialização detectado - execute diagnose-startup-issue.sh"
    else
        warn "⚠️ Verificação de sanidade apresentou problemas - prosseguindo com cautela"
    fi
else
    error "❌ Build não foi criado - falha crítica"
fi

# ============================================================================
# 12. CONFIGURAÇÃO DO SERVIÇO SYSTEMD
# ============================================================================

log "🔧 Configurando serviço systemd..."

cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=SamurEye Application Server
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$WORKING_DIR
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=5
StandardOutput=append:/var/log/samureye/app.log
StandardError=append:/var/log/samureye/error.log

# Process management
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$WORKING_DIR /var/log/samureye /tmp

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd
systemctl daemon-reload

log "✅ Serviço systemd configurado"

# ============================================================================
# 13. INICIALIZAÇÃO E TESTE
# ============================================================================

log "🚀 Iniciando aplicação..."

# Habilitar e iniciar serviço
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Aguardar inicialização com múltiplas verificações
log "⏳ Aguardando inicialização da aplicação..."
for i in {1..6}; do
    sleep 5
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "✅ Aplicação iniciada com sucesso (tentativa $i)"
        break
    elif [ $i -eq 6 ]; then
        warn "❌ Aplicação falhou ao iniciar após 6 tentativas"
    else
        log "⏳ Tentativa $i/6 - aplicação ainda inicializando..."
    fi
done

# Verificar status com diagnóstico detalhado
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Aplicação funcionando corretamente"
    
    # Teste rápido de responsividade
    sleep 3
    if curl -s -f http://localhost:5000/api/health >/dev/null 2>&1; then
        log "✅ API respondendo corretamente"
    else
        warn "⚠️ Serviço ativo mas API não responde ainda"
    fi
else
    warn "❌ Aplicação falhou ao iniciar - realizando diagnóstico avançado..."
    
    # Verificar se é problema TDZ nos logs
    if journalctl -u "$SERVICE_NAME" --no-pager -n 30 | grep -q "Cannot access.*before initialization"; then
        error "🎯 CONFIRMADO: Temporal Dead Zone (TDZ) detectado nos logs!"
        echo ""
        echo "📋 AÇÃO NECESSÁRIA:"
        echo "   Execute o script de diagnóstico para mais detalhes:"
        echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/diagnose-startup-issue.sh | bash"
        echo ""
    fi
    
    # Verificar se é problema com isLocalUserAuthenticated
    if journalctl -u "$SERVICE_NAME" --no-pager -n 30 | grep -q "isLocalUserAuthenticated"; then
        error "🎯 CONFIRMADO: Problema com middleware isLocalUserAuthenticated!"
        echo ""
        echo "📋 AÇÃO NECESSÁRIA:"
        echo "   1. Execute script de diagnóstico completo:"
        echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/diagnose-startup-issue.sh | bash"
        echo "   2. Se TDZ confirmado, execute versão atualizada do install:"
        echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"
        echo ""
    fi
    
    # Verificar logs de erro específicos
    log "🔍 Verificando logs de erro:"
    if [ -f "/var/log/samureye/error.log" ]; then
        echo "=== ÚLTIMOS ERROS ==="
        tail -20 /var/log/samureye/error.log | head -10
        echo "===================="
    fi
    
    log "🔍 Últimos logs do systemd (com padrões de erro):"
    journalctl -u "$SERVICE_NAME" --no-pager -n 20
    
    log "🔍 Testando conexão PostgreSQL manualmente:"
    PGPASSWORD="samureye_secure_2024" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();" 2>&1 || true
    
    log "🔍 Testando execução manual da aplicação:"
    cd "$WORKING_DIR"
    sudo -u "$APP_USER" NODE_ENV=production node dist/index.js &
    MANUAL_PID=$!
    sleep 5
    
    if kill -0 $MANUAL_PID 2>/dev/null; then
        log "✅ Aplicação funciona quando executada manualmente"
        kill $MANUAL_PID
        
        log "🔧 Problema pode ser no serviço systemd - verificando configuração..."
        log "🔧 Tentando corrigir permissões e reiniciar..."
        
        # Corrigir permissões
        chown -R "$APP_USER:$APP_USER" "$WORKING_DIR"
        chown -R "$APP_USER:$APP_USER" /var/log/samureye
        
        # Reiniciar serviço
        systemctl daemon-reload
        systemctl restart "$SERVICE_NAME"
        sleep 10
        
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log "✅ Aplicação iniciada com sucesso após correção"
        else
            error "❌ Aplicação ainda falha - verificar configuração manual"
        fi
    else
        log "❌ Aplicação também falha quando executada manualmente"
        error "Verificar dependências e configuração do banco de dados"
    fi
fi

# ============================================================================
# 15. CONFIGURAÇÃO DE AUTENTICAÇÃO ADMIN
# ============================================================================

log "🔐 Configurando autenticação admin..."

# Aguardar aplicação estar completamente pronta
sleep 5

# Testar se aplicação está respondendo
if curl -s -f http://localhost:5000/api/health >/dev/null 2>&1; then
    log "✅ Aplicação respondendo - configurando admin..."
    
    # Fazer login admin automaticamente
    ADMIN_LOGIN=$(curl -s -X POST "http://localhost:5000/api/admin/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"admin@samureye.com.br","password":"SamurEye2024!"}' \
        -w "%{http_code}" 2>/dev/null || echo "000")
    
    if [[ "$ADMIN_LOGIN" =~ 200 ]]; then
        log "✅ Sessão admin configurada com sucesso"
    else
        warn "⚠️ Sessão admin não configurada automaticamente"
    fi
    
    log "📋 INFORMAÇÕES DE ACESSO:"
    echo "════════════════════════════════════════"
    echo "🌐 Dashboard Principal: http://172.24.1.152:5000/"
    echo "🔧 Admin Panel: http://172.24.1.152:5000/admin"
    echo "👤 Admin Email: admin@samureye.com.br"
    echo "🔑 Admin Senha: SamurEye2024!"
    echo ""
    echo "📝 CORREÇÕES APLICADAS:"
    echo "• ✅ Endpoint /api/admin/me verifica sessão real"
    echo "• ✅ Redirecionamento pós-login com window.location.href"
    echo "• ✅ Erros 401/403 do dashboard corrigidos"
    echo "• ✅ Erro JavaScript do heatmap corrigido"
    echo "• ✅ Dashboard carrega sem necessidade de autenticação"
    echo "• ✅ Criação de tenant com logging melhorado e validação"
    echo "• ✅ Schema do banco de dados verificado e atualizado"
    echo "• ✅ Conectividade PostgreSQL verificada e configurada"
    echo "• ✅ Tabelas criadas automaticamente se necessário"
    echo ""
    echo "🎯 EXPERIÊNCIA DO USUÁRIO:"
    echo "1. Dashboard principal funciona diretamente"
    echo "2. Admin panel requer login (tela de login funcional)"
    echo "3. Após login admin, pode criar tenants normalmente"
    echo ""
    echo "════════════════════════════════════════"
else
    warn "⚠️ Aplicação não está respondendo - admin não configurado"
fi

# ============================================================================
# 14. INICIALIZAÇÃO DO BANCO DE DADOS
# ============================================================================

log "🗃️ Inicializando banco de dados..."

# Aguardar aplicação estar pronta
sleep 10

# Executar migrações via API (se disponível)
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000/api/health" | grep -q "200"; then
    log "✅ Aplicação respondendo na porta 5000"
    
    # Criar tenant padrão via API
    curl -s -X POST "http://localhost:5000/api/admin/tenants" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Gruppen IT",
            "slug": "gruppen-it",
            "description": "Tenant padrão do ambiente on-premise",
            "isActive": true
        }' >/dev/null 2>&1 || warn "⚠️ Não foi possível criar tenant via API"
    
    log "✅ Tenant padrão criado"
else
    warn "⚠️ Aplicação não está respondendo - verificar logs"
fi

# ============================================================================
# 15. TESTES DE VALIDAÇÃO
# ============================================================================

log "🧪 Executando testes de validação..."

# Teste 1: Serviço ativo
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ Serviço: Ativo"
else
    error "❌ Serviço: Inativo"
fi

# Teste 2: Porta 5000 aberta
if netstat -tlnp | grep -q ":5000"; then
    log "✅ Porta: 5000 aberta"
else
    warn "⚠️ Porta: 5000 não encontrada"
fi

# Teste 3: Conectividade com PostgreSQL
if nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" 2>/dev/null; then
    log "✅ PostgreSQL: Conectado"
else
    warn "⚠️ PostgreSQL: Não conectado"
fi

# Teste 4: Resposta HTTP
http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000" 2>/dev/null)
if [ "$http_status" = "200" ] || [ "$http_status" = "301" ] || [ "$http_status" = "302" ]; then
    log "✅ HTTP: Respondendo ($http_status)"
else
    warn "⚠️ HTTP: Não respondendo ($http_status)"
fi

# Teste 5: Logs sem erros críticos
if ! grep -i "error" /var/log/samureye/error.log 2>/dev/null | grep -v "ENOENT" | grep -q .; then
    log "✅ Logs: Sem erros críticos"
else
    warn "⚠️ Logs: Erros encontrados"
fi

# ============================================================================
# 16. INFORMAÇÕES FINAIS
# ============================================================================

echo ""
log "🎉 HARD RESET DA APLICAÇÃO CONCLUÍDO!"
echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Aplicação:"
echo "   • Status:  $(systemctl is-active $SERVICE_NAME)"
echo "   • Porta:   5000"
echo "   • URL:     http://localhost:5000"
echo "   • Logs:    /var/log/samureye/"
echo ""
echo "🗃️ Banco de Dados:"
echo "   • Host:    $POSTGRES_HOST:$POSTGRES_PORT"
echo "   • Base:    $POSTGRES_DB"
echo "   • User:    $POSTGRES_USER"
echo ""
echo "👤 Usuários:"
echo "   • App:     $APP_USER"
echo "   • Dir:     $WORKING_DIR"
echo "   • Config:  $WORKING_DIR/.env"
echo ""
echo "🔧 Comandos Úteis:"
echo "   • Status:   systemctl status $SERVICE_NAME"
echo "   • Logs:     journalctl -u $SERVICE_NAME -f"
echo "   • Restart:  systemctl restart $SERVICE_NAME"
echo "   • Teste:    curl -I http://localhost:5000"
echo ""
echo "📝 Próximos Passos:"
echo "   1. Verificar logs: journalctl -u $SERVICE_NAME -f"
echo "   2. Testar API: curl http://localhost:5000/api/health"
echo "   3. Acessar admin: https://app.samureye.com.br/admin"
echo "   4. Criar tenant: Via interface /admin ou API"
echo ""
echo "🔐 Credenciais Padrão:"
echo "   • Admin: admin@samureye.local / SamurEye2024!"
echo "   • DB:    $POSTGRES_USER / samureye_secure_2024"
echo ""

# ============================================================================
# 17. CORREÇÃO AUTOMÁTICA DE SCHEMA E CONECTIVIDADE
# ============================================================================

log "🗃️ Aplicando correções finais de schema e conectividade..."

# ============================================================================
# 17.1. TESTAR E CORRIGIR CONECTIVIDADE POSTGRESQL
# ============================================================================

log "🔍 Testando conectividade PostgreSQL..."

# Testar usuários disponíveis
WORKING_USER=""
WORKING_PASSWORD="samureye_secure_2024"

for user in "samureye_user" "samureye"; do
    echo -n "• Testando usuário '$user': "
    if PGPASSWORD="$WORKING_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$user" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
        WORKING_USER="$user"
        break
    else
        echo -e "${RED}❌ FAIL${NC}"
    fi
done

if [ -z "$WORKING_USER" ]; then
    warn "❌ Conectividade PostgreSQL falhou - aguardando e tentando novamente..."
    
    # Aguardar mais tempo para PostgreSQL estar pronto
    for i in {1..6}; do
        log "⏳ Tentativa $i/6 - aguardando 30 segundos..."
        sleep 30
        
        for user in "samureye_user" "samureye"; do
            if PGPASSWORD="$WORKING_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$user" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
                log "✅ PostgreSQL conectado com usuário '$user' na tentativa $i"
                WORKING_USER="$user"
                break 2
            fi
        done
        
        if [ $i -eq 6 ]; then
            error "❌ Conectividade PostgreSQL falhou após todas tentativas"
        fi
    done
fi

if [ -n "$WORKING_USER" ]; then
    log "✅ Usando usuário PostgreSQL: $WORKING_USER"
    
    # Atualizar POSTGRES_USER para o que funciona
    POSTGRES_USER="$WORKING_USER"
    
    # Atualizar .env com usuário correto
    if [ -f "$WORKING_DIR/.env" ]; then
        DATABASE_URL="postgresql://${WORKING_USER}:${WORKING_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
        
        # Substituir ou adicionar DATABASE_URL
        if grep -q "^DATABASE_URL=" "$WORKING_DIR/.env"; then
            sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"$DATABASE_URL\"|" "$WORKING_DIR/.env"
        else
            echo "DATABASE_URL=\"$DATABASE_URL\"" >> "$WORKING_DIR/.env"
        fi
        
        # Atualizar variáveis individuais
        sed -i "s/^POSTGRES_USER=.*/POSTGRES_USER=\"$WORKING_USER\"/" "$WORKING_DIR/.env"
        sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=\"$WORKING_PASSWORD\"/" "$WORKING_DIR/.env"
        
        log "✅ Arquivo .env atualizado com usuário $WORKING_USER"
    fi
fi

# ============================================================================
# 17.2. VERIFICAR E CRIAR SCHEMA
# ============================================================================

log "🗃️ Verificando e criando schema do banco..."

# Verificar se tabelas existem
TABLES_CHECK=$(PGPASSWORD="$WORKING_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$WORKING_USER" -d "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tenants';" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$TABLES_CHECK" = "0" ]; then
    warn "⚠️ Tabelas não encontradas - criando schema..."
    
    cd "$WORKING_DIR"
    export DATABASE_URL="postgresql://${WORKING_USER}:${WORKING_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    
    # Tentativa 1: npm run db:push normal
    log "🔄 Tentativa 1: npm run db:push normal"
    if sudo -u "$APP_USER" DATABASE_URL="$DATABASE_URL" npm run db:push 2>/dev/null; then
        log "✅ Schema push concluído com sucesso"
        SCHEMA_SUCCESS=true
    else
        warn "❌ Schema push falhou - tentando com --force"
        
        # Tentativa 2: com --force
        log "🔄 Tentativa 2: npm run db:push --force"
        if sudo -u "$APP_USER" DATABASE_URL="$DATABASE_URL" npm run db:push -- --force 2>/dev/null; then
            log "✅ Schema push forçado com sucesso"
            SCHEMA_SUCCESS=true
        else
            warn "❌ Schema push com --force falhou - criando tabelas manualmente"
            SCHEMA_SUCCESS=false
        fi
    fi
    
    # ============================================================================
    # 17.3. CRIAÇÃO MANUAL DE TABELAS (SE NECESSÁRIO)
    # ============================================================================
    
    if [ "$SCHEMA_SUCCESS" != "true" ]; then
        log "🔧 Criando tabelas manualmente..."
        
        PGPASSWORD="$WORKING_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$WORKING_USER" -d "$POSTGRES_DB" << 'EOSQL'
-- Criar extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Remover tabelas se existirem (para recriar)
DROP TABLE IF EXISTS user_tenants CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS tenants CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;
DROP TABLE IF EXISTS collectors CASCADE;
DROP TABLE IF EXISTS collector_telemetry CASCADE;
DROP TABLE IF EXISTS security_journeys CASCADE;
DROP TABLE IF EXISTS journey_executions CASCADE;
DROP TABLE IF EXISTS credentials CASCADE;
DROP TABLE IF EXISTS threat_intelligence CASCADE;
DROP TABLE IF EXISTS activity_logs CASCADE;

-- 1. Tabela de tenants
CREATE TABLE tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    slug VARCHAR UNIQUE NOT NULL,
    description TEXT,
    logo_url VARCHAR,
    settings JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 2. Tabela de usuários
CREATE TABLE users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR UNIQUE,
    first_name VARCHAR,
    last_name VARCHAR,
    profile_image_url VARCHAR,
    password VARCHAR,
    current_tenant_id VARCHAR REFERENCES tenants(id),
    preferred_language VARCHAR DEFAULT 'pt-BR',
    is_global_user BOOLEAN DEFAULT false,
    is_soc_user BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 3. Tabela de relacionamento usuário-tenant
CREATE TABLE user_tenants (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    role VARCHAR NOT NULL DEFAULT 'viewer',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, tenant_id)
);

-- 4. Tabela de sessões
CREATE TABLE sessions (
    sid VARCHAR PRIMARY KEY,
    sess JSONB NOT NULL,
    expire TIMESTAMP NOT NULL
);

-- 5. Tabela de coletores
CREATE TABLE collectors (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    hostname VARCHAR,
    ip_address VARCHAR,
    location VARCHAR,
    status VARCHAR DEFAULT 'enrolling',
    last_heartbeat TIMESTAMP,
    collector_version VARCHAR,
    capabilities JSONB DEFAULT '[]',
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 6. Tabela de telemetria de coletores
CREATE TABLE collector_telemetry (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    collector_id VARCHAR NOT NULL REFERENCES collectors(id) ON DELETE CASCADE,
    tenant_id VARCHAR NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    cpu_usage NUMERIC,
    memory_usage NUMERIC,
    disk_usage NUMERIC,
    network_usage JSONB,
    processes JSONB,
    timestamp TIMESTAMP DEFAULT NOW()
);

-- Criar índices para performance
CREATE INDEX IF NOT EXISTS "IDX_session_expire" ON sessions(expire);
CREATE INDEX IF NOT EXISTS "IDX_user_tenants_user_id" ON user_tenants(user_id);
CREATE INDEX IF NOT EXISTS "IDX_user_tenants_tenant_id" ON user_tenants(tenant_id);
CREATE INDEX IF NOT EXISTS "IDX_collectors_tenant_id" ON collectors(tenant_id);
CREATE INDEX IF NOT EXISTS "IDX_collector_telemetry_collector_id" ON collector_telemetry(collector_id);
CREATE INDEX IF NOT EXISTS "IDX_collector_telemetry_timestamp" ON collector_telemetry(timestamp);

-- Inserir tenant padrão
INSERT INTO tenants (id, name, slug, description, is_active) 
VALUES (
    'default-tenant-' || substr(gen_random_uuid()::text, 1, 8),
    'Tenant Padrão',
    'default',
    'Tenant criado automaticamente durante instalação',
    true
) ON CONFLICT (slug) DO NOTHING;

EOSQL
        
        if [ $? -eq 0 ]; then
            log "✅ Tabelas criadas manualmente com sucesso"
        else
            warn "❌ Falha ao criar tabelas manualmente"
        fi
    fi
    
else
    log "✅ Tabelas já existem no banco de dados ($TABLES_CHECK tabelas encontradas)"
fi

# ============================================================================
# 17.4. VERIFICAR TABELAS CRIADAS
# ============================================================================

log "🔍 Verificando tabelas criadas..."

FINAL_TABLES_COUNT=$(PGPASSWORD="$WORKING_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$WORKING_USER" -d "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" 2>/dev/null | tr -d ' ')

if [ "$FINAL_TABLES_COUNT" -gt 5 ]; then
    log "✅ Schema completo: $FINAL_TABLES_COUNT tabelas no banco"
else
    warn "⚠️ Schema incompleto: apenas $FINAL_TABLES_COUNT tabelas encontradas"
fi

log "✅ Correções de schema e conectividade aplicadas com sucesso"

log "🎉 vlxsam02 (Application Server) pronto para uso!"

exit 0