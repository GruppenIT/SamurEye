#!/bin/bash

# Correção rápida para duplicação de limit_req_zone no NGINX

echo "🔧 Corrigindo duplicação de limit_req_zone..."

# Backup primeiro
cp /etc/nginx/sites-enabled/samureye /etc/nginx/sites-enabled/samureye.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || echo "Arquivo não encontrado em sites-enabled"

# Tentar diferentes locais
for CONFIG_FILE in "/etc/nginx/sites-enabled/samureye" "/etc/nginx/conf.d/samureye.conf" "/etc/nginx/sites-available/samureye"; do
    if [ -f "$CONFIG_FILE" ]; then
        echo "Encontrado: $CONFIG_FILE"
        
        # Contar ocorrências
        LIMIT_COUNT=$(grep -c "limit_req_zone.*api" "$CONFIG_FILE" 2>/dev/null || echo "0")
        echo "Ocorrências de limit_req_zone api: $LIMIT_COUNT"
        
        if [ "$LIMIT_COUNT" -gt 1 ]; then
            echo "Removendo duplicatas..."
            
            # Backup específico
            cp "$CONFIG_FILE" "$CONFIG_FILE.before-fix"
            
            # Remover duplicatas mantendo apenas a primeira
            awk '
            /limit_req_zone.*api/ {
                if (!api_seen) {
                    print
                    api_seen = 1
                    next
                }
                next
            }
            { print }
            ' "$CONFIG_FILE" > "/tmp/nginx_fixed.conf"
            
            # Aplicar correção
            mv "/tmp/nginx_fixed.conf" "$CONFIG_FILE"
            echo "✅ Duplicatas removidas de $CONFIG_FILE"
        fi
    fi
done

# Verificar se ainda há problemas
echo ""
echo "🧪 Testando configuração..."
if nginx -t; then
    echo "✅ Configuração válida! Recarregando..."
    systemctl reload nginx
    echo "✅ NGINX recarregado"
else
    echo "❌ Ainda há erros. Verificação manual necessária:"
    echo ""
    echo "Execute estes comandos para investigar:"
    echo "  grep -rn 'limit_req_zone' /etc/nginx/"
    echo "  nginx -t"
fi