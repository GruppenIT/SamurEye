#!/bin/bash
# Corrigir DATABASE_URL do vlxsam02 com IP correto

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔧 Correção DATABASE_URL vlxsam02"
echo "================================="

# Detectar IP do vlxsam03
log "🔍 Detectando IP do vlxsam03..."

VLXSAM03_IP=""

# Método 1: ping e extrair IP
if ping -c 1 vlxsam03 >/dev/null 2>&1; then
    VLXSAM03_IP=$(ping -c 1 vlxsam03 | grep -oP '(?<=\()\d+\.\d+\.\d+\.\d+(?=\))' | head -1)
    log "📍 IP detectado via ping: $VLXSAM03_IP"
fi

# Método 2: nslookup se ping falhar
if [ -z "$VLXSAM03_IP" ]; then
    VLXSAM03_IP=$(nslookup vlxsam03 2>/dev/null | grep -oP 'Address: \K\d+\.\d+\.\d+\.\d+' | head -1)
    log "📍 IP detectado via nslookup: $VLXSAM03_IP"
fi

# Método 3: usar IP conhecido como fallback
if [ -z "$VLXSAM03_IP" ]; then
    VLXSAM03_IP="172.24.1.153"
    log "📍 Usando IP conhecido: $VLXSAM03_IP"
fi

log "🎯 IP final do vlxsam03: $VLXSAM03_IP"

# Testar conectividade com IP
log "🔌 Testando conectividade com $VLXSAM03_IP:5432..."

if timeout 5 bash -c "</dev/tcp/$VLXSAM03_IP/5432" 2>/dev/null; then
    log "✅ Porta 5432 acessível no IP $VLXSAM03_IP"
else
    log "❌ Porta 5432 não acessível no IP $VLXSAM03_IP"
    exit 1
fi

# Testar credenciais PostgreSQL
log "🔐 Testando credenciais PostgreSQL..."

DATABASE_URLS=(
    "postgresql://samureye:SamurEye2024!@$VLXSAM03_IP:5432/samureye_prod"
    "postgresql://samureye:SamurEye2024!@$VLXSAM03_IP:5432/samureye"
    "postgresql://postgres:SamurEye2024!@$VLXSAM03_IP:5432/samureye_prod"
    "postgresql://postgres:SamurEye2024!@$VLXSAM03_IP:5432/samureye"
)

WORKING_URL=""

for url in "${DATABASE_URLS[@]}"; do
    log "🧪 Testando: $url"
    if echo "SELECT version();" | psql "$url" >/dev/null 2>&1; then
        log "✅ SUCESSO!"
        WORKING_URL="$url"
        break
    else
        log "❌ Falhou"
    fi
done

if [ -z "$WORKING_URL" ]; then
    log "❌ Nenhuma URL funcionou - verificar PostgreSQL no vlxsam03"
    exit 1
fi

log "🎯 URL funcional: $WORKING_URL"

# Encontrar diretório da aplicação
APP_DIR="/opt/samureye/SamurEye"

if [ ! -d "$APP_DIR" ]; then
    log "🔍 Procurando diretório da aplicação..."
    
    # Usar PID do processo para encontrar diretório
    PID=$(systemctl show samureye-app --property=MainPID --no-pager | cut -d'=' -f2)
    if [ "$PID" != "0" ] && [ -n "$PID" ]; then
        APP_DIR=$(readlink -f "/proc/$PID/cwd" 2>/dev/null || echo "")
        log "📁 Diretório detectado via PID: $APP_DIR"
    fi
fi

if [ ! -d "$APP_DIR" ]; then
    log "❌ Diretório da aplicação não encontrado"
    exit 1
fi

cd "$APP_DIR"
log "📁 Trabalhando em: $APP_DIR"

# Backup do .env atual
if [ -f ".env" ]; then
    cp .env .env.backup.$(date +%H%M%S)
    log "💾 Backup criado: .env.backup.$(date +%H%M%S)"
fi

# Atualizar .env com URL correta
log "📝 Atualizando DATABASE_URL no .env..."

# Remover DATABASE_URL existente e adicionar novo
grep -v "^DATABASE_URL=" .env > .env.tmp 2>/dev/null || touch .env.tmp
echo "DATABASE_URL=$WORKING_URL" >> .env.tmp
mv .env.tmp .env

log "✅ DATABASE_URL atualizada no .env"

# Verificar o novo .env
log "📋 Nova configuração .env:"
grep "DATABASE_URL" .env | sed 's/=.*/=***/'

# Sincronizar schema do banco
log "🗃️ Sincronizando schema do banco..."

if command -v npm >/dev/null 2>&1 && [ -f "package.json" ]; then
    # Verificar se tem script db:push
    if grep -q '"db:push"' package.json; then
        log "🔄 Executando npm run db:push..."
        
        # Tentar db:push normal primeiro
        if npm run db:push >/dev/null 2>&1; then
            log "✅ Schema sincronizado com sucesso"
        else
            log "⚠️ db:push normal falhou, tentando --force..."
            if npm run db:push -- --force >/dev/null 2>&1; then
                log "✅ Schema sincronizado com --force"
            else
                log "❌ Falha na sincronização do schema"
            fi
        fi
    else
        log "⚠️ Script db:push não encontrado no package.json"
    fi
else
    log "⚠️ npm ou package.json não encontrado"
fi

# Reiniciar aplicação
log "🔄 Reiniciando aplicação SamurEye..."

systemctl stop samureye-app
sleep 3
systemctl start samureye-app
sleep 5

if systemctl is-active --quiet samureye-app; then
    log "✅ Aplicação reiniciada com sucesso"
else
    log "❌ Falha ao reiniciar aplicação"
    systemctl status samureye-app --no-pager -l
    exit 1
fi

# Verificar se app está respondendo
log "🌐 Testando aplicação..."

sleep 10

# Testar endpoint local
if curl -s http://localhost:5000/api/admin/me >/dev/null 2>&1; then
    log "✅ Aplicação respondendo localmente"
else
    log "⚠️ Aplicação pode ainda estar inicializando"
fi

# Verificar logs recentes
log "📝 Logs recentes da aplicação:"
journalctl -u samureye-app --since "30 seconds ago" | tail -5

echo ""
log "✅ Correção DATABASE_URL finalizada!"
echo ""
echo "📋 RESUMO:"
echo "   • IP vlxsam03: $VLXSAM03_IP"
echo "   • DATABASE_URL: $WORKING_URL"
echo "   • Schema sincronizado"
echo "   • Aplicação reiniciada"
echo ""
echo "🔗 Testar interface:"
echo "   https://app.samureye.com.br/admin/collectors"
echo ""
echo "📝 Monitorar logs:"
echo "   journalctl -u samureye-app -f"

exit 0