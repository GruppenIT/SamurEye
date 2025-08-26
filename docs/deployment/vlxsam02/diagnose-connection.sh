#!/bin/bash

# Script de diagnóstico específico para identificar problema de conexão porta 443

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

echo "🔍 DIAGNÓSTICO DETALHADO - Problema Conexão Porta 443"
echo "=================================================="

# 1. Verificar estrutura de arquivos
log "1️⃣ Verificando estrutura de arquivos..."

WORKING_DIR="/opt/samureye/SamurEye"
ETC_DIR="/etc/samureye"

echo "Diretório da aplicação: $WORKING_DIR"
echo "Diretório de configuração: $ETC_DIR"
echo ""

if [ ! -d "$WORKING_DIR" ]; then
    echo "❌ ERRO: Diretório da aplicação não existe: $WORKING_DIR"
    exit 1
fi

if [ ! -d "$ETC_DIR" ]; then
    echo "❌ ERRO: Diretório de configuração não existe: $ETC_DIR"
    exit 1
fi

# 2. Verificar arquivo .env
log "2️⃣ Verificando arquivo .env..."

if [ -f "$ETC_DIR/.env" ]; then
    echo "✅ Arquivo .env existe: $ETC_DIR/.env"
    
    # Verificar DATABASE_URL
    if grep -q "DATABASE_URL" "$ETC_DIR/.env"; then
        DATABASE_URL_LINE=$(grep "DATABASE_URL" "$ETC_DIR/.env")
        echo "🔧 DATABASE_URL encontrada: $DATABASE_URL_LINE"
        
        if echo "$DATABASE_URL_LINE" | grep -q ":443"; then
            echo "❌ PROBLEMA: DATABASE_URL contém porta 443!"
        elif echo "$DATABASE_URL_LINE" | grep -q ":5432"; then
            echo "✅ DATABASE_URL contém porta correta (5432)"
        else
            echo "⚠️ DATABASE_URL não contém especificação de porta clara"
        fi
    else
        echo "❌ DATABASE_URL não encontrada no .env"
    fi
    
    echo ""
    echo "📋 Conteúdo do .env (apenas DATABASE_URL e conexões):"
    grep -E "(DATABASE_URL|PGHOST|PGPORT|REDIS_URL)" "$ETC_DIR/.env" | head -10
else
    echo "❌ Arquivo .env não existe: $ETC_DIR/.env"
fi

echo ""

# 3. Verificar links simbólicos
log "3️⃣ Verificando links simbólicos..."

for link_path in "/opt/samureye/.env" "$WORKING_DIR/.env"; do
    if [ -L "$link_path" ]; then
        target=$(readlink "$link_path")
        echo "✅ Link: $link_path -> $target"
        
        if [ "$target" = "$ETC_DIR/.env" ]; then
            echo "✅ Link aponta para o local correto"
        else
            echo "❌ Link aponta para local incorreto"
        fi
    elif [ -f "$link_path" ]; then
        echo "⚠️ Arquivo regular (não link): $link_path"
    else
        echo "❌ Link não existe: $link_path"
    fi
done

echo ""

# 4. Procurar configurações hardcoded
log "4️⃣ Procurando configurações hardcoded no código..."

cd "$WORKING_DIR"

echo "🔍 Procurando por ':443' em arquivos de código..."
if find . -name "*.ts" -o -name "*.js" | xargs grep -n ":443" 2>/dev/null; then
    echo "❌ Encontradas referências à porta 443 no código!"
else
    echo "✅ Nenhuma referência à porta 443 encontrada"
fi

echo ""
echo "🔍 Procurando por 'https://172.24.1.153' em arquivos de código..."
if find . -name "*.ts" -o -name "*.js" | xargs grep -n "https://172.24.1.153" 2>/dev/null; then
    echo "❌ Encontradas URLs HTTPS incorretas no código!"
else
    echo "✅ Nenhuma URL HTTPS incorreta encontrada"
fi

echo ""
echo "🔍 Procurando por '172.24.1.153.*443' em arquivos de código..."
if find . -name "*.ts" -o -name "*.js" | xargs grep -n "172\.24\.1\.153.*443" 2>/dev/null; then
    echo "❌ Encontradas configurações IP:443 incorretas no código!"
else
    echo "✅ Nenhuma configuração IP:443 encontrada"
fi

echo ""

# 5. Verificar configuração do servidor
log "5️⃣ Verificando configuração do servidor..."

if [ -f "server/index.ts" ]; then
    echo "📄 Primeiras 10 linhas do server/index.ts:"
    head -10 server/index.ts
    echo ""
    
    if head -10 server/index.ts | grep -q "dotenv"; then
        echo "✅ dotenv está configurado no servidor"
    else
        echo "❌ dotenv NÃO está configurado no servidor"
    fi
else
    echo "❌ Arquivo server/index.ts não encontrado"
fi

echo ""

# 6. Verificar se dotenv está instalado
log "6️⃣ Verificando se dotenv está instalado..."

if [ -f "package.json" ]; then
    if grep -q '"dotenv"' package.json; then
        echo "✅ dotenv está no package.json"
    else
        echo "❌ dotenv NÃO está no package.json"
    fi
    
    if [ -d "node_modules/dotenv" ]; then
        echo "✅ dotenv está instalado em node_modules"
    else
        echo "❌ dotenv NÃO está instalado em node_modules"
    fi
else
    echo "❌ package.json não encontrado"
fi

echo ""

# 7. Testar carregamento de variáveis (se aplicação estiver rodando)
log "7️⃣ Testando carregamento de variáveis..."

# Criar script de teste
cat > /tmp/test-env-loading.js << 'EOF'
// Testar carregamento de variáveis sem dependências externas
console.log('=== TESTE DE CARREGAMENTO ===');
console.log('NODE_ENV:', process.env.NODE_ENV || 'undefined');
console.log('DATABASE_URL existe:', process.env.DATABASE_URL ? 'SIM' : 'NÃO');

if (process.env.DATABASE_URL) {
    const url = process.env.DATABASE_URL;
    console.log('DATABASE_URL (primeiros 50 chars):', url.substring(0, 50) + '...');
    
    if (url.includes(':443')) {
        console.log('❌ PROBLEMA: DATABASE_URL contém :443');
        process.exit(1);
    } else if (url.includes(':5432')) {
        console.log('✅ DATABASE_URL contém :5432 (correto)');
    } else {
        console.log('⚠️ DATABASE_URL sem especificação clara de porta');
    }
} else {
    console.log('❌ DATABASE_URL não carregada');
}

console.log('=== FIM DO TESTE ===');
EOF

echo "🧪 Executando teste de carregamento..."
if sudo -u samureye node /tmp/test-env-loading.js 2>/dev/null; then
    echo "✅ Teste executado com sucesso"
else
    echo "❌ Teste falhou"
fi

rm -f /tmp/test-env-loading.js

echo ""

# 8. Verificar status do serviço e logs recentes
log "8️⃣ Verificando status do serviço..."

if systemctl is-active --quiet samureye-app; then
    echo "✅ Serviço samureye-app está ativo"
    
    echo ""
    echo "📋 Logs recentes do serviço (últimos 20 linhas):"
    journalctl -u samureye-app --since "5 minutes ago" --no-pager -q | tail -20
    
    echo ""
    echo "🔍 Procurando por erros de conexão 443 nos logs:"
    if journalctl -u samureye-app --since "5 minutes ago" --no-pager -q | grep -q "ECONNREFUSED.*:443"; then
        echo "❌ ENCONTRADOS ERROS de conexão porta 443:"
        journalctl -u samureye-app --since "5 minutes ago" --no-pager -q | grep "ECONNREFUSED.*:443" | tail -3
    else
        echo "✅ Nenhum erro de conexão porta 443 encontrado"
    fi
    
else
    echo "❌ Serviço samureye-app NÃO está ativo"
    echo ""
    echo "📋 Status do serviço:"
    systemctl status samureye-app --no-pager -l
fi

echo ""

cd - >/dev/null

# 9. Resumo e recomendações
echo "============================================"
echo "🎯 RESUMO DO DIAGNÓSTICO"
echo "============================================"
echo ""

# Verificar se encontramos problemas
problems_found=false

if [ ! -f "$ETC_DIR/.env" ]; then
    echo "❌ Arquivo .env não existe"
    problems_found=true
fi

if grep -q ":443" "$ETC_DIR/.env" 2>/dev/null; then
    echo "❌ Arquivo .env contém porta 443"
    problems_found=true
fi

cd "$WORKING_DIR"
if find . -name "*.ts" -o -name "*.js" | xargs grep -q ":443\|https://172.24.1.153" 2>/dev/null; then
    echo "❌ Código contém configurações hardcoded incorretas"
    problems_found=true
fi
cd - >/dev/null

if ! head -10 "$WORKING_DIR/server/index.ts" | grep -q "dotenv" 2>/dev/null; then
    echo "❌ Server não carrega dotenv"
    problems_found=true
fi

if journalctl -u samureye-app --since "5 minutes ago" --no-pager -q | grep -q "ECONNREFUSED.*:443" 2>/dev/null; then
    echo "❌ Logs mostram tentativas de conexão na porta 443"
    problems_found=true
fi

echo ""
if [ "$problems_found" = true ]; then
    echo "🔧 AÇÕES RECOMENDADAS:"
    echo "   1. Executar: ./fix-env-loading.sh"
    echo "   2. Executar: ./fix-port-443-issue.sh"
    echo "   3. Reiniciar serviço e verificar logs"
else
    echo "✅ Nenhum problema óbvio encontrado"
    echo "ℹ️ Se o problema persiste, pode ser necessário análise mais detalhada"
fi
echo ""
log "🏁 Diagnóstico concluído"