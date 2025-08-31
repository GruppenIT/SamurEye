#!/bin/bash
# Script para encontrar instalação do SamurEye no vlxsam02

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔍 Localizando SamurEye App no vlxsam02"
echo "====================================="

log "📂 Verificando diretórios comuns..."

# Diretórios possíveis
DIRS_TO_CHECK=(
    "/opt/samureye"
    "/opt/SamurEye" 
    "/home/samureye"
    "/opt/samureye-app"
    "/var/www/samureye"
    "/root/samureye"
    "/root/SamurEye"
)

FOUND_APPS=()

for dir in "${DIRS_TO_CHECK[@]}"; do
    if [ -d "$dir" ] && [ -f "$dir/package.json" ]; then
        log "✅ Encontrado: $dir"
        FOUND_APPS+=("$dir")
        
        # Mostrar informações básicas
        echo "   - package.json: $(jq -r '.name // "N/A"' "$dir/package.json" 2>/dev/null)"
        echo "   - Arquivos: $(ls -la "$dir" | wc -l) itens"
    fi
done

log "🔍 Verificando via systemd..."

if systemctl is-active --quiet samureye-app; then
    log "✅ Serviço samureye-app está rodando"
    
    # Obter informações do serviço
    SERVICE_FILE="/etc/systemd/system/samureye-app.service"
    if [ -f "$SERVICE_FILE" ]; then
        log "📄 Analisando $SERVICE_FILE:"
        
        WORKING_DIR=$(grep "WorkingDirectory" "$SERVICE_FILE" | cut -d= -f2 2>/dev/null || echo "")
        EXEC_START=$(grep "ExecStart" "$SERVICE_FILE" | cut -d= -f2- 2>/dev/null || echo "")
        
        if [ -n "$WORKING_DIR" ]; then
            echo "   WorkingDirectory: $WORKING_DIR"
            if [ -d "$WORKING_DIR" ] && [ -f "$WORKING_DIR/package.json" ]; then
                FOUND_APPS+=("$WORKING_DIR")
                log "✅ Aplicação encontrada via systemd: $WORKING_DIR"
            fi
        fi
        
        if [ -n "$EXEC_START" ]; then
            echo "   ExecStart: $EXEC_START"
        fi
    fi
    
    # Verificar processo rodando
    PID=$(systemctl show samureye-app -p MainPID --value)
    if [ -n "$PID" ] && [ "$PID" != "0" ]; then
        PROC_DIR=$(readlink -f "/proc/$PID/cwd" 2>/dev/null || echo "")
        if [ -n "$PROC_DIR" ] && [ -f "$PROC_DIR/package.json" ]; then
            log "✅ Diretório do processo: $PROC_DIR"
            FOUND_APPS+=("$PROC_DIR")
        fi
    fi
else
    log "⚠️ Serviço samureye-app não está rodando"
fi

log "🔍 Procurando por arquivos package.json com 'samureye'..."

# Busca mais ampla
find /opt /home /var /root -name "package.json" -type f 2>/dev/null | while read -r file; do
    if grep -q -i "samureye" "$file" 2>/dev/null; then
        dir=$(dirname "$file")
        echo "   Encontrado: $dir"
    fi
done

echo ""
echo "📊 RESUMO:"
echo "=========="

if [ ${#FOUND_APPS[@]} -eq 0 ]; then
    log "❌ Nenhuma instalação do SamurEye encontrada"
    echo ""
    echo "💡 Sugestões:"
    echo "   1. Verificar se a aplicação foi instalada corretamente"
    echo "   2. Executar o script de instalação vlxsam02/install.sh"
    echo "   3. Verificar logs: journalctl -u samureye-app"
else
    log "✅ Instalações encontradas:"
    for app in "${FOUND_APPS[@]}"; do
        echo "   📂 $app"
    done
    
    # Usar o primeiro encontrado como principal
    MAIN_APP="${FOUND_APPS[0]}"
    log "🎯 Usando como principal: $MAIN_APP"
    
    echo ""
    echo "🔧 Para sincronizar schema:"
    echo "   cd $MAIN_APP"
    echo "   export DATABASE_URL=\"postgresql://samureye:SamurEye2024%21@vlxsam03:5432/samureye\""
    echo "   npm run db:push --force"
fi

exit 0