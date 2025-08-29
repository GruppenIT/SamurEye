#!/bin/bash
# Script para registrar o collector vlxsam04 no banco de dados da aplicação SamurEye

set -e

# Configurações
COLLECTOR_NAME="vlxsam04"
HOSTNAME="vlxsam04"
API_URL="http://localhost:5000"
TENANT_SLUG="gruppen-it"

echo "🔄 Registrando collector $COLLECTOR_NAME no SamurEye..."

# 1. Fazer login como admin
echo "Step 1: Login de administrador..."
LOGIN_RESPONSE=$(curl -s -c /tmp/samureye_cookies.txt -X POST \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@samureye.com.br","password":"SamurEye2024!"}' \
    "$API_URL/api/admin/login")

if [[ "$LOGIN_RESPONSE" == *"sucesso"* ]]; then
    echo "✅ Login realizado com sucesso"
else
    echo "❌ Falha no login: $LOGIN_RESPONSE"
    exit 1
fi

# 2. Verificar se tenant existe
echo "Step 2: Verificando tenant $TENANT_SLUG..."
TENANT_RESPONSE=$(curl -s -b /tmp/samureye_cookies.txt "$API_URL/api/admin/tenants")

if [[ "$TENANT_RESPONSE" == *"$TENANT_SLUG"* ]]; then
    echo "✅ Tenant $TENANT_SLUG encontrado"
    # Extrair tenant ID (assumindo formato JSON simples)
    TENANT_ID=$(echo "$TENANT_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "  Tenant ID: $TENANT_ID"
else
    echo "❌ Tenant $TENANT_SLUG não encontrado"
    echo "Resposta: $TENANT_RESPONSE"
    exit 1
fi

# 3. Registrar collector
echo "Step 3: Registrando collector..."
COLLECTOR_DATA=$(cat <<EOF
{
    "name": "$COLLECTOR_NAME",
    "hostname": "$HOSTNAME", 
    "tenantId": "$TENANT_ID",
    "status": "enrolling",
    "capabilities": ["nmap", "nuclei", "security-scan"],
    "version": "1.0.0"
}
EOF
)

REGISTER_RESPONSE=$(curl -s -b /tmp/samureye_cookies.txt -X POST \
    -H "Content-Type: application/json" \
    -d "$COLLECTOR_DATA" \
    "$API_URL/api/collectors")

if [[ "$REGISTER_RESPONSE" == *"enrollmentToken"* ]]; then
    echo "✅ Collector registrado com sucesso!"
    
    # Extrair o enrollment token
    ENROLLMENT_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"enrollmentToken":"[^"]*"' | cut -d'"' -f4)
    echo "  Enrollment Token: $ENROLLMENT_TOKEN"
    
    # Salvar token no collector
    echo "$ENROLLMENT_TOKEN" > /opt/samureye-collector/enrollment-token.txt
    chown samureye-collector:samureye-collector /opt/samureye-collector/enrollment-token.txt
    chmod 600 /opt/samureye-collector/enrollment-token.txt
    
else
    echo "❌ Falha ao registrar collector"
    echo "Resposta: $REGISTER_RESPONSE"
    exit 1
fi

# 4. Testar heartbeat
echo "Step 4: Testando heartbeat..."
HEARTBEAT_DATA=$(cat <<EOF
{
    "collector_id": "$COLLECTOR_NAME",
    "status": "online",
    "timestamp": "$(date -Iseconds)",
    "telemetry": {
        "cpu_percent": 12.5,
        "memory_percent": 35.2,
        "disk_percent": 42.1,
        "processes": 135
    },
    "capabilities": ["nmap", "nuclei"]
}
EOF
)

HEARTBEAT_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$HEARTBEAT_DATA" \
    "$API_URL/collector-api/heartbeat")

if [[ "$HEARTBEAT_RESPONSE" == *"Heartbeat received"* ]]; then
    echo "✅ Heartbeat enviado com sucesso!"
    echo "  Resposta: $HEARTBEAT_RESPONSE"
else
    echo "⚠️ Problema com heartbeat"
    echo "  Resposta: $HEARTBEAT_RESPONSE"
fi

# 5. Atualizar configuração do collector Python para usar novo endpoint
echo "Step 5: Atualizando configuração do collector..."

# Atualizar URL da API no collector Python
sed -i "s|https://api.samureye.com.br/api/collectors/heartbeat|https://api.samureye.com.br/collector-api/heartbeat|g" /opt/samureye-collector/collector_agent.py

# Reiniciar serviço do collector
echo "Step 6: Reiniciando serviço do collector..."
systemctl restart samureye-collector.service
sleep 3

if systemctl is-active samureye-collector.service >/dev/null; then
    echo "✅ Serviço do collector reiniciado com sucesso"
else
    echo "⚠️ Problema ao reiniciar serviço do collector"
fi

# Limpar cookies temporários
rm -f /tmp/samureye_cookies.txt

echo ""
echo "🎉 Registro do collector concluído!"
echo ""
echo "🔍 Comandos para verificar:"
echo "  systemctl status samureye-collector.service"
echo "  journalctl -u samureye-collector.service -f"
echo "  curl -X POST -H 'Content-Type: application/json' -d '{\"collector_id\":\"$COLLECTOR_NAME\",\"status\":\"online\"}' $API_URL/collector-api/heartbeat"