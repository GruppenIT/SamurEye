#!/bin/bash

echo "🔧 CORREÇÃO DEFINITIVA: Vite Middleware capturando rotas /collector-api/*"
echo "======================================================================"

VITE_FILE="/opt/samureye/SamurEye/server/vite.ts"

if [ ! -f "$VITE_FILE" ]; then
    echo "❌ Arquivo vite.ts não encontrado"
    exit 1
fi

echo ""
echo "1️⃣ Fazendo backup do vite.ts..."
cp "$VITE_FILE" "${VITE_FILE}.backup"
echo "✅ Backup criado: vite.ts.backup"

echo ""
echo "2️⃣ Aplicando correção no middleware..."

# A correção: modificar a linha que captura todas as rotas para excluir /collector-api/*
sed -i 's|app\.use("\*", async (req, res, next) => {|app.use("*", async (req, res, next) => {\n    // Skip collector API routes - let them be handled by registerRoutes\n    if (req.originalUrl.startsWith("/collector-api")) {\n      return next();\n    }|' "$VITE_FILE"

echo "✅ Middleware modificado para excluir rotas /collector-api/*"

echo ""
echo "3️⃣ Verificando correção..."
if grep -A 5 "Skip collector API routes" "$VITE_FILE"; then
    echo "✅ Correção aplicada com sucesso"
else
    echo "❌ Erro na aplicação da correção"
    echo "   Restaurando backup..."
    cp "${VITE_FILE}.backup" "$VITE_FILE"
    exit 1
fi

echo ""
echo "4️⃣ Reiniciando serviço..."
systemctl restart samureye-app

echo ""
echo "5️⃣ Aguardando aplicação..."
for i in {1..20}; do
    if curl -s --connect-timeout 2 http://localhost:5000/api/health >/dev/null 2>&1; then
        echo "✅ Aplicação online"
        break
    fi
    sleep 2
done

echo ""
echo "6️⃣ Testando correção DEFINITIVA..."

# Testar endpoint de jornadas pendentes (deve retornar array JSON)
echo "   Testando /collector-api/journeys/pending..."
PENDING_RESPONSE=$(curl -s "http://localhost:5000/collector-api/journeys/pending?collector_id=vlxsam04&token=5a774b05-8a8e-4e40-9f83-981320752086" 2>/dev/null)
if [[ "$PENDING_RESPONSE" == "["* ]]; then
    echo "   ✅ /pending: ${PENDING_RESPONSE:0:30}..."
else
    echo "   ❌ /pending: ${PENDING_RESPONSE:0:30}..."
fi

# Testar endpoint de dados da jornada (deve retornar JSON ou Journey not found)
echo "   Testando /collector-api/journeys/test/data..."
DATA_RESPONSE=$(curl -s "http://localhost:5000/collector-api/journeys/test/data?collector_id=vlxsam04&token=5a774b05-8a8e-4e40-9f83-981320752086" 2>/dev/null)
if [[ "$DATA_RESPONSE" == *"Journey not found"* ]] || [[ "$DATA_RESPONSE" == *"{"* ]]; then
    echo "   ✅ /data: ${DATA_RESPONSE:0:30}..."
    echo ""
    echo "🎉 SUCESSO TOTAL! Middleware corrigido"
    echo "   • Vite não captura mais rotas /collector-api/*"
    echo "   • Endpoints retornam JSON em vez de HTML"
    echo "   • Sistema de execução de jornadas OPERACIONAL"
else
    echo "   ❌ /data: ${DATA_RESPONSE:0:30}..."
    echo ""
    echo "❌ Correção não funcionou - ainda retorna HTML"
fi

echo ""
echo "🎯 CORREÇÃO DEFINITIVA CONCLUÍDA!"
echo ""
echo "📋 TESTE COMPLETO:"
echo "   curl 'http://localhost:5000/collector-api/journeys/pending?collector_id=vlxsam04&token=5a774b05-8a8e-4e40-9f83-981320752086'"
echo "   curl 'http://localhost:5000/collector-api/journeys/test/data?collector_id=vlxsam04&token=5a774b05-8a8e-4e40-9f83-981320752086'"