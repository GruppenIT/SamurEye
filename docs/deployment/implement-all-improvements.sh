#!/bin/bash

# IMPLEMENTAR TODAS AS MELHORIAS DOS COLLECTORS
# Script mestre para executar melhorias em todas as VMs

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

clear
echo "🚀 SAMUREYE - IMPLEMENTAR MELHORIAS DOS COLLECTORS"
echo "=================================================="
echo ""
echo "Este script orienta a implementação das melhorias em cada VM:"
echo ""
echo "📋 MELHORIAS A IMPLEMENTAR:"
echo "   ✓ Detecção automática de status offline (5min timeout)"
echo "   ✓ Telemetria real do collector (CPU, memória, disco)"  
echo "   ✓ Botão Update Packages funcional com alertas"
echo "   ✓ Comando Deploy unificado (copy-paste)"
echo "   ✓ Interface atualizada com dados reais"
echo ""

# ============================================================================
# VERIFICAÇÃO DE REQUISITOS
# ============================================================================

log "🔍 Verificando ambiente..."

# Verificar se estamos no diretório correto
if [ ! -f "docs/deployment/vlxsam01/update-certificates.sh" ]; then
    error "Execute a partir do diretório raiz do projeto SamurEye"
fi

# Verificar conectividade com VMs (opcional)
VMs=("192.168.100.151" "192.168.100.152" "192.168.100.153" "192.168.100.154")
VM_NAMES=("vlxsam01" "vlxsam02" "vlxsam03" "vlxsam04")

echo ""
info "🌐 Verificando conectividade com VMs..."
for i in "${!VMs[@]}"; do
    if ping -c 1 -W 2 "${VMs[$i]}" >/dev/null 2>&1; then
        log "✅ ${VM_NAMES[$i]} (${VMs[$i]}) - Online"
    else
        warn "⚠️ ${VM_NAMES[$i]} (${VMs[$i]}) - Não acessível"
    fi
done

# ============================================================================
# INSTRUÇÕES DE IMPLEMENTAÇÃO
# ============================================================================

echo ""
echo "📋 SEQUÊNCIA DE IMPLEMENTAÇÃO RECOMENDADA:"
echo "=========================================="

echo ""
echo "🔐 PASSO 1: vlxsam01 (Gateway + NGINX + SSL)"
echo "────────────────────────────────────────────────────────────────"
echo "Conecte na VM vlxsam01 e execute:"
echo ""
echo "  scp docs/deployment/vlxsam01/update-certificates.sh root@192.168.100.151:/tmp/"
echo "  ssh root@192.168.100.151"
echo "  chmod +x /tmp/update-certificates.sh"
echo "  /tmp/update-certificates.sh"
echo ""
echo "🎯 OBJETIVO: Otimizar NGINX e SSL para APIs dos collectors"

echo ""
echo "🗄️ PASSO 2: vlxsam03 (PostgreSQL + Otimizações)"
echo "────────────────────────────────────────────────────────────────"
echo "Conecte na VM vlxsam03 e execute:"
echo ""
echo "  scp docs/deployment/vlxsam03/optimize-database.sh root@192.168.100.153:/tmp/"
echo "  ssh root@192.168.100.153"
echo "  chmod +x /tmp/optimize-database.sh"
echo "  /tmp/optimize-database.sh"
echo ""
echo "🎯 OBJETIVO: Criar índices, limpeza automática e detecção offline"

echo ""
echo "🚀 PASSO 3: vlxsam02 (Aplicação + Melhorias)"
echo "────────────────────────────────────────────────────────────────"
echo "Conecte na VM vlxsam02 e execute:"
echo ""
echo "  scp docs/deployment/vlxsam02/apply-collector-improvements.sh root@192.168.100.152:/tmp/"
echo "  ssh root@192.168.100.152"
echo "  chmod +x /tmp/apply-collector-improvements.sh"
echo "  /tmp/apply-collector-improvements.sh"
echo ""
echo "🎯 OBJETIVO: Aplicar código atualizado com todas as funcionalidades"

echo ""
echo "🧪 PASSO 4: vlxsam04 (Teste do Collector)"
echo "────────────────────────────────────────────────────────────────"
echo "Conecte na VM vlxsam04 e execute:"
echo ""
echo "  scp docs/deployment/vlxsam04/test-collector-improvements.sh root@192.168.100.154:/tmp/"
echo "  ssh root@192.168.100.154"
echo "  chmod +x /tmp/test-collector-improvements.sh"
echo "  /tmp/test-collector-improvements.sh"
echo ""
echo "🎯 OBJETIVO: Testar telemetria, detecção offline e comandos"

# ============================================================================
# VERIFICAÇÕES APÓS IMPLEMENTAÇÃO
# ============================================================================

echo ""
echo "✅ VERIFICAÇÕES APÓS IMPLEMENTAÇÃO:"
echo "════════════════════════════════════"
echo ""
echo "1. 🌐 Interface Web:"
echo "   https://app.samureye.com.br/collectors"
echo "   • Status do collector deve aparecer como 'online'"
echo "   • Telemetria real (CPU, memória, disco) deve ser exibida"
echo ""
echo "2. 🔄 Teste Offline:"
echo "   • Parar collector: systemctl stop samureye-collector"
echo "   • Aguardar 5-6 minutos"
echo "   • Interface deve mostrar status 'offline'"
echo ""
echo "3. 📦 Teste Update Packages:"
echo "   • Clicar no botão 'Update Packages'"
echo "   • Deve mostrar aviso sobre jobs interrompidos"
echo ""
echo "4. 🚀 Teste Deploy Command:"
echo "   • Clicar no botão 'Copiar Comando Deploy'"
echo "   • Comando deve ser copiado para área de transferência"

# ============================================================================
# COMANDO DE DEPLOY GERADO
# ============================================================================

echo ""
echo "🎯 COMANDO DE DEPLOY UNIFICADO FINAL:"
echo "════════════════════════════════════"
echo ""
echo "Para instalar um novo collector, use:"
echo ""
echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/install-collector.sh | sudo bash -s -- --tenant-slug=\"NOME-TENANT\" --collector-name=\"NOME-COLLECTOR\" --server-url=\"https://app.samureye.com.br\""
echo ""
echo "Exemplo prático:"
echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/install-collector.sh | sudo bash -s -- --tenant-slug=\"empresa-teste\" --collector-name=\"servidor-web-01\" --server-url=\"https://app.samureye.com.br\""

# ============================================================================
# SCRIPTS LOCAIS ALTERNATIVOS
# ============================================================================

echo ""
echo "📋 SCRIPTS LOCAIS (Alternativa sem SSH):"
echo "========================================"
echo ""
echo "Se não conseguir usar SCP/SSH, copie manualmente:"
echo ""
echo "vlxsam01:"
echo "  cat docs/deployment/vlxsam01/update-certificates.sh"
echo ""
echo "vlxsam02:"  
echo "  cat docs/deployment/vlxsam02/apply-collector-improvements.sh"
echo ""
echo "vlxsam03:"
echo "  cat docs/deployment/vlxsam03/optimize-database.sh"
echo ""
echo "vlxsam04:"
echo "  cat docs/deployment/vlxsam04/test-collector-improvements.sh"

# ============================================================================
# RESOLUÇÃO DE PROBLEMAS
# ============================================================================

echo ""
echo "🔧 RESOLUÇÃO DE PROBLEMAS:"
echo "========================="
echo ""
echo "❌ Se interface não carrega collectors:"
echo "   • Verificar logs: journalctl -u samureye-app -f"
echo "   • Testar API: curl http://localhost:5000/api/collectors"
echo ""
echo "❌ Se collector não aparece online:"
echo "   • Verificar heartbeat: journalctl -u samureye-collector -f"
echo "   • Testar conectividade: curl https://app.samureye.com.br/api/system/settings"
echo ""
echo "❌ Se telemetria não aparece:"
echo "   • Verificar banco: SELECT * FROM collector_telemetry;"
echo "   • Verificar última telemetria: SELECT * FROM collectors;"

# ============================================================================
# RESUMO FINAL
# ============================================================================

echo ""
log "📋 RESUMO FINAL"
echo "══════════════════════════════════════════════════"
echo ""
echo "🎯 IMPLEMENTAÇÃO:"
echo "   1. vlxsam01: SSL e NGINX otimizado"
echo "   2. vlxsam03: Banco otimizado"  
echo "   3. vlxsam02: Código atualizado"
echo "   4. vlxsam04: Testes e validação"
echo ""
echo "✅ FUNCIONALIDADES:"
echo "   • Detecção offline automática"
echo "   • Telemetria real em tempo real"
echo "   • Update Packages funcional"
echo "   • Deploy command copy-paste"
echo ""
echo "🌐 RESULTADO:"
echo "   • Interface completa e funcional"
echo "   • Collector vlxsam04 com dados reais"
echo "   • Sistema pronto para novos collectors"

echo ""
read -p "Pressione Enter para continuar com a implementação..."

exit 0