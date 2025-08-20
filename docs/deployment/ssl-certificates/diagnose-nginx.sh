#!/bin/bash

# Script de diagnóstico completo para NGINX SamurEye

echo "=== DIAGNÓSTICO NGINX SAMUREYE ==="
echo ""

# 1. Localizar arquivo de configuração
echo "📁 LOCALIZANDO CONFIGURAÇÕES NGINX:"
find /etc/nginx -name "*samur*" -type f 2>/dev/null || echo "Nenhum arquivo com 'samur' encontrado"
find /etc/nginx/sites-enabled -name "*" -type f 2>/dev/null | head -5
echo ""

# 2. Verificar estrutura de diretórios
echo "📂 ESTRUTURA /etc/nginx/:"
ls -la /etc/nginx/ 2>/dev/null | grep -E "(sites-|conf\.d)"
echo ""

# 3. Verificar configurações ativas
echo "🔧 CONFIGURAÇÕES ATIVAS EM sites-enabled/:"
ls -la /etc/nginx/sites-enabled/ 2>/dev/null || echo "Diretório não encontrado"
echo ""

# 4. Verificar erros específicos do nginx -t
echo "⚠️  TESTE DE CONFIGURAÇÃO NGINX:"
nginx -t 2>&1 | grep -A5 -B5 "limit_req_zone"
echo ""

# 5. Procurar todas as ocorrências de limit_req_zone
echo "🔍 BUSCANDO limit_req_zone EM TODOS OS ARQUIVOS:"
find /etc/nginx -type f -name "*.conf" -o -name "*" | head -10 | xargs grep -l "limit_req_zone" 2>/dev/null || echo "Nenhum arquivo encontrado"
echo ""

# 6. Verificar arquivo principal nginx.conf
echo "📋 ARQUIVO PRINCIPAL /etc/nginx/nginx.conf:"
grep -n "limit_req_zone\|include.*sites" /etc/nginx/nginx.conf 2>/dev/null || echo "Não encontrado"
echo ""

# 7. Verificar se há includes duplicados
echo "🔄 VERIFICANDO INCLUDES DUPLICADOS:"
grep -n "include" /etc/nginx/nginx.conf 2>/dev/null | grep sites
echo ""

# Comando para corrigir manualmente
echo "💡 COMANDOS PARA CORREÇÃO MANUAL:"
echo ""
echo "1. Listar arquivos de configuração:"
echo "   find /etc/nginx -name '*' -type f | grep -v '.backup'"
echo ""
echo "2. Verificar conteúdo dos arquivos:"
echo "   grep -n 'limit_req_zone' /etc/nginx/sites-enabled/*"
echo "   grep -n 'limit_req_zone' /etc/nginx/conf.d/*"
echo ""
echo "3. Editar arquivo problemático:"
echo "   nano /etc/nginx/sites-enabled/[arquivo]"
echo "   # Remover linhas duplicadas de limit_req_zone"
echo ""
echo "4. Testar e recarregar:"
echo "   nginx -t && systemctl reload nginx"
echo ""

# Solução automatizada
echo "🤖 SOLUÇÃO AUTOMATIZADA:"
echo ""
cat << 'EOF'
# Execute este comando para encontrar e remover duplicatas:
for file in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
    if [ -f "$file" ]; then
        echo "Verificando: $file"
        grep -n "limit_req_zone" "$file" 2>/dev/null || echo "  Sem limit_req_zone"
    fi
done

# Para remover duplicatas automaticamente (fazer backup primeiro):
cp /etc/nginx/sites-enabled/samureye /etc/nginx/sites-enabled/samureye.backup
awk '!seen[$0]++' /etc/nginx/sites-enabled/samureye > /tmp/nginx_fixed.conf
mv /tmp/nginx_fixed.conf /etc/nginx/sites-enabled/samureye
nginx -t && systemctl reload nginx
EOF

echo ""
echo "=== FIM DO DIAGNÓSTICO ==="