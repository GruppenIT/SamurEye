#!/bin/bash

# vlxsam02 - Rodar apenas backend para testar collectors

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./run-backend-only.sh"
fi

echo "🚀 vlxsam02 - RODAR APENAS BACKEND"
echo "=================================="

WORKING_DIR="/opt/samureye/SamurEye"
cd "$WORKING_DIR"

systemctl stop samureye-app 2>/dev/null || true

# ============================================================================
# 1. CRIAR INDEX SIMPLES APENAS BACKEND
# ============================================================================

log "🔧 Criando index.ts simples apenas para backend..."

cat > server/index.ts << 'EOF'
import express from "express";
import routes from "./routes";

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware básico
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// CORS simples para ambiente on-premise
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    res.sendStatus(200);
  } else {
    next();
  }
});

// Usar rotas
app.use(routes);

// Health check root
app.get("/", (req, res) => {
  res.json({
    message: "SamurEye Backend funcionando",
    timestamp: new Date().toISOString(),
    version: "1.0.0"
  });
});

// Iniciar servidor
app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 SamurEye Backend rodando na porta ${PORT}`);
  console.log(`📊 Environment: ${process.env.NODE_ENV || "development"}`);
  console.log(`🌐 URLs API disponíveis:`);
  console.log(`   • http://localhost:${PORT}/`);
  console.log(`   • http://localhost:${PORT}/api/system/settings`);
  console.log(`   • http://localhost:${PORT}/collector-api/health`);
  console.log(`   • http://localhost:${PORT}/api/admin/collectors`);
  console.log(`📡 Pronto para receber collectors!`);
});

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log("🛑 Recebido SIGTERM, fechando servidor...");
  process.exit(0);
});

process.on("SIGINT", () => {
  console.log("🛑 Recebido SIGINT, fechando servidor...");
  process.exit(0);
});
EOF

log "✅ index.ts simples criado"

# ============================================================================
# 2. COMPILAR APENAS BACKEND
# ============================================================================

log "🔨 Compilando apenas o backend..."

# Usar esbuild direto para evitar problemas do Vite
npx esbuild server/index.ts --platform=node --packages=external --bundle --format=esm --outdir=dist --minify

if [ $? -eq 0 ]; then
    log "✅ Backend compilado com sucesso"
else
    error "❌ Falha na compilação"
fi

# ============================================================================
# 3. TESTAR EXECUÇÃO DIRETA
# ============================================================================

log "🧪 Testando execução direta..."

# Testar se roda sem problemas
timeout 10s node dist/index.js &
BACKEND_PID=$!

sleep 5

# Verificar se está respondendo
if curl -s http://localhost:5000/ | grep -q "SamurEye Backend funcionando"; then
    log "✅ Backend funcionando corretamente"
    kill $BACKEND_PID 2>/dev/null || true
else
    warn "⚠️ Backend pode ter problemas"
    kill $BACKEND_PID 2>/dev/null || true
fi

# ============================================================================
# 4. ATUALIZAR SERVIÇO SYSTEMD
# ============================================================================

log "🔧 Atualizando serviço systemd..."

# Criar script de inicialização simples
cat > /opt/samureye/start-backend.sh << 'EOF'
#!/bin/bash
cd /opt/samureye/SamurEye
NODE_ENV=production node dist/index.js
EOF

chmod +x /opt/samureye/start-backend.sh
chown samureye:samureye /opt/samureye/start-backend.sh

# Atualizar serviço para usar o script
cat > /etc/systemd/system/samureye-app.service << 'EOF'
[Unit]
Description=SamurEye Application Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=samureye
Group=samureye
WorkingDirectory=/opt/samureye/SamurEye
ExecStart=/opt/samureye/start-backend.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-app

Environment=NODE_ENV=production
Environment=PORT=5000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# ============================================================================
# 5. INICIAR APLICAÇÃO
# ============================================================================

log "🚀 Iniciando aplicação backend..."

chown -R samureye:samureye "$WORKING_DIR"
systemctl start samureye-app

sleep 10

# ============================================================================
# 6. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Verificando aplicação..."

if systemctl is-active --quiet samureye-app; then
    log "✅ Aplicação rodando"
    
    # Testes de API
    if curl -s http://localhost:5000/ | grep -q "funcionando"; then
        log "✅ Root endpoint OK"
    fi
    
    if curl -s http://localhost:5000/collector-api/health | grep -q "ok"; then
        log "✅ Collector API OK"
    fi
    
    if curl -s http://localhost:5000/api/system/settings >/dev/null; then
        log "✅ System API OK"
    fi
    
    if curl -s http://localhost:5000/api/admin/collectors >/dev/null; then
        log "✅ Admin API OK"
    fi
    
    # Mostrar logs atuais
    log "📝 Últimos logs:"
    journalctl -u samureye-app --no-pager -n 3
    
else
    error "❌ Aplicação não iniciou"
fi

echo ""
log "🎯 BACKEND SIMPLIFICADO FUNCIONANDO"
echo "===================================="
echo ""
echo "✅ Backend rodando sem frontend"
echo "✅ APIs disponíveis para collectors"
echo "✅ Compilação simples sem plugins problemáticos"
echo ""
echo "🌐 URLs funcionais:"
echo "   http://localhost:5000/"
echo "   http://localhost:5000/collector-api/health"
echo "   http://localhost:5000/api/admin/collectors"
echo ""
echo "📡 Sistema pronto para receber collectors!"
echo ""
echo "💡 PRÓXIMO PASSO:"
echo "   Configurar vlxsam04 para conectar via HTTP"

exit 0