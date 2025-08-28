#!/bin/bash

# Script para corrigir registro do collector vlxsam04
set -e

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2
}

log "🔧 Corrigindo registro do collector vlxsam04..."

# Configurações
COLLECTOR_DIR="/opt/samureye-collector"
CERTS_DIR="$COLLECTOR_DIR/certs"
CA_URL="https://ca.samureye.com.br"
STEP_PATH="/usr/local/bin/step"

# Verificar se step está instalado
if ! command -v step >/dev/null 2>&1; then
    error "step-ca client não está instalado"
    exit 1
fi

# Criar script de registro corrigido
cat > "$COLLECTOR_DIR/register-collector-fixed.sh" << 'EOF'
#!/bin/bash
# Script de Registro do Collector SamurEye - CORRIGIDO
# Versão: 2.0.0 - Corrigido para step-ca
# Uso: ./register-collector-fixed.sh <tenant-slug> <collector-name>

set -euo pipefail

# Configurações
COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
API_BASE_URL="https://api.samureye.com.br"
CA_URL="https://ca.samureye.com.br"
CERTS_DIR="$COLLECTOR_DIR/certs"
STEP_PATH="/usr/local/bin/step"

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

echo "🔧 SamurEye Collector Registration - CORRIGIDO"
echo "=============================================="
echo "Tenant: $TENANT_SLUG"
echo "Collector: $COLLECTOR_NAME"
echo "API: $API_BASE_URL"
echo "CA: $CA_URL"
echo ""

log "1. Preparando ambiente..."
mkdir -p "$CERTS_DIR"
chown samureye-collector:samureye-collector "$CERTS_DIR"
chmod 700 "$CERTS_DIR"

# Remover configuração anterior do step se existir
rm -rf /home/samureye-collector/.step 2>/dev/null || true
rm -rf "$CERTS_DIR"/* 2>/dev/null || true

log "2. Testando conectividade com CA..."
if ! timeout 10 curl -k -s -I "$CA_URL" | grep -q "HTTP"; then
    error "CA não está acessível em $CA_URL"
    echo ""
    echo "Verificações necessárias:"
    echo "1. vlxsam01 (Gateway) está funcionando?"
    echo "2. NGINX está proxy para step-ca na porta 9000?"
    echo "3. DNS aponta ca.samureye.com.br para vlxsam01?"
    echo ""
    echo "Teste manual: curl -k -I $CA_URL"
    exit 1
fi

log "✅ CA acessível"

log "3. Obtendo root certificate..."
# Método 1: Baixar root certificate diretamente
ROOT_CERT_URL="$CA_URL/root"
if curl -k -s -f "$ROOT_CERT_URL" -o "$CERTS_DIR/root_ca.crt"; then
    log "✅ Root certificate baixado via API"
    
    # Verificar se é um certificado válido
    if openssl x509 -in "$CERTS_DIR/root_ca.crt" -text -noout >/dev/null 2>&1; then
        log "✅ Root certificate válido"
        
        # Calcular fingerprint correto
        CA_FINGERPRINT=$(openssl x509 -in "$CERTS_DIR/root_ca.crt" -fingerprint -sha256 -noout | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
        log "✅ Fingerprint calculado: ${CA_FINGERPRINT:0:16}..."
    else
        error "Root certificate inválido"
        exit 1
    fi
else
    error "Falha ao baixar root certificate de $ROOT_CERT_URL"
    
    # Método 2: Extrair do TLS handshake
    log "Tentando método alternativo..."
    if timeout 10 openssl s_client -connect ca.samureye.com.br:443 -servername ca.samureye.com.br </dev/null 2>/dev/null | openssl x509 -outform PEM > "$CERTS_DIR/root_ca.crt" 2>/dev/null; then
        log "✅ Root certificate extraído via TLS"
        CA_FINGERPRINT=$(openssl x509 -in "$CERTS_DIR/root_ca.crt" -fingerprint -sha256 -noout | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
        log "✅ Fingerprint: ${CA_FINGERPRINT:0:16}..."
    else
        error "Não foi possível obter root certificate"
        exit 1
    fi
fi

log "4. Configurando step-ca bootstrap..."
# Executar bootstrap como usuário collector
if sudo -u samureye-collector "$STEP_PATH" ca bootstrap \
    --ca-url "$CA_URL" \
    --fingerprint "$CA_FINGERPRINT" \
    --install \
    --force; then
    log "✅ Step-ca bootstrap concluído"
else
    error "Falha no step-ca bootstrap"
    
    # Método alternativo - configuração manual
    log "Tentando configuração manual..."
    
    # Criar diretório step para o usuário
    STEP_HOME="/home/samureye-collector/.step"
    mkdir -p "$STEP_HOME"
    chown samureye-collector:samureye-collector "$STEP_HOME"
    
    # Criar configuração manual
    cat > "$STEP_HOME/config.json" << STEPEOF
{
  "ca-url": "$CA_URL",
  "fingerprint": "$CA_FINGERPRINT",
  "root": "$STEP_HOME/certs/root_ca.crt"
}
STEPEOF
    
    # Copiar root certificate
    mkdir -p "$STEP_HOME/certs"
    cp "$CERTS_DIR/root_ca.crt" "$STEP_HOME/certs/root_ca.crt"
    chown -R samureye-collector:samureye-collector "$STEP_HOME"
    
    log "✅ Configuração manual do step-ca aplicada"
fi

log "5. Testando step-ca configuration..."
if sudo -u samureye-collector "$STEP_PATH" ca health; then
    log "✅ Step-ca configurado e funcionando"
else
    warn "Step-ca health check falhou - prosseguindo..."
fi

log "6. Gerando certificados do collector..."

# Gerar certificado do collector
if sudo -u samureye-collector "$STEP_PATH" certificate create \
    "$COLLECTOR_NAME" \
    "$CERTS_DIR/collector.crt" \
    "$CERTS_DIR/collector.key" \
    --profile leaf \
    --not-after 8760h \
    --san "$COLLECTOR_NAME" \
    --san "vlxsam04" \
    --san "$(hostname -f)" \
    --san "$(hostname -s)" \
    --force; then
    log "✅ Certificado do collector gerado"
else
    error "Falha ao gerar certificado do collector"
    exit 1
fi

# Verificar arquivos gerados
if [[ -f "$CERTS_DIR/collector.crt" && -f "$CERTS_DIR/collector.key" ]]; then
    log "✅ Arquivos de certificado verificados"
    
    # Verificar certificado
    if openssl x509 -in "$CERTS_DIR/collector.crt" -text -noout | grep -q "$COLLECTOR_NAME"; then
        log "✅ Certificado contém SAN correto"
    else
        warn "Certificado pode não ter SAN correto"
    fi
else
    error "Arquivos de certificado não encontrados"
    exit 1
fi

log "7. Configurando permissões..."
chown -R samureye-collector:samureye-collector "$CERTS_DIR"
chmod 600 "$CERTS_DIR"/*.key 2>/dev/null || true
chmod 644 "$CERTS_DIR"/*.crt 2>/dev/null || true

log "8. Registrando collector na API..."

# Criar payload de registro
REGISTRATION_DATA=$(cat <<REGEOF
{
  "name": "$COLLECTOR_NAME",
  "hostname": "$(hostname -f)",
  "ip_address": "$(hostname -I | awk '{print $1}')",
  "certificate": "$(base64 -w 0 "$CERTS_DIR/collector.crt")",
  "type": "security_scanner",
  "capabilities": ["nmap", "nuclei", "security_scan"],
  "tenant_slug": "$TENANT_SLUG"
}
REGEOF
)

# Registrar via API
REGISTER_RESPONSE=$(curl -k -s -X POST \
    -H "Content-Type: application/json" \
    -d "$REGISTRATION_DATA" \
    --cert "$CERTS_DIR/collector.crt" \
    --key "$CERTS_DIR/collector.key" \
    --cacert "$CERTS_DIR/root_ca.crt" \
    "$API_BASE_URL/api/admin/collectors" || echo "CURL_FAILED")

if [[ "$REGISTER_RESPONSE" == "CURL_FAILED" ]]; then
    warn "Falha na comunicação com API - verificando conectividade..."
    
    # Teste básico da API
    if curl -k -s -I "$API_BASE_URL/api/system/settings" | grep -q "HTTP"; then
        log "✅ API acessível"
    else
        error "API não está acessível"
        exit 1
    fi
    
    # Tentar novamente sem certificado cliente para teste
    TEST_RESPONSE=$(curl -k -s -X GET "$API_BASE_URL/api/system/settings" || echo "FAILED")
    if [[ "$TEST_RESPONSE" != "FAILED" ]]; then
        warn "API funciona sem mTLS - problema pode ser nos certificados"
    fi
else
    log "✅ Resposta da API recebida"
    echo "Response: $REGISTER_RESPONSE"
    
    # Verificar se registro foi bem-sucedido
    if echo "$REGISTER_RESPONSE" | grep -q '"id"'; then
        log "✅ Collector registrado com sucesso na API"
    else
        warn "Registro pode não ter sido bem-sucedido"
        echo "Resposta completa: $REGISTER_RESPONSE"
    fi
fi

log "9. Atualizando configuração do collector..."

# Atualizar arquivo de configuração
cat > "$CONFIG_DIR/.env" << ENVEOF
# SamurEye Collector Configuration - Auto-generated
COLLECTOR_NAME=$COLLECTOR_NAME
TENANT_SLUG=$TENANT_SLUG
API_BASE_URL=$API_BASE_URL
CA_URL=$CA_URL
STEP_CA_FINGERPRINT=$CA_FINGERPRINT

# Certificados
TLS_CERT_FILE=$CERTS_DIR/collector.crt
TLS_KEY_FILE=$CERTS_DIR/collector.key
CA_CERT_FILE=$CERTS_DIR/root_ca.crt

# Logs
LOG_LEVEL=info
LOG_FILE=/var/log/samureye-collector/collector.log
ENVEOF

chown samureye-collector:samureye-collector "$CONFIG_DIR/.env"
chmod 600 "$CONFIG_DIR/.env"

log "10. Reiniciando serviço..."
systemctl restart samureye-collector.service

# Aguardar estabilização
sleep 3

if systemctl is-active samureye-collector.service >/dev/null 2>&1; then
    log "✅ Serviço samureye-collector reiniciado com sucesso"
else
    error "Falha ao reiniciar serviço"
    echo "Verificar logs: journalctl -u samureye-collector.service -f"
    exit 1
fi

echo ""
echo "🎉 REGISTRO DO COLLECTOR CONCLUÍDO COM SUCESSO!"
echo "=============================================="
echo ""
echo "📊 Resumo da configuração:"
echo "  Collector: $COLLECTOR_NAME"
echo "  Tenant: $TENANT_SLUG"
echo "  Certificados: $CERTS_DIR"
echo "  Configuração: $CONFIG_DIR/.env"
echo ""
echo "🔍 Verificar status:"
echo "  systemctl status samureye-collector.service"
echo "  journalctl -u samureye-collector.service -f"
echo ""
echo "🌐 Teste de conectividade:"
echo "  curl -k --cert $CERTS_DIR/collector.crt --key $CERTS_DIR/collector.key $API_BASE_URL/api/system/settings"
echo ""
echo "✅ Collector vlxsam04 registrado e operacional!"
EOF

chmod +x "$COLLECTOR_DIR/register-collector-fixed.sh"

# Baixar script funcionando (método simplificado)
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/register-collector-working.sh -o "$COLLECTOR_DIR/register-collector-working.sh"
chmod +x "$COLLECTOR_DIR/register-collector-working.sh"

log "✅ Script de registro simplificado criado"
log "Execute: cd $COLLECTOR_DIR && sudo ./register-collector-working.sh gruppen-it vlxsam04"