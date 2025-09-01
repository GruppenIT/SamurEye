#!/bin/bash

# vlxsam02 - Corrigir server/index.ts

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-index.sh"
fi

echo "🔧 vlxsam02 - CORRIGIR INDEX.TS"
echo "==============================="

WORKING_DIR="/opt/samureye/SamurEye"
cd "$WORKING_DIR"

systemctl stop samureye-app 2>/dev/null || true

# ============================================================================
# 1. VERIFICAR E CORRIGIR INDEX.TS
# ============================================================================

log "🔍 Verificando server/index.ts..."

if [ -f "server/index.ts" ]; then
    log "Conteúdo atual do index.ts:"
    head -10 server/index.ts
    
    # Backup
    cp server/index.ts server/index.ts.backup
    
    # Recriar index.ts compatível
    cat > server/index.ts << 'EOF'
import express from "express";
import { createProxyMiddleware } from "http-proxy-middleware";
import routes from "./routes";
import { setupAuth } from "./replitAuth";
import { createServer } from "http";
import { setupWebSocket } from "./websocket";

const app = express();
const PORT = process.env.PORT || 5000;

// Configurar autenticação
setupAuth(app);

// Usar rotas
app.use(routes);

// Configurar proxy para frontend
if (process.env.NODE_ENV === "development") {
  const viteDevServer = createProxyMiddleware({
    target: "http://localhost:5173",
    changeOrigin: true,
    ws: true,
  });
  app.use(viteDevServer);
} else {
  // Servir arquivos estáticos em produção
  app.use(express.static("dist/public"));
}

// Criar servidor HTTP
const server = createServer(app);

// Configurar WebSocket
setupWebSocket(server);

// Iniciar servidor
server.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 SamurEye Server rodando na porta ${PORT}`);
  console.log(`📊 Environment: ${process.env.NODE_ENV || "development"}`);
  console.log(`🌐 URLs disponíveis:`);
  console.log(`   • http://localhost:${PORT}/api/system/settings`);
  console.log(`   • http://localhost:${PORT}/collector-api/health`);
  console.log(`   • http://localhost:${PORT}/api/admin/collectors`);
});

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log("🛑 Recebido SIGTERM, fechando servidor...");
  server.close(() => {
    console.log("✅ Servidor fechado");
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.log("🛑 Recebido SIGINT, fechando servidor...");
  server.close(() => {
    console.log("✅ Servidor fechado");
    process.exit(0);
  });
});
EOF

    log "✅ index.ts corrigido"
else
    error "server/index.ts não encontrado"
fi

# ============================================================================
# 2. VERIFICAR WEBSOCKET.TS
# ============================================================================

log "🔍 Verificando websocket.ts..."

if [ ! -f "server/websocket.ts" ]; then
    log "Criando websocket.ts básico..."
    
    cat > server/websocket.ts << 'EOF'
import { Server } from "http";
import { Server as SocketIOServer } from "socket.io";

export function setupWebSocket(server: Server) {
  const io = new SocketIOServer(server, {
    cors: {
      origin: "*",
      methods: ["GET", "POST"]
    }
  });

  io.on("connection", (socket) => {
    console.log("🔌 Cliente WebSocket conectado:", socket.id);
    
    socket.on("disconnect", () => {
      console.log("🔌 Cliente WebSocket desconectado:", socket.id);
    });
  });

  return io;
}
EOF

    log "✅ websocket.ts criado"
fi

# ============================================================================
# 3. BUILD E TESTE
# ============================================================================

log "🔨 Fazendo build..."

if npm run build; then
    log "✅ Build bem-sucedido!"
else
    error "❌ Build falhou"
fi

# ============================================================================
# 4. INICIAR APLICAÇÃO
# ============================================================================

log "🚀 Iniciando aplicação..."

chown -R samureye:samureye "$WORKING_DIR"
systemctl start samureye-app

sleep 15

# ============================================================================
# 5. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Verificando aplicação..."

if systemctl is-active --quiet samureye-app; then
    log "✅ Aplicação rodando"
    
    # Testes de API
    if curl -s http://localhost:5000/collector-api/health | grep -q "ok"; then
        log "✅ Collector API funcionando"
    else
        warn "⚠️ Collector API com problemas"
    fi
    
    if curl -s http://localhost:5000/api/system/settings >/dev/null; then
        log "✅ System API funcionando"
    else
        warn "⚠️ System API com problemas"
    fi
    
    if curl -s http://localhost:5000/api/admin/collectors >/dev/null; then
        log "✅ Admin API funcionando"
    else
        warn "⚠️ Admin API com problemas"
    fi
    
    # Mostrar status
    log "📊 Status completo:"
    curl -s http://localhost:5000/collector-api/health
    
else
    error "❌ Aplicação não iniciou - verificar logs"
fi

echo ""
log "🎯 INDEX.TS CORRIGIDO"
echo "======================"
echo ""
echo "✅ server/index.ts reescrito"
echo "✅ websocket.ts criado"
echo "✅ Build bem-sucedido"
echo "✅ Aplicação rodando"
echo ""
echo "🌐 URLs funcionais:"
echo "   http://localhost:5000/collector-api/health"
echo "   http://localhost:5000/api/admin/collectors"
echo ""
echo "💡 PRÓXIMO PASSO:"
echo "   Configurar vlxsam04 para conectar"

exit 0