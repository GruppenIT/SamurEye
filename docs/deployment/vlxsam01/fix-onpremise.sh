#!/bin/bash
# Script de correção para vlxsam01 (Gateway/CA) - SamurEye On-Premise

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

echo "🔧 Correção Gateway vlxsam01 - SamurEye"
echo "======================================"

# 1. Atualizar o script de instalação principal
log "1. Atualizando script de instalação..."
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/install.sh > /tmp/install-vlxsam01.sh
chmod +x /tmp/install-vlxsam01.sh

# 2. Verificar serviços críticos
log "2. Verificando serviços..."

# NGINX
if systemctl is-active nginx >/dev/null 2>&1; then
    log "✅ NGINX ativo"
else
    log "⚠️ NGINX inativo - reiniciando..."
    systemctl restart nginx
fi

# step-ca
if systemctl is-active step-ca >/dev/null 2>&1; then
    log "✅ step-ca ativo"
else
    log "⚠️ step-ca inativo - verificando configuração..."
    if [[ -f /etc/step-ca/config/ca.json ]]; then
        systemctl restart step-ca
    else
        log "❌ Configuração step-ca ausente - executar install.sh"
        exit 1
    fi
fi

# 3. Verificar certificados SSL
log "3. Verificando certificados..."
CERT_FILES=(
    "/etc/ssl/samureye/samureye.crt"
    "/etc/ssl/samureye/samureye.key"
    "/etc/step-ca/certs/root_ca.crt"
)

for cert in "${CERT_FILES[@]}"; do
    if [[ -f "$cert" ]]; then
        log "✅ Certificado presente: $cert"
    else
        log "❌ Certificado ausente: $cert"
        log "  Execute: /tmp/install-vlxsam01.sh"
        exit 1
    fi
done

# 4. Verificar conectividade
log "4. Testando conectividade..."

# Teste interno (step-ca)
if curl -k -s https://localhost:8443/health >/dev/null 2>&1; then
    log "✅ step-ca respondendo"
else
    log "⚠️ step-ca não responde"
fi

# Teste externo (NGINX)
if curl -k -s https://app.samureye.com.br >/dev/null 2>&1; then
    log "✅ NGINX/SSL funcionando"
else
    log "⚠️ NGINX/SSL com problemas"
fi

# 5. Verificar proxy reverso
log "5. Verificando configuração NGINX..."
if nginx -t >/dev/null 2>&1; then
    log "✅ Configuração NGINX válida"
else
    log "❌ Configuração NGINX inválida"
    log "  Verifique: /etc/nginx/sites-available/samureye"
fi

# 6. Status final dos serviços
log "6. Status dos serviços:"
echo "  NGINX: $(systemctl is-active nginx)"
echo "  step-ca: $(systemctl is-active step-ca)"

# 7. URLs funcionais
log "7. URLs do ambiente:"
echo "  App: https://app.samureye.com.br"
echo "  API: https://api.samureye.com.br"
echo "  CA: https://ca.samureye.com.br"

echo ""
log "✅ Verificação do Gateway concluída"
echo ""
echo "🔍 Para executar correção completa:"
echo "  bash /tmp/install-vlxsam01.sh"
echo ""
echo "🔍 Logs importantes:"
echo "  journalctl -u nginx -f"
echo "  journalctl -u step-ca -f"
echo "  tail -f /var/log/nginx/error.log"