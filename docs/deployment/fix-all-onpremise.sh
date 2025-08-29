#!/bin/bash
# Script de correção geral para todo ambiente on-premise SamurEye

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔧 Correção Ambiente On-Premise SamurEye Completo"
echo "================================================"
echo ""

# Detectar qual servidor está sendo executado
HOSTNAME=$(hostname)
log "Servidor detectado: $HOSTNAME"

case $HOSTNAME in
    "vlxsam01")
        log "Executando correções para Gateway/CA..."
        curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/fix-onpremise.sh | bash
        ;;
    "vlxsam02") 
        log "Executando correções para Application Server..."
        curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/fix-onpremise.sh | bash
        ;;
    "vlxsam04")
        log "Executando correções para Collector..."
        curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/fix-onpremise.sh | bash
        ;;
    *)
        echo ""
        log "❌ Servidor não reconhecido: $HOSTNAME"
        echo ""
        echo "Servidores suportados:"
        echo "  vlxsam01 - Gateway/Certificate Authority"  
        echo "  vlxsam02 - Application Server"
        echo "  vlxsam04 - Collector Agent"
        echo ""
        echo "Execute manualmente:"
        echo "  # Para vlxsam01 (Gateway):"
        echo "  curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/fix-onpremise.sh | bash"
        echo ""
        echo "  # Para vlxsam02 (App Server):"
        echo "  curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/fix-onpremise.sh | bash"
        echo ""
        echo "  # Para vlxsam04 (Collector):"
        echo "  curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/fix-onpremise.sh | bash"
        echo ""
        exit 1
        ;;
esac

echo ""
log "✅ Correção específica para $HOSTNAME concluída"
echo ""
echo "🔍 Para verificar todo o ambiente, execute nos outros servidores:"
echo "  curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/fix-all-onpremise.sh | bash"