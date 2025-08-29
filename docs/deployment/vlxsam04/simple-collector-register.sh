#!/bin/bash
# Script Simplificado para Registro do Collector vlxsam04
# Método direto sem dependência do step-ca bootstrap

set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2
}

# Verificar argumentos
if [[ $# -ne 2 ]]; then
    echo "Uso: $0 <tenant-slug> <collector-name>"
    echo "Exemplo: $0 gruppen-it vlxsam04"
    exit 1
fi

TENANT_SLUG="$1"
COLLECTOR_NAME="$2"
COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
API_BASE_URL="https://api.samureye.com.br"
CA_URL="https://ca.samureye.com.br"
CERTS_DIR="$COLLECTOR_DIR/certs"

echo "🔧 Registro Simplificado do Collector vlxsam04"
echo "Tenant: $TENANT_SLUG"
echo "Collector: $COLLECTOR_NAME"
echo ""

log "1. Preparando diretórios..."
mkdir -p "$CERTS_DIR"
chown samureye-collector:samureye-collector "$CERTS_DIR" 2>/dev/null || true
chmod 700 "$CERTS_DIR"
rm -f "$CERTS_DIR"/* 2>/dev/null || true

log "2. Testando conectividade..."
if ! curl -k -s -I "$API_BASE_URL/api/system/settings" | grep -q "HTTP"; then
    error "API não acessível"
    exit 1
fi

log "3. Extraindo certificado CA..."
if ! timeout 10 openssl s_client -connect ca.samureye.com.br:443 -servername ca.samureye.com.br </dev/null 2>/dev/null | openssl x509 -outform PEM > "$CERTS_DIR/ca.crt" 2>/dev/null; then
    error "Falha ao extrair certificado CA"
    exit 1
fi

log "4. Gerando chave privada..."
openssl genrsa -out "$CERTS_DIR/collector.key" 2048
chmod 600 "$CERTS_DIR/collector.key"

log "5. Criando CSR..."
cat > "$CERTS_DIR/openssl.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = vlxsam04
O = SamurEye
OU = Collector

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = vlxsam04
IP.1 = 192.168.100.154
EOF

openssl req -new -key "$CERTS_DIR/collector.key" -out "$CERTS_DIR/collector.csr" -config "$CERTS_DIR/openssl.conf"

log "6. Gerando certificado auto-assinado..."
openssl x509 -req -in "$CERTS_DIR/collector.csr" -signkey "$CERTS_DIR/collector.key" -out "$CERTS_DIR/collector.crt" -days 365 -extensions v3_req -extfile "$CERTS_DIR/openssl.conf"

log "7. Configurando permissões..."
chown samureye-collector:samureye-collector "$CERTS_DIR"/* 2>/dev/null || true
chmod 600 "$CERTS_DIR/collector.key"
chmod 644 "$CERTS_DIR/collector.crt" "$CERTS_DIR/ca.crt"

log "8. Registrando na API..."
HOSTNAME=$(hostname -f)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
CERT_B64=$(base64 -w 0 "$CERTS_DIR/collector.crt")

REGISTRATION_DATA=$(cat <<EOF
{
  "name": "$COLLECTOR_NAME",
  "hostname": "$HOSTNAME",
  "ip_address": "$IP_ADDRESS",
  "certificate": "$CERT_B64",
  "type": "security_scanner",
  "capabilities": ["nmap", "nuclei"],
  "tenant_slug": "$TENANT_SLUG"
}
EOF
)

RESPONSE=$(curl -k -s -w "HTTP:%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$REGISTRATION_DATA" \
    --cert "$CERTS_DIR/collector.crt" \
    --key "$CERTS_DIR/collector.key" \
    "$API_BASE_URL/api/admin/collectors" 2>/dev/null || echo "HTTP:000")

HTTP_CODE=$(echo "$RESPONSE" | grep -o "HTTP:[0-9]*" | cut -d: -f2)

if [[ "$HTTP_CODE" =~ ^(200|201)$ ]]; then
    log "✅ Registrado com sucesso (HTTP $HTTP_CODE)"
else
    log "⚠️ Resposta HTTP: $HTTP_CODE"
fi

log "9. Criando configuração..."
CA_FINGERPRINT=$(openssl x509 -in "$CERTS_DIR/ca.crt" -fingerprint -sha256 -noout | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')

cat > "$CONFIG_DIR/.env" << EOF
COLLECTOR_NAME=$COLLECTOR_NAME
TENANT_SLUG=$TENANT_SLUG
API_BASE_URL=$API_BASE_URL
CA_URL=$CA_URL
STEP_CA_FINGERPRINT=$CA_FINGERPRINT
TLS_CERT_FILE=$CERTS_DIR/collector.crt
TLS_KEY_FILE=$CERTS_DIR/collector.key
CA_CERT_FILE=$CERTS_DIR/ca.crt
LOG_LEVEL=info
REGISTERED=true
EOF

chown samureye-collector:samureye-collector "$CONFIG_DIR/.env" 2>/dev/null || true
chmod 600 "$CONFIG_DIR/.env"

log "10. Reiniciando serviço..."
systemctl restart samureye-collector.service 2>/dev/null || true
sleep 2

if systemctl is-active samureye-collector.service >/dev/null 2>&1; then
    log "✅ Serviço ativo"
else
    log "⚠️ Verificar serviço: systemctl status samureye-collector.service"
fi

# Cleanup
rm -f "$CERTS_DIR/openssl.conf" "$CERTS_DIR/collector.csr"

echo ""
echo "✅ REGISTRO CONCLUÍDO!"
echo "Collector: $COLLECTOR_NAME"
echo "Certificados: $CERTS_DIR/"
echo "Configuração: $CONFIG_DIR/.env"
echo ""
echo "Teste: curl -k --cert $CERTS_DIR/collector.crt --key $CERTS_DIR/collector.key $API_BASE_URL/api/system/settings"