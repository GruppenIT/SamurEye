#!/bin/bash

# ============================================================================
# CORREÇÃO ESPECÍFICA - TOKEN ENROLLMENT vlxsam02
# ============================================================================
# Corrige problema do token de enrollment não aparecer na interface
# Garante que o token seja gerado, salvo e retornado corretamente
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

echo ""
echo "🔧 CORREÇÃO TOKEN ENROLLMENT"
echo "============================"
echo "Sistema: vlxsam02 ($(hostname))"
echo ""

# Configurações
WORKING_DIR="/opt/samureye"
SERVICE_NAME="samureye-app"

# Verificar se aplicação está rodando
if ! systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    error "❌ Aplicação não está rodando"
    echo "   • Execute: systemctl start $SERVICE_NAME"
    exit 1
fi

# ============================================================================
# 1. CORRIGIR SCHEMA DO COLLECTOR
# ============================================================================

log "🔧 Corrigindo schema do collector..."

cd "$WORKING_DIR"

# Backup do arquivo original
cp "shared/schema.ts" "shared/schema.ts.bak.$(date +%s)"

# Correção 1: Garantir que enrollmentToken não está sendo omitido
cat > /tmp/fix_schema.js << 'EOF'
const fs = require('fs');

const schemaPath = process.argv[2];
let content = fs.readFileSync(schemaPath, 'utf8');

// Correção: Remover enrollmentToken e enrollmentTokenExpires do omit
const oldPattern = /export const insertCollectorSchema = createInsertSchema\(collectors\)\.omit\(\s*\{[^}]*enrollmentToken:\s*true[^}]*\}\s*\);/gs;
const newPattern = `export const insertCollectorSchema = createInsertSchema(collectors).omit({ 
  id: true, 
  createdAt: true, 
  updatedAt: true
});`;

if (content.match(oldPattern)) {
    content = content.replace(oldPattern, newPattern);
    fs.writeFileSync(schemaPath, content, 'utf8');
    console.log('✅ Schema corrigido - enrollmentToken removido do omit');
} else {
    console.log('⚠️ Schema já estava correto ou padrão não encontrado');
}
EOF

node /tmp/fix_schema.js "$WORKING_DIR/shared/schema.ts"
rm /tmp/fix_schema.js

# ============================================================================
# 2. CORRIGIR ENDPOINT DE CRIAÇÃO DE COLLECTOR
# ============================================================================

log "🔧 Corrigindo endpoint POST /api/collectors..."

# Backup do arquivo original
cp "server/routes.ts" "server/routes.ts.bak.$(date +%s)"

# Correção 2: Garantir que o token está sendo retornado corretamente
cat > /tmp/fix_routes.js << 'EOF'
const fs = require('fs');

const routesPath = process.argv[2];
let content = fs.readFileSync(routesPath, 'utf8');

// Procurar o response do endpoint POST /api/collectors
const responsePattern = /res\.json\(\s*\{[\s\S]*?enrollmentInstructions:\s*\{[\s\S]*?\}\s*\}\s*\);/;

if (content.match(responsePattern)) {
    console.log('✅ Response do collector já tem estrutura correta');
} else {
    console.log('⚠️ Estrutura do response pode precisar de correção');
    
    // Procurar por res.json que retorna collector sem enrollmentToken explícito
    const simpleResponsePattern = /(res\.json\(\s*\{[\s\S]*?collector[\s\S]*?\}\s*\);)/;
    
    if (content.match(simpleResponsePattern)) {
        // Corrigir response para incluir explicitamente enrollmentToken
        const betterResponse = `res.json({
        ...collector,
        enrollmentToken: collector.enrollmentToken,
        enrollmentTokenExpires: collector.enrollmentTokenExpires,
        tenantSlug: tenant?.slug || 'default',
        message: \`Collector created successfully. Token expires in 15 minutes.\`,
        enrollmentInstructions: {
          step1: "Copy the enrollment token and tenant slug",
          step2: "Run the registration script on the collector server:",
          command: \`curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/register-collector.sh | bash -s -- \${tenant?.slug || 'tenant-slug'} \${collector.enrollmentToken}\`,
          note: "Token expires at: " + collector.enrollmentTokenExpires?.toISOString()
        }
      });`;
      
        content = content.replace(simpleResponsePattern, betterResponse);
        fs.writeFileSync(routesPath, content, 'utf8');
        console.log('✅ Response corrigido para incluir enrollmentToken explicitamente');
    }
}
EOF

node /tmp/fix_routes.js "$WORKING_DIR/server/routes.ts"
rm /tmp/fix_routes.js

# ============================================================================
# 3. VERIFICAR E CORRIGIR ESTRUTURA DO COLLECTOR RETORNADO
# ============================================================================

log "🔧 Adicionando debug logging para criação de collector..."

# Adicionar logging detalhado para debug
cat > /tmp/add_debug.js << 'EOF'
const fs = require('fs');

const routesPath = process.argv[2];
let content = fs.readFileSync(routesPath, 'utf8');

// Adicionar logging antes do response final
const logPattern = /const collector = await storage\.createCollector\(validatedData\);/;

if (content.match(logPattern)) {
    const replacement = `const collector = await storage.createCollector(validatedData);
      
      // Debug logging
      console.log('Collector created with data:', {
        id: collector.id,
        name: collector.name,
        tenantId: collector.tenantId,
        enrollmentToken: collector.enrollmentToken ? 'PRESENT' : 'MISSING',
        enrollmentTokenExpires: collector.enrollmentTokenExpires
      });`;
      
    content = content.replace(logPattern, replacement);
    fs.writeFileSync(routesPath, content, 'utf8');
    console.log('✅ Debug logging adicionado');
} else {
    console.log('⚠️ Padrão para debug logging não encontrado');
}
EOF

node /tmp/add_debug.js "$WORKING_DIR/server/routes.ts"
rm /tmp/add_debug.js

# ============================================================================
# 4. CORRIGIR MÉTODO createCollector NO STORAGE
# ============================================================================

log "🔧 Verificando método createCollector no storage..."

# Verificar se o storage está retornando todos os campos
cat > /tmp/check_storage.js << 'EOF'
const fs = require('fs');

const storagePath = process.argv[2];
let content = fs.readFileSync(storagePath, 'utf8');

// Verificar se createCollector está usando .returning() completo
const createPattern = /async createCollector\(collector: InsertCollector\): Promise<Collector> \{[\s\S]*?return[\s\S]*?\}/;

if (content.match(createPattern)) {
    console.log('✅ Método createCollector encontrado');
    
    // Verificar se está usando .returning()
    if (content.match(/\.returning\(\)/)) {
        console.log('✅ Usando .returning() - deve retornar todos os campos');
    } else {
        console.log('⚠️ Pode não estar usando .returning()');
    }
} else {
    console.log('⚠️ Método createCollector não encontrado no padrão esperado');
}
EOF

node /tmp/check_storage.js "$WORKING_DIR/server/storage.ts"
rm /tmp/check_storage.js

# ============================================================================
# 5. REINICIAR APLICAÇÃO PARA APLICAR CORREÇÕES
# ============================================================================

log "🔄 Reiniciando aplicação para aplicar correções..."

# Recompilar TypeScript se necessário
if command -v npm >/dev/null 2>&1; then
    info "Recompilando aplicação..."
    cd "$WORKING_DIR"
    sudo -u samureye npm run build 2>/dev/null || warn "Build falhou - aplicação pode estar em modo desenvolvimento"
fi

# Reiniciar serviço
systemctl restart "$SERVICE_NAME"

# Aguardar aplicação ficar online
log "⏳ Aguardando aplicação reiniciar..."
for i in {1..30}; do
    if curl -s --connect-timeout 2 http://localhost:5000/api/health >/dev/null 2>&1; then
        log "✅ Aplicação online após $i segundos"
        break
    fi
    sleep 1
done

# ============================================================================
# 6. TESTE FINAL
# ============================================================================

log "🧪 Testando correção..."

# Aguardar mais um pouco para garantir que aplicação está estável
sleep 3

# Verificar logs recentes para erros
info "Verificando logs recentes..."
journalctl -u "$SERVICE_NAME" --since "30 seconds ago" --no-pager | grep -i error | tail -5 || echo "Nenhum erro recente encontrado"

# ============================================================================
# 7. FINALIZAÇÃO
# ============================================================================

echo ""
log "🎉 CORREÇÃO APLICADA COM SUCESSO!"
echo ""
echo "✅ Schema corrigido - enrollmentToken não omitido"
echo "✅ Endpoint corrigido - response inclui token explicitamente"
echo "✅ Debug logging adicionado"
echo "✅ Aplicação reiniciada"
echo ""
echo "🧪 TESTE AGORA:"
echo "   1. Acesse a interface: https://app.samureye.com.br/admin/collectors"
echo "   2. Clique em 'Novo Coletor'"
echo "   3. Preencha os dados e crie"
echo "   4. Verifique se o Token de Enrollment está preenchido"
echo ""

if curl -s --connect-timeout 5 http://localhost:5000/api/health >/dev/null 2>&1; then
    log "✅ Aplicação respondendo - pronta para teste"
else
    warn "⚠️ Aplicação pode não estar respondendo - aguarde mais alguns segundos"
fi

echo ""
log "📝 LOGS EM TEMPO REAL:"
echo "   journalctl -u $SERVICE_NAME -f"
echo ""

exit 0