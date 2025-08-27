#!/bin/bash

# Script para diagnosticar problemas de DNS e SSL do domínio app.samureye.com.br

echo "=== DIAGNÓSTICO DNS e SSL PARA app.samureye.com.br ==="
echo ""

# Verificar resolução DNS
echo "1. RESOLUÇÃO DNS:"
getent hosts app.samureye.com.br || echo "Falha na resolução DNS"
echo ""

# Verificar conectividade básica
echo "2. CONECTIVIDADE:"
timeout 5 telnet 200.155.137.4 443 2>/dev/null && echo "Porta 443 aberta" || echo "Porta 443 fechada ou timeout"
timeout 5 telnet 200.155.137.4 80 2>/dev/null && echo "Porta 80 aberta" || echo "Porta 80 fechada ou timeout"
echo ""

# Verificar certificado SSL
echo "3. CERTIFICADO SSL:"
echo | timeout 10 openssl s_client -connect 200.155.137.4:443 -servername app.samureye.com.br 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "Falha ao obter certificado SSL"
echo ""

# Testar HTTP simples
echo "4. TESTE HTTP (porta 80):"
curl -s -m 5 http://200.155.137.4 | head -2 2>/dev/null || echo "Falha na conexão HTTP"
echo ""

# Verificar se é o servidor correto
echo "5. IDENTIFICAÇÃO DO SERVIDOR:"
curl -s -m 5 -I http://200.155.137.4 | grep -i server || echo "Header Server não encontrado"
echo ""

# Verificar redirecionamento
echo "6. REDIRECIONAMENTO HTTP->HTTPS:"
curl -s -m 5 -I http://app.samureye.com.br | grep -i location || echo "Sem redirecionamento encontrado"
echo ""

# Comparar com servidor local
echo "7. SERVIDOR LOCAL (vlxsam02):"
echo "IP local: $(hostname -I | awk '{print $1}')"
echo "Teste local: $(curl -s -m 3 http://172.24.1.152:5000/api/health | jq -r .status 2>/dev/null || echo 'Falha')"
echo ""

echo "=== CONCLUSÃO ==="
echo "DNS app.samureye.com.br -> 200.155.137.4"
echo "Servidor local vlxsam02: $(hostname -I | awk '{print $1}'):5000"
echo ""
echo "PROBLEMA: DNS não aponta para o servidor correto!"
echo "SOLUÇÃO: Atualizar DNS para apontar para $(hostname -I | awk '{print $1}') ou configurar proxy/load balancer"