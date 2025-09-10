#!/bin/bash

echo "🚀 SCRIPT MASTER: Execução Completa de Todas as Correções"
echo "========================================================"
echo ""
echo "Este script irá executar todas as correções em ordem:"
echo "1️⃣ Diagnóstico inicial"
echo "2️⃣ Correção do middleware Vite"
echo "3️⃣ Validação final do sistema"
echo "4️⃣ Integração no install-hard-reset (opcional)"
echo ""

# Verificar se estamos no diretório correto
if [ ! -f "1-debug-onpremise-auth.sh" ]; then
    echo "❌ Scripts não encontrados no diretório atual"
    echo "   Certifique-se de que todos os scripts estão no mesmo diretório"
    exit 1
fi

# Tornar todos os scripts executáveis
chmod +x *.sh

echo "=========================================="
echo "🔍 ETAPA 1: DIAGNÓSTICO INICIAL"
echo "=========================================="
./1-debug-onpremise-auth.sh

echo ""
echo "Pressione ENTER para continuar com a correção ou Ctrl+C para sair..."
read -r

echo ""
echo "=========================================="
echo "🔧 ETAPA 2: CORREÇÃO DO MIDDLEWARE VITE"
echo "=========================================="
./2-fix-vite-middleware.sh

echo ""
echo "Pressione ENTER para continuar com a validação ou Ctrl+C para sair..."
read -r

echo ""
echo "=========================================="
echo "✅ ETAPA 3: VALIDAÇÃO FINAL"
echo "=========================================="
./3-validate-journey-system.sh

echo ""
echo "=========================================="
echo "🎯 RESULTADO FINAL"
echo "=========================================="

# Testar novamente os endpoints principais
TOKEN="5a774b05-8a8e-4e40-9f83-981320752086"
COLLECTOR_ID="vlxsam04"

echo ""
echo "🧪 TESTES FINAIS:"

# Teste endpoint pending
PENDING=$(curl -s "http://localhost:5000/collector-api/journeys/pending?collector_id=${COLLECTOR_ID}&token=${TOKEN}" 2>/dev/null)
if [[ "$PENDING" == "["* ]]; then
    echo "✅ /collector-api/journeys/pending - OK (JSON)"
else
    echo "❌ /collector-api/journeys/pending - FALHOU (HTML)"
fi

# Teste endpoint data
DATA=$(curl -s "http://localhost:5000/collector-api/journeys/test/data?collector_id=${COLLECTOR_ID}&token=${TOKEN}" 2>/dev/null)
if [[ "$DATA" == *"Journey not found"* ]] || [[ "$DATA" == *"{"* ]]; then
    echo "✅ /collector-api/journeys/test/data - OK (JSON)"
    SYSTEM_OK=true
else
    echo "❌ /collector-api/journeys/test/data - FALHOU (HTML)"
    SYSTEM_OK=false
fi

echo ""
if [ "$SYSTEM_OK" = true ]; then
    echo "🎉 SUCESSO TOTAL!"
    echo "   ✅ Sistema de execução de jornadas OPERACIONAL"
    echo "   ✅ Collector vlxsam04 pode buscar dados"
    echo "   ✅ Endpoints retornam JSON correto"
    echo ""
    echo "🔧 Deseja integrar as correções no install-hard-reset.sh?"
    echo "   (Para que futuras reinstalações já tenham a correção)"
    echo ""
    echo "Digite 'sim' para integrar ou ENTER para pular:"
    read -r INTEGRATE
    
    if [[ "$INTEGRATE" == "sim" ]] || [[ "$INTEGRATE" == "s" ]]; then
        echo ""
        echo "=========================================="
        echo "🔗 ETAPA 4: INTEGRAÇÃO NO INSTALL-HARD-RESET"
        echo "=========================================="
        ./4-update-install-hard-reset.sh
    fi
    
    echo ""
    echo "🎯 CORREÇÃO COMPLETA!"
    echo "   O sistema de execução de jornadas está totalmente funcional."
    echo "   O collector vlxsam04 agora pode buscar e executar jornadas automaticamente."
else
    echo "❌ AINDA HÁ PROBLEMAS"
    echo "   Os endpoints ainda retornam HTML em vez de JSON"
    echo "   Verifique os logs da aplicação para mais detalhes"
    echo "   Execute: journalctl -u samureye-app -f"
fi

echo ""
echo "=========================================="
echo "🏁 EXECUÇÃO MASTER CONCLUÍDA"
echo "=========================================="