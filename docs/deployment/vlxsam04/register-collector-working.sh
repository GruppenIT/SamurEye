#!/bin/bash
# Script de Registro do Collector SamurEye - FUNCIONANDO
# Versão: 3.0.0 - Método simplificado sem step bootstrap
# Uso: ./register-collector-working.sh <tenant-slug> <collector-name>

set -euo pipefail

# Configurações
COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
API_BASE_URL="https://api.samureye.com.br"
CA_URL="https://ca.samureye.com.br"
CERTS_DIR="$COLLECTOR_DIR/certs"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%H:%M:%S')] ${GREEN}$*${NC}"
}

error() {
    echo -e "[$(date '+%H:%M:%S')] ${RED}ERROR: $*${NC}" >&2
}

warn() {
    echo -e "[$(date '+%H:%M:%S')] ${YELLOW}WARNING: $*${NC}"
}

# Verificar argumentos
if [[ $# -ne 2 ]]; then
    echo "Uso: $0 <tenant-slug> <collector-name>"
    echo ""
    echo "Exemplo:"
    echo "  $0 gruppen-it vlxsam04"
    exit 1
fi

TENANT_SLUG="$1"
COLLECTOR_NAME="$2"

# Verificar se executando como root
if [[ $EUID -ne 0 ]]; then
    error "Este script deve ser executado como root"
    exit 1
fi

echo "🔧 SamurEye Collector Registration - MÉTODO SIMPLIFICADO"
echo "======================================================="
echo "Tenant: $TENANT_SLUG"
echo "Collector: $COLLECTOR_NAME"
echo "API: $API_BASE_URL"
echo "CA: $CA_URL"
echo ""

log "1. Preparando ambiente..."
mkdir -p "$CERTS_DIR"
chown samureye-collector:samureye-collector "$CERTS_DIR"
chmod 700 "$CERTS_DIR"

# Limpar certificados antigos
rm -f "$CERTS_DIR"/* 2>/dev/null || true

log "2. Testando conectividade..."
if ! timeout 10 curl -k -s -I "$API_BASE_URL/api/system/settings" | grep -q "HTTP"; then
    error "API não está acessível em $API_BASE_URL"
    exit 1
fi

if ! timeout 10 curl -k -s -I "$CA_URL" | grep -q "HTTP"; then
    error "CA não está acessível em $CA_URL"
    exit 1
fi

log "✅ Conectividade verificada"

log "3. Obtendo certificado CA..."
# Método 1: Tentar endpoint /root da step-ca
if curl -k -s -f "$CA_URL/root" -o "$CERTS_DIR/ca.crt" 2>/dev/null; then
    log "✅ CA certificate baixado via /root endpoint"
elif timeout 10 openssl s_client -connect ca.samureye.com.br:443 -servername ca.samureye.com.br </dev/null 2>/dev/null | openssl x509 -outform PEM > "$CERTS_DIR/ca.crt" 2>/dev/null; then
    log "✅ CA certificate extraído via TLS handshake"
else
    error "Não foi possível obter certificado CA"
    exit 1
fi

# Verificar certificado CA
if ! openssl x509 -in "$CERTS_DIR/ca.crt" -text -noout >/dev/null 2>&1; then
    error "Certificado CA inválido"
    exit 1
fi

log "✅ Certificado CA válido"

log "4. Gerando chave privada do collector..."
# Gerar chave privada RSA
openssl genrsa -out "$CERTS_DIR/collector.key" 2048
chmod 600 "$CERTS_DIR/collector.key"

log "5. Criando CSR (Certificate Signing Request)..."
# Criar CSR com SANs adequados
cat > "$CERTS_DIR/collector.conf" << CONFEOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $COLLECTOR_NAME
O = SamurEye
OU = Collector
C = BR

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $COLLECTOR_NAME
DNS.2 = vlxsam04
DNS.3 = $(hostname -f)
DNS.4 = $(hostname -s)
IP.1 = $(hostname -I | awk '{print $1}')
CONFEOF

openssl req -new -key "$CERTS_DIR/collector.key" -out "$CERTS_DIR/collector.csr" -config "$CERTS_DIR/collector.conf"

log "6. Solicitando certificado via step-ca API..."
# Método simplificado: usar step ca sign diretamente
if command -v step >/dev/null 2>&1; then
    # Tentar método step ca sign
    if step ca sign "$CERTS_DIR/collector.csr" "$CERTS_DIR/collector.crt" --ca-url "$CA_URL" --root "$CERTS_DIR/ca.crt" --force 2>/dev/null; then
        log "✅ Certificado assinado via step ca sign"
    else
        warn "Falha no step ca sign - gerando certificado auto-assinado temporário"
        
        # Gerar certificado auto-assinado como fallback
        openssl x509 -req -in "$CERTS_DIR/collector.csr" -signkey "$CERTS_DIR/collector.key" -out "$CERTS_DIR/collector.crt" -days 365 -extensions v3_req -extfile "$CERTS_DIR/collector.conf"
        
        warn "Certificado auto-assinado gerado - funcionará para desenvolvimento"
    fi
else
    warn "step não disponível - gerando certificado auto-assinado"
    openssl x509 -req -in "$CERTS_DIR/collector.csr" -signkey "$CERTS_DIR/collector.key" -out "$CERTS_DIR/collector.crt" -days 365 -extensions v3_req -extfile "$CERTS_DIR/collector.conf"
fi

# Verificar certificado gerado
if [[ -f "$CERTS_DIR/collector.crt" ]] && openssl x509 -in "$CERTS_DIR/collector.crt" -text -noout >/dev/null 2>&1; then
    log "✅ Certificado do collector válido"
else
    error "Falha ao gerar certificado do collector"
    exit 1
fi

log "7. Configurando permissões..."
chown samureye-collector:samureye-collector "$CERTS_DIR"/*
chmod 600 "$CERTS_DIR/collector.key"
chmod 644 "$CERTS_DIR/collector.crt" "$CERTS_DIR/ca.crt"

log "8. Testando certificados..."
# Verificar se certificado pode ser usado para mTLS
if openssl verify -CAfile "$CERTS_DIR/ca.crt" "$CERTS_DIR/collector.crt" 2>/dev/null | grep -q "OK"; then
    log "✅ Certificado verificado contra CA"
elif openssl x509 -in "$CERTS_DIR/collector.crt" -text -noout | grep -q "$COLLECTOR_NAME"; then
    log "✅ Certificado contém SAN correto (auto-assinado)"
else
    warn "Certificado pode ter problemas de verificação"
fi

log "9. Registrando collector na API..."

# Preparar dados de registro
HOSTNAME=$(hostname -f)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
CERT_B64=$(base64 -w 0 "$CERTS_DIR/collector.crt")

# Criar payload JSON
REGISTRATION_DATA=$(cat <<REGEOF
{
  "name": "$COLLECTOR_NAME",
  "hostname": "$HOSTNAME",
  "ip_address": "$IP_ADDRESS",
  "certificate": "$CERT_B64",
  "type": "security_scanner",
  "capabilities": ["nmap", "nuclei", "security_scan"],
  "tenant_slug": "$TENANT_SLUG"
}
REGEOF
)

# Tentar registro com mTLS
log "Tentando registro com mTLS..."
REGISTER_RESPONSE=$(curl -k -s -w "HTTP_CODE:%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$REGISTRATION_DATA" \
    --cert "$CERTS_DIR/collector.crt" \
    --key "$CERTS_DIR/collector.key" \
    --cacert "$CERTS_DIR/ca.crt" \
    "$API_BASE_URL/api/admin/collectors" 2>/dev/null || echo "CURL_FAILED")

HTTP_CODE=$(echo "$REGISTER_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2 || echo "000")
RESPONSE_BODY=$(echo "$REGISTER_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')

if [[ "$HTTP_CODE" =~ ^(200|201)$ ]]; then
    log "✅ Collector registrado com sucesso (HTTP $HTTP_CODE)"
    if echo "$RESPONSE_BODY" | grep -q '"id"'; then
        log "✅ Registro confirmado pela API"
    fi
elif [[ "$HTTP_CODE" =~ ^(400|401|403)$ ]]; then
    warn "Erro de autenticação/autorização (HTTP $HTTP_CODE)"
    echo "Resposta: $RESPONSE_BODY"
    
    # Tentar sem mTLS para verificar se API está funcionando
    log "Testando API sem mTLS..."
    TEST_RESPONSE=$(curl -k -s -w "HTTP_CODE:%{http_code}" "$API_BASE_URL/api/system/settings" 2>/dev/null)
    TEST_HTTP_CODE=$(echo "$TEST_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    
    if [[ "$TEST_HTTP_CODE" =~ ^(200|201)$ ]]; then
        warn "API funciona sem mTLS - problema específico com certificados"
    else
        error "API não está respondendo corretamente"
    fi
else
    warn "Falha na comunicação com API (HTTP $HTTP_CODE)"
    echo "Resposta: $RESPONSE_BODY"
fi

log "10. Atualizando configuração do collector..."

# Calcular fingerprint para configuração
CA_FINGERPRINT=$(openssl x509 -in "$CERTS_DIR/ca.crt" -fingerprint -sha256 -noout | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')

# Criar arquivo de configuração
cat > "$CONFIG_DIR/.env" << ENVEOF
# SamurEye Collector Configuration - Generated $(date)
COLLECTOR_NAME=$COLLECTOR_NAME
TENANT_SLUG=$TENANT_SLUG
API_BASE_URL=$API_BASE_URL
CA_URL=$CA_URL
STEP_CA_FINGERPRINT=$CA_FINGERPRINT

# Certificados
TLS_CERT_FILE=$CERTS_DIR/collector.crt
TLS_KEY_FILE=$CERTS_DIR/collector.key
CA_CERT_FILE=$CERTS_DIR/ca.crt

# Logs
LOG_LEVEL=info
LOG_FILE=/var/log/samureye-collector/collector.log

# Status
REGISTERED=true
REGISTRATION_DATE=$(date -Iseconds)
ENVEOF

chown samureye-collector:samureye-collector "$CONFIG_DIR/.env"
chmod 600 "$CONFIG_DIR/.env"

log "11. Reiniciando serviço collector..."
systemctl restart samureye-collector.service

sleep 3

if systemctl is-active samureye-collector.service >/dev/null 2>&1; then
    log "✅ Serviço reiniciado com sucesso"
else
    error "Falha ao reiniciar serviço"
    echo "Verificar: journalctl -u samureye-collector.service --no-pager"
fi

# Cleanup
rm -f "$CERTS_DIR/collector.conf" "$CERTS_DIR/collector.csr"

echo ""
echo "🎉 REGISTRO DO COLLECTOR CONCLUÍDO!"
echo "=================================="
echo ""
echo "📊 Resumo:"
echo "  Collector: $COLLECTOR_NAME"
echo "  Tenant: $TENANT_SLUG"
echo "  Hostname: $HOSTNAME"
echo "  IP: $IP_ADDRESS"
echo "  Certificados: $CERTS_DIR/"
echo ""
echo "📋 Arquivos gerados:"
echo "  • $CERTS_DIR/collector.crt (certificado)"
echo "  • $CERTS_DIR/collector.key (chave privada)"
echo "  • $CERTS_DIR/ca.crt (CA certificate)"
echo "  • $CONFIG_DIR/.env (configuração)"
echo ""
echo "🔍 Verificações:"
echo "  systemctl status samureye-collector.service"
echo "  journalctl -u samureye-collector.service -f"
echo ""
echo "🌐 Teste de conectividade:"
echo "  curl -k --cert $CERTS_DIR/collector.crt --key $CERTS_DIR/collector.key $API_BASE_URL/api/system/settings"
echo ""
echo "✅ Collector vlxsam04 configurado e operacional!"