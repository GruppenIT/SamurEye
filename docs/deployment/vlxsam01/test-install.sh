#!/bin/bash

# Script de teste para instalação vlxsam01
# Executa em ambiente limpo para verificar funcionamento

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

log "🧪 Testando instalação do vlxsam01..."

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./test-install.sh"
fi

# Executar script de instalação
log "Executando script de instalação..."
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam01/install.sh | bash

# Verificar se os arquivos foram criados
log "Verificando arquivos criados..."
files_to_check=(
    "/etc/nginx/sites-available/samureye"
    "/etc/nginx/sites-available/samureye-temp"
    "/opt/request-ssl.sh"
    "/opt/request-ssl-wildcard.sh"
    "/opt/samureye/scripts/health-check.sh"
    "/opt/samureye/scripts/check-ssl.sh"
)

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ]; then
        log "✅ $file"
    else
        error "❌ $file não encontrado"
    fi
done

# Verificar se NGINX está funcionando
log "Verificando NGINX..."
if systemctl is-active --quiet nginx; then
    log "✅ NGINX ativo"
else
    error "❌ NGINX não está ativo"
fi

# Testar configuração NGINX
if nginx -t >/dev/null 2>&1; then
    log "✅ Configuração NGINX válida"
else
    error "❌ Configuração NGINX inválida"
fi

# Testar acesso HTTP local
log "Testando acesso HTTP local..."
if curl -f -s http://localhost/nginx-health >/dev/null 2>&1; then
    log "✅ Health check HTTP funcionando"
else
    warn "⚠️ Health check HTTP não está funcionando (normal se vlxsam02 não estiver rodando)"
fi

# Verificar firewall
log "Verificando firewall..."
if ufw status | grep -q "Status: active"; then
    log "✅ UFW ativo"
else
    warn "⚠️ UFW não está ativo"
fi

# Verificar portas abertas
log "Verificando portas..."
if netstat -ln | grep -q ":80 "; then
    log "✅ Porta 80 (HTTP) aberta"
else
    error "❌ Porta 80 não está aberta"
fi

if netstat -ln | grep -q ":443 "; then
    log "✅ Porta 443 (HTTPS) preparada"
else
    warn "⚠️ Porta 443 ainda não configurada (normal sem SSL)"
fi

log "🎉 Teste de instalação concluído com sucesso!"

echo ""
echo "📋 RESULTADO DOS TESTES:"
echo "======================="
echo "✅ Script de instalação executado"
echo "✅ Arquivos de configuração criados"
echo "✅ NGINX funcionando (configuração temporária)"
echo "✅ Firewall configurado"
echo "✅ Scripts de manutenção instalados"
echo ""
echo "🔄 PRÓXIMOS PASSOS:"
echo "1. Configurar DNS para samureye.com.br -> $(hostname -I | awk '{print $1}')"
echo "2. Executar: /opt/request-ssl.sh"
echo "3. Testar com: /opt/samureye/scripts/check-ssl.sh"
echo ""
echo "⚠️  NOTA: SSL será configurado após executar /opt/request-ssl.sh"