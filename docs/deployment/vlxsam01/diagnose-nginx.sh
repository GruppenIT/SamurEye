#!/bin/bash

# Diagnóstico rápido NGINX no vlxsam01
# Identifica problema de página em branco no HTTPS

echo "=== Diagnóstico NGINX vlxsam01 ==="

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK") echo -e "${GREEN}✅ $message${NC}" ;;
        "FAIL") echo -e "${RED}❌ $message${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "INFO") echo -e "ℹ️  $message" ;;
    esac
}

# Status serviços
print_status "INFO" "Status dos serviços:"
systemctl is-active nginx >/dev/null && print_status "OK" "NGINX rodando" || print_status "FAIL" "NGINX parado"

# Portas
print_status "INFO" "Portas abertas:"
ss -tlnp | grep ":80" >/dev/null && print_status "OK" "Porta 80 aberta" || print_status "FAIL" "Porta 80 fechada"
ss -tlnp | grep ":443" >/dev/null && print_status "OK" "Porta 443 aberta" || print_status "FAIL" "Porta 443 fechada"

# Certificados
print_status "INFO" "Certificados Let's Encrypt:"
if [ -d "/etc/letsencrypt/live" ]; then
    for cert_dir in /etc/letsencrypt/live/*; do
        if [ -d "$cert_dir" ] && [ -f "$cert_dir/cert.pem" ]; then
            domain=$(basename "$cert_dir")
            print_status "OK" "Certificado: $domain"
        fi
    done
else
    print_status "FAIL" "Diretório Let's Encrypt não existe"
fi

# Configuração nginx
print_status "INFO" "Configurações nginx ativas:"
if [ -d "/etc/nginx/sites-enabled" ]; then
    for config in /etc/nginx/sites-enabled/*; do
        if [ -f "$config" ]; then
            config_name=$(basename "$config")
            print_status "OK" "Config ativa: $config_name"
        fi
    done
else
    print_status "WARN" "Diretório sites-enabled não existe"
fi

# Teste configuração nginx
print_status "INFO" "Testando configuração nginx..."
if nginx -t 2>/dev/null; then
    print_status "OK" "Configuração nginx válida"
else
    print_status "FAIL" "Erro na configuração nginx:"
    nginx -t
fi

# Conectividade backend
print_status "INFO" "Testando backend vlxsam02:5000..."
if curl -s --connect-timeout 3 http://172.24.1.152:5000/api/system/settings >/dev/null; then
    print_status "OK" "Backend vlxsam02:5000 respondendo"
else
    print_status "FAIL" "Backend vlxsam02:5000 não responde"
fi

# Teste HTTPS local
print_status "INFO" "Testando HTTPS local..."
response=$(curl -s -o /dev/null -w "%{http_code}" -k https://127.0.0.1/ 2>/dev/null || echo "000")
case "$response" in
    "200"|"301"|"302") print_status "OK" "HTTPS local funcionando (código $response)" ;;
    "000") print_status "FAIL" "HTTPS local sem resposta" ;;
    *) print_status "WARN" "HTTPS local código $response" ;;
esac

# Logs recentes
print_status "INFO" "Logs nginx recentes (últimas 3 linhas):"
if [ -f "/var/log/nginx/error.log" ]; then
    tail -n 3 /var/log/nginx/error.log | while IFS= read -r line; do
        [ -n "$line" ] && echo "   $line"
    done
else
    print_status "WARN" "Log de erro nginx não encontrado"
fi

echo ""
print_status "INFO" "Para corrigir problemas identificados:"
echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam01/fix-nginx-proxy.sh | sudo bash"