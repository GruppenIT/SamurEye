#!/bin/bash

# Script de lembrete para renovação manual de certificados
# Para ser executado via cron 30 dias antes do vencimento

CERT_PATH="/etc/letsencrypt/live/samureye.com.br/fullchain.pem"
EMAIL="admin@samureye.com.br"  # Configurar email correto

# Verificar se o certificado existe
if [ ! -f "$CERT_PATH" ]; then
    echo "Certificado não encontrado em $CERT_PATH"
    exit 1
fi

# Obter data de expiração
EXPIRY_DATE=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

echo "=== Status do Certificado SSL SamurEye ==="
echo "Certificado: $CERT_PATH"
echo "Expira em: $EXPIRY_DATE"
echo "Dias restantes: $DAYS_LEFT"

# Alertar se menos de 30 dias
if [ $DAYS_LEFT -le 30 ]; then
    echo ""
    echo "⚠️  ATENÇÃO: Certificado expira em $DAYS_LEFT dias!"
    echo ""
    echo "Para renovar:"
    echo "1. Acesse o servidor vlxsam01 (172.24.1.151)"
    echo "2. Execute: sudo /opt/setup-certificates.sh"
    echo "3. Escolha opção 7 (DNS Manual Assistido)"
    echo ""
    
    # Opcional: enviar email de alerta
    if command -v mail >/dev/null 2>&1; then
        echo "Certificado SSL SamurEye expira em $DAYS_LEFT dias. Renovar em vlxsam01." | \
        mail -s "ALERTA: Renovação SSL SamurEye necessária" "$EMAIL"
    fi
    
    # Log do sistema
    logger "SamurEye SSL certificate expires in $DAYS_LEFT days - manual renewal required"
fi