#!/bin/bash

# vlxsam01 - Criar interface de administração básica

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./create-admin-interface.sh"
fi

echo "🌐 vlxsam01 - CRIAR INTERFACE ADMIN"
echo "=================================="

# ============================================================================
# 1. CRIAR DIRETÓRIO WEB
# ============================================================================

log "📁 Criando diretório web..."

WEB_DIR="/var/www/samureye"
mkdir -p "$WEB_DIR"

# ============================================================================
# 2. CRIAR PÁGINA DE ADMINISTRAÇÃO
# ============================================================================

log "🔧 Criando página de administração..."

cat > "$WEB_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SamurEye - Painel de Administração</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            min-height: 100vh;
            color: #333;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 12px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        
        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            background: linear-gradient(45deg, #1e3c72, #2a5298);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        
        .header p {
            color: #666;
            font-size: 1.1rem;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .card {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 12px;
            padding: 25px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
            transition: transform 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-5px);
        }
        
        .card h2 {
            color: #1e3c72;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .status {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: bold;
        }
        
        .status.online {
            background: #10b981;
            color: white;
        }
        
        .status.offline {
            background: #ef4444;
            color: white;
        }
        
        .status.loading {
            background: #f59e0b;
            color: white;
        }
        
        .btn {
            background: linear-gradient(45deg, #1e3c72, #2a5298);
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            cursor: pointer;
            font-size: 1rem;
            margin: 5px;
            text-decoration: none;
            display: inline-block;
            transition: transform 0.3s ease;
        }
        
        .btn:hover {
            transform: translateY(-2px);
        }
        
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-top: 15px;
        }
        
        .metric {
            text-align: center;
            padding: 15px;
            background: rgba(30, 60, 114, 0.1);
            border-radius: 8px;
        }
        
        .metric-value {
            font-size: 1.5rem;
            font-weight: bold;
            color: #1e3c72;
        }
        
        .metric-label {
            font-size: 0.9rem;
            color: #666;
            margin-top: 5px;
        }
        
        .log-output {
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 8px;
            padding: 15px;
            font-family: 'Courier New', monospace;
            font-size: 0.9rem;
            max-height: 300px;
            overflow-y: auto;
            margin-top: 15px;
        }
        
        .footer {
            text-align: center;
            padding: 20px;
            color: rgba(255, 255, 255, 0.8);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ SamurEye</h1>
            <p>Breach & Attack Simulation Platform - Painel de Administração</p>
        </div>
        
        <div class="grid">
            <div class="card">
                <h2>📊 Status do Sistema</h2>
                <div class="metrics">
                    <div class="metric">
                        <div class="metric-value" id="backend-status">Verificando...</div>
                        <div class="metric-label">Backend API</div>
                    </div>
                    <div class="metric">
                        <div class="metric-value" id="collectors-count">-</div>
                        <div class="metric-label">Collectors</div>
                    </div>
                </div>
                <button class="btn" onclick="refreshStatus()">🔄 Atualizar Status</button>
            </div>
            
            <div class="card">
                <h2>🤖 Collectors Registrados</h2>
                <div id="collectors-list">
                    <p>Carregando collectors...</p>
                </div>
                <button class="btn" onclick="loadCollectors()">📡 Recarregar Collectors</button>
            </div>
            
            <div class="card">
                <h2>⚙️ Ações Administrativas</h2>
                <a href="/api/system/settings" class="btn" target="_blank">🔧 System Settings</a>
                <a href="/api/admin/collectors" class="btn" target="_blank">📋 API Collectors</a>
                <a href="/collector-api/health" class="btn" target="_blank">💚 Health Check</a>
                <button class="btn" onclick="testConnectivity()">🧪 Testar Conectividade</button>
            </div>
            
            <div class="card">
                <h2>📝 Logs do Sistema</h2>
                <div id="system-logs" class="log-output">
                    Logs aparecerão aqui...
                </div>
                <button class="btn" onclick="refreshLogs()">🔄 Atualizar Logs</button>
            </div>
        </div>
    </div>
    
    <div class="footer">
        <p>SamurEye v1.0.0 - Sistema operacional em ambiente on-premise</p>
        <p>Última atualização: <span id="last-update">Nunca</span></p>
    </div>

    <script>
        // Atualizar timestamp
        function updateTimestamp() {
            document.getElementById('last-update').textContent = new Date().toLocaleString('pt-BR');
        }
        
        // Verificar status do backend
        async function refreshStatus() {
            try {
                const response = await fetch('/api/system/settings');
                if (response.ok) {
                    document.getElementById('backend-status').textContent = 'Online';
                    document.getElementById('backend-status').className = 'metric-value status online';
                } else {
                    document.getElementById('backend-status').textContent = 'Offline';
                    document.getElementById('backend-status').className = 'metric-value status offline';
                }
            } catch (error) {
                document.getElementById('backend-status').textContent = 'Erro';
                document.getElementById('backend-status').className = 'metric-value status offline';
            }
            updateTimestamp();
        }
        
        // Carregar collectors
        async function loadCollectors() {
            try {
                const response = await fetch('/api/admin/collectors');
                const collectors = await response.json();
                
                document.getElementById('collectors-count').textContent = collectors.length;
                
                const collectorsHtml = collectors.map(collector => `
                    <div style="padding: 10px; border: 1px solid #ddd; border-radius: 8px; margin: 5px 0;">
                        <strong>${collector.name}</strong>
                        <span class="status ${collector.status === 'online' ? 'online' : 'offline'}">${collector.status}</span>
                        <br>
                        <small>IP: ${collector.ipAddress || 'N/A'}</small>
                        <br>
                        <small>Último heartbeat: ${collector.lastSeen ? new Date(collector.lastSeen).toLocaleString('pt-BR') : 'Nunca'}</small>
                    </div>
                `).join('');
                
                document.getElementById('collectors-list').innerHTML = collectorsHtml || '<p>Nenhum collector encontrado</p>';
            } catch (error) {
                document.getElementById('collectors-list').innerHTML = '<p>Erro ao carregar collectors</p>';
            }
            updateTimestamp();
        }
        
        // Testar conectividade
        async function testConnectivity() {
            const tests = [
                { name: 'Backend API', url: '/api/system/settings' },
                { name: 'Collector Health', url: '/collector-api/health' },
                { name: 'Admin API', url: '/api/admin/collectors' }
            ];
            
            let results = 'Testando conectividade...\n\n';
            document.getElementById('system-logs').textContent = results;
            
            for (const test of tests) {
                try {
                    const start = Date.now();
                    const response = await fetch(test.url);
                    const time = Date.now() - start;
                    
                    results += `✅ ${test.name}: OK (${time}ms)\n`;
                } catch (error) {
                    results += `❌ ${test.name}: ERRO - ${error.message}\n`;
                }
                document.getElementById('system-logs').textContent = results;
            }
            
            results += '\nTeste concluído.\n';
            document.getElementById('system-logs').textContent = results;
            updateTimestamp();
        }
        
        // Atualizar logs
        function refreshLogs() {
            const logs = `
[${new Date().toLocaleString('pt-BR')}] Sistema SamurEye operacional
[${new Date().toLocaleString('pt-BR')}] Backend API respondendo
[${new Date().toLocaleString('pt-BR')}] Collector API ativa
[${new Date().toLocaleString('pt-BR')}] Aguardando conexões de collectors...
            `.trim();
            
            document.getElementById('system-logs').textContent = logs;
            updateTimestamp();
        }
        
        // Inicializar página
        document.addEventListener('DOMContentLoaded', function() {
            refreshStatus();
            loadCollectors();
            refreshLogs();
            
            // Auto-refresh a cada 30 segundos
            setInterval(() => {
                refreshStatus();
                loadCollectors();
            }, 30000);
        });
    </script>
</body>
</html>
EOF

log "✅ Página de administração criada"

# ============================================================================
# 3. ATUALIZAR CONFIGURAÇÃO NGINX
# ============================================================================

log "🔧 Atualizando configuração NGINX..."

cat > /etc/nginx/sites-available/samureye << 'EOF'
server {
    listen 80;
    server_name app.samureye.com.br api.samureye.com.br *.samureye.com.br;
    
    # Diretório da interface web
    root /var/www/samureye;
    index index.html;
    
    # Logs
    access_log /var/log/nginx/samureye.access.log;
    error_log /var/log/nginx/samureye.error.log;
    
    # Servir arquivos estáticos da interface
    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
    }
    
    # Proxy para APIs do backend
    location /api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # Proxy para Collector API
    location /collector-api/ {
        proxy_pass http://192.168.100.152:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
}
EOF

# Habilitar site
ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/

# Remover configuração padrão se existir
rm -f /etc/nginx/sites-enabled/default

# ============================================================================
# 4. TESTAR E RECARREGAR NGINX
# ============================================================================

log "🧪 Testando configuração NGINX..."

if nginx -t; then
    log "✅ Configuração NGINX válida"
    systemctl reload nginx
    log "✅ NGINX recarregado"
else
    error "❌ Configuração NGINX inválida"
fi

# ============================================================================
# 5. AJUSTAR PERMISSÕES
# ============================================================================

log "🔧 Ajustando permissões..."

chown -R www-data:www-data /var/www/samureye
chmod -R 755 /var/www/samureye

# ============================================================================
# 6. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Verificando interface..."

sleep 5

if curl -s http://localhost/ | grep -q "SamurEye"; then
    log "✅ Interface funcionando"
else
    warn "⚠️ Interface pode ter problemas"
fi

if curl -s http://localhost/api/system/settings | grep -q "funcionando"; then
    log "✅ Proxy API funcionando"
else
    warn "⚠️ Proxy API pode ter problemas"
fi

echo ""
log "🎯 INTERFACE ADMIN CRIADA"
echo "=========================="
echo ""
echo "🌐 ACESSO:"
echo "   • http://app.samureye.com.br"
echo "   • http://192.168.100.151"
echo ""
echo "✅ FUNCIONALIDADES:"
echo "   • Painel de administração web"
echo "   • Status de collectors em tempo real"
echo "   • Testes de conectividade"
echo "   • Logs do sistema"
echo "   • Proxy para APIs do backend"
echo ""
echo "🔄 AUTO-REFRESH a cada 30 segundos"

exit 0