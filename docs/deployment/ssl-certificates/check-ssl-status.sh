#!/bin/bash

# Script para verificar status completo dos certificados SSL SamurEye
# Uso: sudo ./check-ssl-status.sh

echo "=== STATUS CERTIFICADOS SSL SAMUREYE ==="
echo "Data: $(date)"
echo ""

# 1. Verificar certificados do certbot
echo "📋 CERTIFICADOS CERTBOT:"
if command -v certbot >/dev/null 2>&1; then
    certbot certificates 2>/dev/null || echo "Nenhum certificado encontrado"
else
    echo "Certbot não instalado"
fi

echo ""

# 2. Verificar arquivos de certificado
echo "📁 ARQUIVOS DE CERTIFICADO:"
if [ -d "/etc/letsencrypt/live/samureye.com.br" ]; then
    ls -la /etc/letsencrypt/live/samureye.com.br/
    echo ""
    
    # Verificar datas de expiração
    echo "📅 DATAS DE EXPIRAÇÃO:"
    CERT_PATH="/etc/letsencrypt/live/samureye.com.br/fullchain.pem"
    if [ -f "$CERT_PATH" ]; then
        EXPIRY=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
        CURRENT_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
        
        echo "Expira em: $EXPIRY"
        echo "Dias restantes: $DAYS_LEFT"
        
        if [ $DAYS_LEFT -le 30 ]; then
            echo "⚠️  ATENÇÃO: Renovação necessária!"
        elif [ $DAYS_LEFT -le 7 ]; then
            echo "🚨 URGENTE: Certificado expira em breve!"
        else
            echo "✅ Certificado válido"
        fi
    else
        echo "❌ Arquivo de certificado não encontrado"
    fi
else
    echo "❌ Diretório de certificados não encontrado"
fi

echo ""

# 3. Verificar configuração NGINX
echo "🌐 CONFIGURAÇÃO NGINX:"
if command -v nginx >/dev/null 2>&1; then
    nginx -t 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ Configuração NGINX válida"
    else
        echo "❌ Erro na configuração NGINX"
        nginx -t
    fi
    
    # Verificar se NGINX está rodando
    if systemctl is-active --quiet nginx; then
        echo "✅ NGINX rodando"
    else
        echo "❌ NGINX parado"
    fi
else
    echo "❌ NGINX não instalado"
fi

echo ""

# 4. Testar conectividade HTTPS
echo "🔒 TESTE DE CONECTIVIDADE HTTPS:"
DOMAINS=("app.samureye.com.br" "api.samureye.com.br" "scanner.samureye.com.br")

for domain in "${DOMAINS[@]}"; do
    echo -n "Testando $domain: "
    
    # Testar conexão HTTPS
    if curl -s -I "https://$domain" >/dev/null 2>&1; then
        echo "✅ OK"
    else
        echo "❌ FALHA"
    fi
done

echo ""

# 5. Verificar renovação automática
echo "🔄 RENOVAÇÃO AUTOMÁTICA:"
if [ -f "/etc/cron.d/certbot-renew" ]; then
    echo "✅ Cron de renovação configurado:"
    cat /etc/cron.d/certbot-renew
elif [ -f "/etc/cron.d/ssl-renewal-reminder" ]; then
    echo "⚠️  Renovação manual - lembrete configurado:"
    cat /etc/cron.d/ssl-renewal-reminder
else
    echo "❌ Renovação não configurada"
fi

echo ""

# 6. Verificar logs recentes
echo "📝 LOGS RECENTES (últimas 5 entradas):"
if [ -f "/var/log/letsencrypt/letsencrypt.log" ]; then
    tail -5 /var/log/letsencrypt/letsencrypt.log
else
    echo "Log do Let's Encrypt não encontrado"
fi

echo ""

# 7. Verificar rate limits
echo "⚠️  VERIFICAÇÃO DE RATE LIMITS:"
if [ -f "/var/log/letsencrypt/letsencrypt.log" ]; then
    RECENT_ERRORS=$(grep -c "Service busy\|rate limit" /var/log/letsencrypt/letsencrypt.log 2>/dev/null || echo "0")
    CERT_COUNT=$(certbot certificates 2>/dev/null | grep -c "samureye.com.br" || echo "0")
    
    echo "Erros de rate limit encontrados: $RECENT_ERRORS"
    echo "Certificados para samureye.com.br: $CERT_COUNT"
    
    if [ "$RECENT_ERRORS" -gt 0 ] || [ "$CERT_COUNT" -ge 3 ]; then
        echo "⚠️  Cuidado com rate limiting ao renovar"
    else
        echo "✅ Rate limits OK"
    fi
else
    echo "Não foi possível verificar rate limits"
fi

echo ""
echo "=== FIM DO RELATÓRIO ==="
echo ""
echo "💡 PRÓXIMOS PASSOS:"
echo "- Para renovar certificado manual: sudo ./setup-certificates.sh (opção 7)"
echo "- Para troubleshooting: consulte TROUBLESHOOTING-CERTIFICATES.md"
echo "- Para logs detalhados: sudo tail -f /var/log/letsencrypt/letsencrypt.log"