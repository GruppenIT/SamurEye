#!/bin/bash

# Script de correção para inicialização do step-ca no vlxsam01
echo "🔧 Corrigindo inicialização do step-ca..."

# Configurar diretório e permissões
STEP_CA_DIR="/etc/step-ca"
sudo mkdir -p "$STEP_CA_DIR"/{certs,secrets,config}
sudo chown -R step-ca:step-ca "$STEP_CA_DIR"
sudo chmod -R 755 "$STEP_CA_DIR"

echo "✅ Diretório $STEP_CA_DIR configurado com permissões corretas"

# Criar script de inicialização corrigido
sudo tee /tmp/step-ca-init-fixed.sh > /dev/null << 'STEP_INIT'
#!/bin/bash
set -e

# Definir variáveis
CA_NAME="SamurEye Internal CA"
DNS_NAME="ca.samureye.com.br"
ADDRESS=":9000"
PASSWORD="samureye-ca-$(openssl rand -hex 16)"

# Mudar para diretório step-ca
cd /etc/step-ca

# Salvar senha em arquivo seguro
echo "$PASSWORD" > password.txt
chmod 600 password.txt

echo "🔐 Inicializando Certificate Authority..."

# Inicializar CA
step ca init \
    --name="$CA_NAME" \
    --dns="$DNS_NAME" \
    --address="$ADDRESS" \
    --provisioner="admin@samureye.com.br" \
    --password-file="password.txt" \
    --force

echo "✅ step-ca inicializado com sucesso"
echo "CA Name: $CA_NAME"
echo "DNS: $DNS_NAME" 
echo "Address: $ADDRESS"
echo "Password saved to: /etc/step-ca/password.txt"

# Obter e salvar fingerprint
if [ -f "certs/root_ca.crt" ]; then
    FINGERPRINT=$(step certificate fingerprint certs/root_ca.crt)
    echo "CA Fingerprint: $FINGERPRINT"
    echo "$FINGERPRINT" > fingerprint.txt
    chmod 644 fingerprint.txt
else
    echo "⚠️  Certificado root não encontrado, verificar configuração"
fi

STEP_INIT

# Tornar script executável e executar como usuário step-ca
sudo chmod +x /tmp/step-ca-init-fixed.sh
sudo chown step-ca:step-ca /tmp/step-ca-init-fixed.sh

echo "🚀 Executando inicialização do step-ca..."
sudo -u step-ca /tmp/step-ca-init-fixed.sh

# Ajustar permissões finais
sudo chown -R step-ca:step-ca "$STEP_CA_DIR"
sudo chmod -R 700 "$STEP_CA_DIR"
sudo chmod 644 "$STEP_CA_DIR"/certs/*.crt 2>/dev/null || true

echo "✅ step-ca inicializado e configurado com sucesso"

# Verificar se a configuração foi criada
if [ -f "$STEP_CA_DIR/config/ca.json" ]; then
    echo "✅ Arquivo de configuração criado: $STEP_CA_DIR/config/ca.json"
else
    echo "⚠️  Arquivo de configuração não encontrado"
fi

if [ -f "$STEP_CA_DIR/certs/root_ca.crt" ]; then
    echo "✅ Certificado root criado: $STEP_CA_DIR/certs/root_ca.crt"
else
    echo "⚠️  Certificado root não encontrado"
fi

echo "🎉 Correção aplicada com sucesso!"
echo "Agora você pode continuar com o script principal."