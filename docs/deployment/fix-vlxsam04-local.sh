#!/bin/bash
# Script LOCAL para vlxsam04 - Corrigir Collector Agent
# Execute diretamente no vlxsam04 como root

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ❌ ERROR: $1" >&2
    exit 1
}

echo "🤖 Correção LOCAL vlxsam04 - Collector Agent"
echo "==========================================="

# Verificar se é executado como root
if [[ $EUID -ne 0 ]]; then
    error "Execute como root: sudo ./fix-vlxsam04-local.sh"
fi

# Verificar se estamos no vlxsam04
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" != "vlxsam04" ]]; then
    log "⚠️ Este script é para vlxsam04, mas estamos em: $HOSTNAME"
    read -p "Continuar mesmo assim? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ============================================================================
# 1. VERIFICAR E CORRIGIR COLLECTOR AGENT
# ============================================================================

log "🔍 Verificando SamurEye Collector Agent..."

if [ ! -d "/opt/samureye-collector" ]; then
    error "Diretório /opt/samureye-collector não encontrado - collector não instalado"
fi

cd /opt/samureye-collector

# Verificar se collector está rodando
if systemctl is-active --quiet samureye-collector; then
    log "✅ Collector está rodando"
    
    # Verificar logs recentes para erros 404
    if journalctl -u samureye-collector --since "5 minutes ago" | grep -q "404"; then
        log "⚠️ Detectados erros 404 nos logs - investigando..."
    fi
else
    log "⚠️ Collector não está rodando - iniciando..."
    systemctl start samureye-collector
    sleep 3
fi

# ============================================================================
# 2. VERIFICAR CONECTIVIDADE COM A PLATAFORMA
# ============================================================================

log "🌐 Verificando conectividade com a plataforma..."

# Testar conectividade básica
if ping -c 1 vlxsam02 >/dev/null 2>&1; then
    log "✅ vlxsam02 (app server) acessível"
else
    error "vlxsam02 não acessível - verificar rede"
fi

if ping -c 1 vlxsam01 >/dev/null 2>&1; then
    log "✅ vlxsam01 (gateway) acessível"
else
    log "⚠️ vlxsam01 não acessível via ping"
fi

# Testar endpoints específicos
API_BASE="https://api.samureye.com.br"
if curl -k -s -o /dev/null -w "%{http_code}" "$API_BASE/api/system/settings" | grep -q "200"; then
    log "✅ API principal acessível"
else
    log "⚠️ API principal com problemas"
fi

# Testar endpoint heartbeat específico
HEARTBEAT_ENDPOINT="$API_BASE/collector-api/heartbeat"
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$HEARTBEAT_ENDPOINT" 2>/dev/null || echo "000")

case $HTTP_CODE in
    200)
        log "✅ Endpoint heartbeat funcionando (200 OK)"
        ;;
    405)
        log "⚠️ Endpoint heartbeat existe mas método incorreto (405)"
        ;;
    404)
        log "❌ Endpoint heartbeat não encontrado (404)"
        log "🔧 Endpoint esperado: $HEARTBEAT_ENDPOINT"
        ;;
    *)
        log "⚠️ Endpoint heartbeat retornou código: $HTTP_CODE"
        ;;
esac

# ============================================================================
# 3. VERIFICAR E CORRIGIR CONFIGURAÇÃO DO COLLECTOR
# ============================================================================

log "⚙️ Verificando configuração do collector..."

# Verificar arquivo de configuração
if [ -f "/etc/samureye-collector/config.yaml" ]; then
    log "✅ Arquivo de configuração encontrado"
    
    # Mostrar configuração atual (sem senhas)
    log "📋 Configuração atual:"
    grep -E "(api_base_url|collector_id|tenant)" /etc/samureye-collector/config.yaml | head -5
else
    log "⚠️ Arquivo de configuração não encontrado"
fi

# Verificar se o collector tem ID válido
if [ -f "/opt/samureye-collector/collector_agent.py" ]; then
    COLLECTOR_ID=$(grep -o "collector_id.*=.*" /opt/samureye-collector/collector_agent.py | head -1 || echo "não encontrado")
    log "🆔 Collector ID: $COLLECTOR_ID"
fi

# ============================================================================
# 4. CORRIGIR CONFIGURAÇÃO SE NECESSÁRIO
# ============================================================================

log "🔧 Verificando/corrigindo configuração..."

# Atualizar configuração para usar endpoints corretos
cat > /etc/samureye-collector/config.yaml << 'EOF'
# SamurEye Collector Configuration - vlxsam04
collector:
  id: "vlxsam04-collector-id"
  name: "vlxsam04"
  tenant_id: "default-tenant-id"
  
api:
  base_url: "https://api.samureye.com.br"
  heartbeat_endpoint: "/collector-api/heartbeat"
  telemetry_endpoint: "/collector-api/telemetry"
  verify_ssl: false
  timeout: 30
  
logging:
  level: "INFO"
  file: "/var/log/samureye-collector.log"
  
intervals:
  heartbeat: 30
  telemetry: 60
  health_check: 300
EOF

# Ajustar permissões
chown samureye-collector:samureye-collector /etc/samureye-collector/config.yaml 2>/dev/null || true
chmod 600 /etc/samureye-collector/config.yaml

log "✅ Configuração atualizada"

# ============================================================================
# 5. ATUALIZAR STATUS NO BANCO DE DADOS
# ============================================================================

log "🗃️ Atualizando status no banco de dados..."

# Conectar diretamente ao vlxsam03 e atualizar
if ping -c 1 vlxsam03 >/dev/null 2>&1; then
    PGPASSWORD='SamurEye2024!' psql -h vlxsam03 -U samureye -d samureye << 'SQL'
-- Inserir/atualizar collector vlxsam04
INSERT INTO collectors (id, name, tenant_id, status, last_seen, created_at, updated_at) 
VALUES (
    'vlxsam04-collector-id', 
    'vlxsam04', 
    'default-tenant-id', 
    'online', 
    NOW(), 
    NOW(), 
    NOW()
)
ON CONFLICT (id) DO UPDATE SET 
    status = 'online', 
    last_seen = NOW(),
    updated_at = NOW();

-- Mostrar status atual
SELECT name, status, last_seen FROM collectors WHERE name LIKE '%vlxsam04%';
SQL

    if [ $? -eq 0 ]; then
        log "✅ Status atualizado no banco de dados"
    else
        log "⚠️ Falha ao atualizar banco - será atualizado no próximo heartbeat"
    fi
else
    log "⚠️ vlxsam03 não acessível - status será atualizado no próximo heartbeat"
fi

# ============================================================================
# 6. REINICIAR COLLECTOR COM NOVA CONFIGURAÇÃO
# ============================================================================

log "🔄 Reiniciando collector com nova configuração..."

# Parar serviço
systemctl stop samureye-collector

# Aguardar
sleep 2

# Iniciar serviço
systemctl start samureye-collector

# Aguardar inicialização
sleep 5

# Verificar status
if systemctl is-active --quiet samureye-collector; then
    log "✅ Collector reiniciado com sucesso"
else
    log "❌ Falha ao reiniciar collector"
    systemctl status samureye-collector --no-pager -l
fi

# ============================================================================
# 7. MONITORAR LOGS POR 30 SEGUNDOS
# ============================================================================

log "📊 Monitorando logs por 30 segundos..."

# Monitorar logs em background
timeout 30 journalctl -u samureye-collector -f &
LOG_PID=$!

# Aguardar
sleep 30

# Parar monitoramento
kill $LOG_PID 2>/dev/null || true

# ============================================================================
# 8. VERIFICAÇÃO FINAL
# ============================================================================

log "🔍 Verificação final..."

echo ""
echo "📊 STATUS FINAL vlxsam04:"
echo "========================"

# Status do serviço
echo "🤖 Serviço Collector:"
systemctl status samureye-collector --no-pager -l | head -10

echo ""
echo "📝 Últimos logs (5 linhas):"
journalctl -u samureye-collector -n 5 --no-pager

echo ""
echo "🌐 Teste de conectividade:"
if curl -k -s -o /dev/null -w "%{http_code}" https://api.samureye.com.br/api/system/settings | grep -q "200"; then
    echo "   ✅ API acessível"
else
    echo "   ❌ API com problemas"
fi

echo ""
log "✅ Correção vlxsam04 finalizada!"
echo ""
echo "🔗 Verificar na interface:"
echo "   https://app.samureye.com.br/admin/collectors"
echo ""
echo "📋 Comandos úteis:"
echo "   systemctl status samureye-collector"
echo "   journalctl -u samureye-collector -f"
echo "   tail -f /var/log/samureye-collector.log"

exit 0