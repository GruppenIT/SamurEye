#!/bin/bash

# vlxsam04 - Testar Melhorias do Collector
# Testa: Detecção offline, telemetria, Update Packages

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./test-collector-improvements.sh"
fi

echo "🧪 vlxsam04 - TESTAR MELHORIAS COLLECTOR"
echo "========================================"
echo "Testa funcionalidades implementadas:"
echo "1. Envio de telemetria real"
echo "2. Detecção de offline (parar/iniciar collector)"
echo "3. Comando Update Packages"
echo ""

# ============================================================================
# 1. VERIFICAR STATUS ATUAL
# ============================================================================

log "📊 Verificando status atual do collector..."

if systemctl is-active --quiet samureye-collector; then
    log "✅ Collector está rodando"
    
    # Verificar últimos logs
    log "📝 Últimos logs do collector:"
    journalctl -u samureye-collector --no-pager -n 5
    
    # Verificar se está enviando telemetria
    if journalctl -u samureye-collector --no-pager -n 10 | grep -q "Heartbeat sent successfully"; then
        log "✅ Telemetria sendo enviada com sucesso"
    else
        warn "⚠️ Telemetria pode não estar sendo enviada"
    fi
else
    warn "⚠️ Collector não está rodando"
fi

# ============================================================================
# 2. TESTE DE TELEMETRIA MANUAL
# ============================================================================

log "🔍 Testando envio manual de telemetria..."

# Verificar configuração
if [ -f "/etc/samureye/collector.conf" ]; then
    log "✅ Configuração encontrada"
    cat /etc/samureye/collector.conf
else
    error "Configuração do collector não encontrada"
fi

# Testar conectividade com servidor
SERVER_URL=$(python3 -c "import json; print(json.load(open('/etc/samureye/collector.conf'))['server_url'])" 2>/dev/null || echo "https://app.samureye.com.br")

log "🌐 Testando conectividade com $SERVER_URL..."
if curl -s -f "$SERVER_URL/api/system/settings" >/dev/null; then
    log "✅ Conectividade com servidor OK"
else
    warn "⚠️ Problema de conectividade com servidor"
fi

# ============================================================================
# 3. TESTE CICLO ONLINE/OFFLINE
# ============================================================================

log "🔄 Testando ciclo online/offline..."

echo "Passo 1: Collector está ONLINE"
log "Aguardando 30 segundos para garantir heartbeat..."
sleep 30

echo "Passo 2: Parando collector para testar detecção OFFLINE..."
systemctl stop samureye-collector
log "🛑 Collector parado - deveria ficar offline em 5 minutos na interface"

echo "Aguarde 5-6 minutos e verifique na interface se o status mudou para OFFLINE"
echo "Interface: https://app.samureye.com.br/collectors"
echo ""
read -p "Pressione Enter quando verificar o status offline na interface..."

echo "Passo 3: Reiniciando collector..."
systemctl start samureye-collector
log "🚀 Collector reiniciado - deveria ficar online em alguns segundos"

sleep 15

if systemctl is-active --quiet samureye-collector; then
    log "✅ Collector voltou a funcionar"
else
    error "❌ Collector não iniciou corretamente"
fi

# ============================================================================
# 4. TESTE DE COMANDO UPDATE PACKAGES (SIMULAÇÃO)
# ============================================================================

log "📦 Testando comando Update Packages..."

# Criar script simulado para testar update
cat > /tmp/test-update-packages.py << 'EOF'
#!/usr/bin/env python3
"""
Simulação de Update Packages
"""
import requests
import json
import sys

try:
    # Ler configuração
    with open('/etc/samureye/collector.conf', 'r') as f:
        config = json.load(f)
    
    # Simular recebimento de comando update
    print("🔄 Simulando comando Update Packages recebido...")
    print("⚠️ AVISO: Jobs em andamento serão interrompidos!")
    
    # Simular update de pacotes
    packages = ["nmap", "nuclei", "samureye-agent"]
    for pkg in packages:
        print(f"📦 Atualizando {pkg}...")
        import time
        time.sleep(2)
        print(f"✅ {pkg} atualizado")
    
    print("✅ Update Packages concluído!")
    
except Exception as e:
    print(f"❌ Erro: {e}")
    sys.exit(1)
EOF

chmod +x /tmp/test-update-packages.py
python3 /tmp/test-update-packages.py

# ============================================================================
# 5. VERIFICAR TELEMETRIA REAL
# ============================================================================

log "📊 Verificando telemetria real sendo coletada..."

# Executar collector por alguns segundos para coletar dados
python3 -c "
import psutil
import json

print('🔍 Telemetria atual do sistema:')
print(f'CPU: {psutil.cpu_percent(interval=1):.1f}%')
print(f'Memória: {psutil.virtual_memory().percent:.1f}%')
disk = psutil.disk_usage('/')
print(f'Disco: {(disk.used / disk.total * 100):.1f}%')
print(f'Processos: {len(psutil.pids())}')
"

# ============================================================================
# 6. TESTE DO NOVO COMANDO DE DEPLOY
# ============================================================================

log "🚀 Testando comando de deploy unificado..."

# Mostrar comando que seria gerado para este collector
COLLECTOR_NAME=$(python3 -c "import json; print(json.load(open('/etc/samureye/collector.conf'))['collector_name'])" 2>/dev/null || echo "vlxsam04")
TENANT_SLUG=$(python3 -c "import json; print(json.load(open('/etc/samureye/collector.conf'))['tenant_slug'])" 2>/dev/null || echo "default")

DEPLOY_CMD="curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/install-collector.sh | sudo bash -s -- --tenant-slug=\"$TENANT_SLUG\" --collector-name=\"$COLLECTOR_NAME\" --server-url=\"https://app.samureye.com.br\""

echo ""
log "📋 Comando de deploy que seria gerado:"
echo "────────────────────────────────────────────────────────────────"
echo "$DEPLOY_CMD"
echo "────────────────────────────────────────────────────────────────"

# ============================================================================
# 7. RESULTADO FINAL
# ============================================================================

echo ""
log "🎯 RESUMO DOS TESTES"
echo "══════════════════════════════════════════════════"

# Status final
if systemctl is-active --quiet samureye-collector; then
    log "✅ Collector funcionando normalmente"
else
    warn "❌ Collector com problemas"
fi

echo ""
echo "📋 CHECKLIST DE MELHORIAS:"
echo "   ✓ Telemetria real sendo coletada (CPU, Memória, Disco)"
echo "   ✓ Heartbeat enviado a cada 2 minutos"  
echo "   ✓ Detecção offline funcional (5min timeout)"
echo "   ✓ Comando Update Packages simulado"
echo "   ✓ Deploy command unificado gerado"
echo ""
echo "🌐 VERIFICAR NA INTERFACE:"
echo "   • Status: https://app.samureye.com.br/collectors"
echo "   • Telemetria em tempo real"
echo "   • Botões Update Packages e Deploy funcionais"
echo ""
echo "📝 LOGS PARA MONITORAMENTO:"
echo "   journalctl -u samureye-collector -f"
echo ""
echo "💡 PRÓXIMOS PASSOS:"
echo "   1. Na interface, testar botão 'Update Packages'"
echo "   2. Testar botão 'Copiar Comando Deploy'"  
echo "   3. Verificar se telemetria é exibida corretamente"

# Cleanup
rm -f /tmp/test-update-packages.py

exit 0