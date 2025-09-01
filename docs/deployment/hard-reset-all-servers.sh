#!/bin/bash

# ============================================================================
# SAMUREYE ON-PREMISE - HARD RESET ALL SERVERS
# ============================================================================
# Script master para reset completo de todo o ambiente on-premise
# Executa reset individual em cada servidor na ordem correta
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

# Configurações dos servidores
SERVERS=(
    "vlxsam03:192.168.100.153:Database Server"
    "vlxsam02:192.168.100.152:Application Server"  
    "vlxsam01:192.168.100.151:Gateway"
    "vlxsam04:192.168.100.154:Collector Agent"
)

echo ""
echo "🔥 SAMUREYE HARD RESET - ALL SERVERS"
echo "==================================="
echo "⚠️  ATENÇÃO: Este script irá fazer HARD RESET de todo o ambiente:"
echo ""
for server_info in "${SERVERS[@]}"; do
    IFS=':' read -r name ip description <<< "$server_info"
    echo "   • $name ($ip) - $description"
done
echo ""
echo "⚠️  ORDEM DE EXECUÇÃO:"
echo "   1. vlxsam03 (Database) - Base de dados"
echo "   2. vlxsam02 (Application) - Aplicação SamurEye"
echo "   3. vlxsam01 (Gateway) - Proxy SSL"
echo "   4. vlxsam04 (Collector) - Agente coletor"
echo ""

# ============================================================================
# CONFIRMAÇÃO GLOBAL
# ============================================================================

read -p "🚨 CONTINUAR COM RESET COMPLETO? (digite 'RESET-COMPLETO' para continuar): " confirm
if [ "$confirm" != "RESET-COMPLETO" ]; then
    error "Reset cancelado pelo usuário"
fi

echo ""
log "🗑️ Iniciando hard reset completo do ambiente SamurEye..."

# ============================================================================
# FUNÇÃO PARA EXECUTAR RESET EM SERVIDOR
# ============================================================================

execute_server_reset() {
    local server_name="$1"
    local server_ip="$2"
    local description="$3"
    
    echo ""
    log "🔄 Executando reset em $server_name ($server_ip) - $description"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # URL do script de reset específico
    local script_url="https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/$server_name/install-hard-reset.sh"
    
    echo "📥 Baixando script de reset para $server_name..."
    if curl -fsSL "$script_url" -o "/tmp/$server_name-reset.sh"; then
        chmod +x "/tmp/$server_name-reset.sh"
        log "✅ Script baixado com sucesso"
        
        echo ""
        info "🚀 Executando reset em $server_name..."
        info "💡 Acesse o servidor e execute:"
        echo ""
        echo "    ssh root@$server_ip"
        echo "    curl -fsSL $script_url | bash"
        echo ""
        echo "    OU execute localmente:"
        echo "    bash /tmp/$server_name-reset.sh"
        echo ""
        
        read -p "Pressione ENTER após concluir o reset do $server_name..." dummy
        log "✅ Reset do $server_name marcado como concluído"
    else
        error "❌ Falha ao baixar script para $server_name"
    fi
}

# ============================================================================
# EXECUÇÃO DO RESET EM CADA SERVIDOR
# ============================================================================

log "🎯 Iniciando sequência de reset dos servidores..."

for server_info in "${SERVERS[@]}"; do
    IFS=':' read -r name ip description <<< "$server_info"
    execute_server_reset "$name" "$ip" "$description"
done

# ============================================================================
# TESTES FINAIS
# ============================================================================

echo ""
log "🧪 Executando testes de conectividade final..."

for server_info in "${SERVERS[@]}"; do
    IFS=':' read -r name ip description <<< "$server_info"
    
    echo -n "   • $name ($ip): "
    if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Online${NC}"
    else
        echo -e "${RED}❌ Offline${NC}"
    fi
done

# ============================================================================
# INFORMAÇÕES FINAIS
# ============================================================================

echo ""
log "🎉 HARD RESET COMPLETO DO AMBIENTE FINALIZADO!"
echo ""
echo "📋 RESUMO DO AMBIENTE APÓS RESET:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🗃️ vlxsam03 (192.168.100.153) - Database Server:"
echo "   • PostgreSQL 16 limpo e reconfigurado"
echo "   • Redis, MinIO, Grafana reinstalados"
echo "   • Banco 'samureye' criado do zero"
echo "   • Teste: /usr/local/bin/test-samureye-db.sh"
echo ""
echo "🚀 vlxsam02 (192.168.100.152) - Application Server:"
echo "   • Node.js 20 e aplicação SamurEye reinstalados"
echo "   • Banco de dados limpo"
echo "   • Serviço samureye-app configurado"
echo "   • URL: http://192.168.100.152:5000"
echo ""
echo "🌐 vlxsam01 (192.168.100.151) - Gateway:"
echo "   • NGINX e step-ca reinstalados"
echo "   • Certificados SSL preservados se válidos"
echo "   • Proxy configurado para vlxsam02:5000"
echo "   • URLs: https://app.samureye.com.br"
echo ""
echo "🤖 vlxsam04 (192.168.100.154) - Collector Agent:"
echo "   • Python 3.11 e ferramentas de segurança"
echo "   • Agente coletor configurado"
echo "   • Tools: Nmap, Nuclei, Masscan, Gobuster"
echo "   • Registro: $COLLECTOR_DIR/scripts/register.sh"
echo ""
echo "🔧 PRÓXIMOS PASSOS APÓS RESET:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. 🗃️  TESTAR DATABASE (vlxsam03):"
echo "   ssh root@192.168.100.153"
echo "   /usr/local/bin/test-samureye-db.sh"
echo ""
echo "2. 🚀 VERIFICAR APPLICATION (vlxsam02):"
echo "   ssh root@192.168.100.152"
echo "   systemctl status samureye-app"
echo "   curl http://localhost:5000/api/health"
echo ""
echo "3. 🌐 CONFIGURAR SSL (vlxsam01) - SE NECESSÁRIO:"
echo "   ssh root@192.168.100.151"
echo "   certbot --nginx -d samureye.com.br -d *.samureye.com.br"
echo ""
echo "4. 🤖 REGISTRAR COLLECTOR (vlxsam04):"
echo "   ssh root@192.168.100.154"
echo "   /opt/samureye/collector/scripts/register.sh"
echo ""
echo "5. 👤 CRIAR DADOS INICIAIS:"
echo "   • Acesse: https://app.samureye.com.br/admin"
echo "   • Login: admin@samureye.local / SamurEye2024!"
echo "   • Crie tenant, usuários e collectors"
echo ""
echo "📁 DOCUMENTAÇÃO ATUALIZADA:"
echo "   • docs/deployment/README.md"
echo "   • docs/deployment/NETWORK-ARCHITECTURE.md"
echo "   • docs/deployment/vlxsam*/README.md"
echo ""

exit 0