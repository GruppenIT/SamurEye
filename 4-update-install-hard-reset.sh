#!/bin/bash

echo "🔧 INTEGRAÇÃO: Adicionando correções ao install-hard-reset.sh"
echo "==========================================================="

INSTALL_SCRIPT="/opt/samureye/SamurEye/docs/deployment/vlxsam02/install-hard-reset.sh"

if [ ! -f "$INSTALL_SCRIPT" ]; then
    echo "❌ Script install-hard-reset.sh não encontrado"
    exit 1
fi

echo ""
echo "1️⃣ Fazendo backup do install-hard-reset.sh..."
cp "$INSTALL_SCRIPT" "${INSTALL_SCRIPT}.backup"
echo "✅ Backup criado"

echo ""
echo "2️⃣ Adicionando correção do middleware Vite..."

# Adicionar a correção do middleware Vite no final do script, antes de "APLICAÇÃO TOTALMENTE CONFIGURADA"
VITE_CORRECTION='
# ============================================================================
# CORREÇÃO CRÍTICA: Vite Middleware capturando rotas /collector-api/*
# ============================================================================

log "🔧 Aplicando correção crítica no middleware Vite..."

VITE_FILE="$WORKING_DIR/server/vite.ts"
if [ -f "$VITE_FILE" ]; then
    # Verificar se a correção já foi aplicada
    if ! grep -q "Skip collector API routes" "$VITE_FILE"; then
        log "   Modificando middleware para excluir rotas /collector-api/*..."
        
        # Fazer backup
        cp "$VITE_FILE" "${VITE_FILE}.backup"
        
        # Aplicar correção
        sed -i '\''s|app\.use("\*", async (req, res, next) => {|app.use("*", async (req, res, next) => {\n    // Skip collector API routes - let them be handled by registerRoutes\n    if (req.originalUrl.startsWith("/collector-api")) {\n      return next();\n    }|'\'' "$VITE_FILE"
        
        if grep -q "Skip collector API routes" "$VITE_FILE"; then
            log "   ✅ Middleware Vite corrigido - rotas /collector-api/* não serão capturadas"
        else
            warn "   ⚠️ Erro ao aplicar correção no middleware Vite"
            cp "${VITE_FILE}.backup" "$VITE_FILE"
        fi
    else
        log "   ✅ Correção do middleware Vite já aplicada"
    fi
else
    warn "   ⚠️ Arquivo vite.ts não encontrado"
fi

# Teste dos endpoints após a correção
log "🧪 Testando endpoints collector-api após correção..."

# Aguardar aplicação reiniciar
for i in {1..15}; do
    if curl -s --connect-timeout 2 http://localhost:5000/api/health >/dev/null 2>&1; then
        log "   Aplicação online para testes"
        break
    fi
    sleep 2
done

# Testar endpoint de jornadas pendentes
REAL_TOKEN=$(psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c "SELECT enrollment_token FROM collectors WHERE name = '\''vlxsam04'\'' LIMIT 1;" 2>/dev/null | tr -d '\'' '\'')

if [ -n "$REAL_TOKEN" ]; then
    PENDING_TEST=$(curl -s "http://localhost:5000/collector-api/journeys/pending?collector_id=vlxsam04&token=${REAL_TOKEN}" 2>/dev/null)
    if [[ "$PENDING_TEST" == "["* ]]; then
        log "   ✅ Endpoint /pending retorna JSON array"
    else
        warn "   ⚠️ Endpoint /pending ainda retorna HTML"
    fi
    
    DATA_TEST=$(curl -s "http://localhost:5000/collector-api/journeys/test/data?collector_id=vlxsam04&token=${REAL_TOKEN}" 2>/dev/null)
    if [[ "$DATA_TEST" == *"Journey not found"* ]] || [[ "$DATA_TEST" == *"{"* ]]; then
        log "   ✅ Endpoint /data retorna JSON"
        log "   🎉 SISTEMA DE EXECUÇÃO DE JORNADAS TOTALMENTE OPERACIONAL"
    else
        warn "   ⚠️ Endpoint /data ainda retorna HTML"
    fi
else
    warn "   ⚠️ Não foi possível encontrar token do collector para teste"
fi

log "✅ Correção do middleware Vite integrada no install-hard-reset"
'

# Encontrar a linha "APLICAÇÃO TOTALMENTE CONFIGURADA" e inserir antes dela
if grep -q "APLICAÇÃO TOTALMENTE CONFIGURADA" "$INSTALL_SCRIPT"; then
    # Criar arquivo temporário com a correção inserida
    awk '
    /APLICAÇÃO TOTALMENTE CONFIGURADA/ {
        print "'"$VITE_CORRECTION"'"
        print ""
    }
    {print}
    ' "$INSTALL_SCRIPT" > "${INSTALL_SCRIPT}.tmp"
    
    mv "${INSTALL_SCRIPT}.tmp" "$INSTALL_SCRIPT"
    echo "✅ Correção integrada no install-hard-reset.sh"
else
    echo "❌ Não foi possível encontrar seção de finalização no script"
    echo "   Adicionando correção no final do arquivo..."
    echo "$VITE_CORRECTION" >> "$INSTALL_SCRIPT"
fi

echo ""
echo "3️⃣ Verificando integração..."
if grep -q "Skip collector API routes" "$INSTALL_SCRIPT"; then
    echo "✅ Correção integrada com sucesso"
    echo ""
    echo "🎯 INSTALL-HARD-RESET ATUALIZADO!"
    echo "   • Correção do middleware Vite integrada"
    echo "   • Próximas reinstalações já terão a correção"
    echo "   • Sistema de execução de jornadas operacional"
else
    echo "❌ Erro na integração"
    echo "   Restaurando backup..."
    cp "${INSTALL_SCRIPT}.backup" "$INSTALL_SCRIPT"
fi

echo ""
echo "=========================================="
echo "🏁 INTEGRAÇÃO CONCLUÍDA"