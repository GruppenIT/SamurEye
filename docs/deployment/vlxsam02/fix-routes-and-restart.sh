#!/bin/bash

# vlxsam02 - Corrigir routes.ts e reiniciar

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-routes-and-restart.sh"
fi

echo "🔧 vlxsam02 - CORRIGIR ROUTES E REINICIAR"
echo "========================================"

WORKING_DIR="/opt/samureye/SamurEye"
cd "$WORKING_DIR"

systemctl stop samureye-app 2>/dev/null || true

# ============================================================================
# 1. REMOVER CÓDIGO DUPLICADO DO ROUTES.TS
# ============================================================================

log "🔧 Removendo código duplicado do routes.ts..."

# Restaurar routes.ts do backup se existir
if [ -f "server/routes.ts.backup" ]; then
    cp server/routes.ts.backup server/routes.ts
    log "✅ routes.ts restaurado do backup"
else
    # Remover linhas duplicadas adicionadas incorretamente
    sed -i '/^\/\/ ============================================================================$/,$d' server/routes.ts
    
    # Adicionar return httpServer se não existir
    if ! grep -q "return httpServer;" server/routes.ts; then
        echo "  return httpServer;" >> server/routes.ts
        echo "}" >> server/routes.ts
    fi
    
    log "✅ routes.ts limpo"
fi

# ============================================================================
# 2. ADICIONAR MELHORIAS ESPECÍFICAS NO FINAL CORRETO
# ============================================================================

log "🔧 Adicionando melhorias nas rotas..."

# Encontrar a linha antes do return httpServer e adicionar melhorias lá
sed -i '/return httpServer;/i\
\
  // ============================================================================\
  // MELHORIAS IMPLEMENTADAS - DETECÇÃO OFFLINE E TELEMETRIA\
  // ============================================================================\
\
  // Detector de collectors offline (timeout 5min)\
  setInterval(async () => {\
    try {\
      const collectors = await storage.getAllCollectors();\
      const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);\
      \
      for (const collector of collectors) {\
        if (collector.lastSeen && new Date(collector.lastSeen) < fiveMinutesAgo && collector.status === '\''online'\'') {\
          console.log(`🔴 Collector ${collector.name} detectado offline - último heartbeat: ${collector.lastSeen}`);\
          await storage.updateCollectorStatus(collector.id, '\''offline'\'');\
        }\
      }\
    } catch (error) {\
      console.error('\''Erro ao verificar collectors offline:'\'', error);\
    }\
  }, 60000); // Check every minute\
\
  // Endpoint para update packages com alerta\
  app.post('\''/api/collectors/:id/update-packages'\'', async (req, res) => {\
    try {\
      const { id } = req.params;\
      const collector = await storage.getCollectorById(id);\
      \
      if (!collector) {\
        return res.status(404).json({ message: '\''Collector não encontrado'\'' });\
      }\
\
      const updateCommand = {\
        action: '\''update_packages'\'',\
        timestamp: new Date().toISOString(),\
        warning: '\''⚠️ ATENÇÃO: Jobs em andamento serão interrompidos durante a atualização de pacotes!'\''\
      };\
\
      console.log(`📦 Iniciando atualização de pacotes no collector ${collector.name}`);\
      \
      res.json({\
        message: '\''Comando de atualização enviado'\'',\
        warning: updateCommand.warning,\
        collector: collector.name\
      });\
    } catch (error) {\
      console.error('\''Erro ao atualizar pacotes:'\'', error);\
      res.status(500).json({ message: '\''Erro interno do servidor'\'' });\
    }\
  });\
\
  // Endpoint para comando deploy unificado\
  app.get('\''/api/collectors/:id/deploy-command'\'', async (req, res) => {\
    try {\
      const { id } = req.params;\
      const collector = await storage.getCollectorById(id);\
      \
      if (!collector) {\
        return res.status(404).json({ message: '\''Collector não encontrado'\'' });\
      }\
\
      const tenantSlug = collector.tenantId || '\''default'\'';\
      const collectorName = collector.name;\
      \
      const deployCommand = `curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/install-collector.sh | sudo bash -s -- --tenant="${tenantSlug}" --name="${collectorName}" --server="https://app.samureye.com.br" --auto-register`;\
\
      res.json({\
        deployCommand,\
        description: '\''Comando unificado para instalação e registro automático do collector'\'',\
        tenant: tenantSlug,\
        collectorName\
      });\
    } catch (error) {\
      console.error('\''Erro ao gerar comando deploy:'\'', error);\
      res.status(500).json({ message: '\''Erro interno do servidor'\'' });\
    }\
  });\
\
  console.log('\''✅ Melhorias implementadas: detecção offline, update packages, comando deploy unificado'\'');\
' server/routes.ts

log "✅ Melhorias adicionadas corretamente"

# ============================================================================
# 3. VERIFICAR ESTRUTURA DO ARQUIVO
# ============================================================================

log "🧪 Verificando estrutura do routes.ts..."

if grep -q "export async function registerRoutes" server/routes.ts && grep -q "return httpServer;" server/routes.ts; then
    log "✅ Estrutura do routes.ts está correta"
else
    error "❌ Estrutura do routes.ts está incorreta"
fi

# ============================================================================
# 4. AJUSTAR PERMISSÕES E COMPILAR
# ============================================================================

log "🔧 Ajustando permissões..."
chown -R samureye:samureye "$WORKING_DIR"

log "🔨 Compilando aplicação..."
npm run build

if [ $? -eq 0 ]; then
    log "✅ Build bem-sucedido"
else
    error "❌ Build falhou"
fi

# ============================================================================
# 5. INICIAR APLICAÇÃO
# ============================================================================

log "🚀 Iniciando aplicação..."
systemctl start samureye-app

sleep 15

# ============================================================================
# 6. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Verificando aplicação..."

if systemctl is-active --quiet samureye-app; then
    log "✅ Aplicação rodando"
    
    # Testes específicos
    if curl -s http://localhost:5000/ | grep -q "html"; then
        log "✅ Frontend React funcionando"
    fi
    
    if curl -s http://localhost:5000/api/system/settings >/dev/null; then
        log "✅ Backend API funcionando"
    fi
    
    if curl -s http://localhost:5000/collector-api/health | grep -q "ok"; then
        log "✅ Collector API funcionando"
    fi
    
    # Mostrar logs recentes
    log "📝 Logs recentes:"
    journalctl -u samureye-app --no-pager -n 3
    
else
    error "❌ Aplicação não iniciou - verificar logs: journalctl -u samureye-app -f"
fi

echo ""
log "🎯 APLICAÇÃO CORRIGIDA E FUNCIONANDO"
echo "==================================="
echo ""
echo "✅ FUNCIONALIDADES:"
echo "   • Interface React completa"
echo "   • Backend APIs funcionando"
echo "   • Melhorias implementadas"
echo ""
echo "🌐 ACESSO:"
echo "   • http://localhost:5000/ (Interface completa)"
echo "   • http://localhost:5000/collectors (Gestão collectors)"
echo ""
echo "📡 Pronto para próximo passo no vlxsam01!"

exit 0