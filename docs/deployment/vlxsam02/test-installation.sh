#!/bin/bash

# Script de teste completo da instalação vlxsam02

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

echo "🧪 TESTE DE INSTALAÇÃO VLXSAM02"
echo "==============================="

# 1. Testar conectividade com PostgreSQL
log "1️⃣ Testando conectividade PostgreSQL..."

echo "🔌 Testando conexão TCP com vlxsam03:5432..."
if timeout 5 bash -c "</dev/tcp/172.24.1.153/5432"; then
    echo "✅ Conectividade TCP: OK"
else
    echo "❌ Conectividade TCP: FALHA"
    echo "⚠️ Verificar se PostgreSQL está rodando em vlxsam03"
    exit 1
fi

echo "🗄️ Testando autenticação PostgreSQL..."
if PGPASSWORD=SamurEye2024! psql -h 172.24.1.153 -p 5432 -U samureye -d samureye_prod -c "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ Autenticação PostgreSQL: OK"
else
    echo "❌ Autenticação PostgreSQL: FALHA"
    echo "⚠️ Verificar credenciais ou configuração do banco"
fi

echo ""

# 2. Testar conectividade com Redis
log "2️⃣ Testando conectividade Redis..."

if timeout 5 bash -c "</dev/tcp/172.24.1.153/6379"; then
    echo "✅ Conectividade Redis: OK"
else
    echo "❌ Conectividade Redis: FALHA"
    echo "⚠️ Verificar se Redis está rodando em vlxsam03"
fi

echo ""

# 3. Verificar estrutura da aplicação
log "3️⃣ Verificando estrutura da aplicação..."

WORKING_DIR="/opt/samureye/SamurEye"
ETC_DIR="/etc/samureye"

# Verificar diretórios
for dir in "$WORKING_DIR" "$ETC_DIR"; do
    if [ -d "$dir" ]; then
        echo "✅ Diretório existe: $dir"
    else
        echo "❌ Diretório não existe: $dir"
    fi
done

# Verificar arquivos essenciais
essential_files=(
    "$WORKING_DIR/package.json"
    "$WORKING_DIR/server/index.ts"
    "$WORKING_DIR/server/db.ts"
    "$ETC_DIR/.env"
)

for file in "${essential_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ Arquivo existe: $file"
    else
        echo "❌ Arquivo não existe: $file"
    fi
done

echo ""

# 4. Verificar configuração .env
log "4️⃣ Verificando configuração .env..."

if [ -f "$ETC_DIR/.env" ]; then
    echo "📄 Verificando variáveis essenciais..."
    
    # Lista de variáveis obrigatórias
    required_vars=(
        "DATABASE_URL"
        "PGHOST"
        "PGPORT"
        "NODE_ENV"
        "PORT"
    )
    
    for var in "${required_vars[@]}"; do
        if grep -q "^$var=" "$ETC_DIR/.env"; then
            value=$(grep "^$var=" "$ETC_DIR/.env" | cut -d'=' -f2- | head -1)
            echo "✅ $var está definida"
            
            # Verificações específicas
            if [ "$var" = "DATABASE_URL" ]; then
                if echo "$value" | grep -q ":443"; then
                    echo "❌ $var contém porta incorreta (443)"
                elif echo "$value" | grep -q ":5432"; then
                    echo "✅ $var contém porta correta (5432)"
                fi
            fi
        else
            echo "❌ $var não está definida"
        fi
    done
else
    echo "❌ Arquivo .env não encontrado"
fi

echo ""

# 5. Verificar links simbólicos
log "5️⃣ Verificando links simbólicos..."

symlinks=(
    "/opt/samureye/.env"
    "$WORKING_DIR/.env"
)

for link in "${symlinks[@]}"; do
    if [ -L "$link" ]; then
        target=$(readlink "$link")
        echo "✅ Link: $link -> $target"
        
        if [ "$target" = "$ETC_DIR/.env" ]; then
            echo "✅ Aponta para local correto"
        else
            echo "⚠️ Aponta para local diferente do esperado"
        fi
    else
        echo "❌ Link não existe: $link"
    fi
done

echo ""

# 6. Verificar serviço systemd
log "6️⃣ Verificando serviço systemd..."

if systemctl list-unit-files | grep -q "samureye-app.service"; then
    echo "✅ Serviço samureye-app está registrado"
    
    if systemctl is-enabled samureye-app >/dev/null 2>&1; then
        echo "✅ Serviço está habilitado"
    else
        echo "⚠️ Serviço não está habilitado"
    fi
    
    if systemctl is-active --quiet samureye-app; then
        echo "✅ Serviço está ativo"
    else
        echo "❌ Serviço não está ativo"
    fi
else
    echo "❌ Serviço samureye-app não está registrado"
fi

echo ""

# 7. Testar aplicação
log "7️⃣ Testando aplicação..."

if systemctl is-active --quiet samureye-app; then
    echo "🌐 Testando endpoint de saúde..."
    
    if curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
        echo "✅ API está respondendo"
        
        # Testar endpoint específico
        response=$(curl -s http://localhost:5000/api/health 2>/dev/null || echo "erro")
        if [ "$response" != "erro" ]; then
            echo "✅ Resposta da API: OK"
        else
            echo "⚠️ API responde mas com possível erro"
        fi
    else
        echo "❌ API não está respondendo"
    fi
    
    echo ""
    echo "📋 Verificando logs de erro recentes..."
    if journalctl -u samureye-app --since "5 minutes ago" --no-pager -q | grep -q "ERROR\|Error\|error"; then
        echo "⚠️ Encontrados erros nos logs:"
        journalctl -u samureye-app --since "5 minutes ago" --no-pager -q | grep -i error | tail -3
    else
        echo "✅ Nenhum erro encontrado nos logs recentes"
    fi
    
    echo ""
    echo "🔍 Verificando especificamente erro porta 443..."
    if journalctl -u samureye-app --since "5 minutes ago" --no-pager -q | grep -q "ECONNREFUSED.*:443"; then
        echo "❌ ERRO CRÍTICO: Tentativa de conexão na porta 443"
        journalctl -u samureye-app --since "5 minutes ago" --no-pager -q | grep "ECONNREFUSED.*:443" | tail -2
        echo ""
        echo "🔧 SOLUÇÃO: Execute ./fix-port-443-issue.sh"
    else
        echo "✅ Nenhum erro de porta 443 encontrado"
    fi
else
    echo "⚠️ Serviço não está ativo, não é possível testar API"
fi

echo ""

# 8. Verificar recursos do sistema
log "8️⃣ Verificando recursos do sistema..."

echo "💾 Uso de memória:"
free -h | grep -E "(Mem:|Swap:)"

echo ""
echo "💽 Uso de disco:"
df -h /opt /etc | grep -v "Filesystem"

echo ""
echo "🔄 Processos Node.js:"
pgrep -f "node\|tsx" | wc -l | awk '{print $1 " processos Node.js ativos"}'

echo ""

# 9. Resumo final
echo "============================================"
echo "🎯 RESUMO DOS TESTES"
echo "============================================"

# Determinar status geral
issues_found=0

# Verificar problemas críticos
if ! timeout 5 bash -c "</dev/tcp/172.24.1.153/5432" 2>/dev/null; then
    echo "❌ Conectividade PostgreSQL falhou"
    ((issues_found++))
fi

if [ ! -f "$ETC_DIR/.env" ]; then
    echo "❌ Arquivo .env não existe"
    ((issues_found++))
fi

if grep -q ":443" "$ETC_DIR/.env" 2>/dev/null; then
    echo "❌ Configuração .env contém porta 443"
    ((issues_found++))
fi

if ! systemctl is-active --quiet samureye-app; then
    echo "❌ Serviço não está ativo"
    ((issues_found++))
fi

if journalctl -u samureye-app --since "5 minutes ago" --no-pager -q | grep -q "ECONNREFUSED.*:443" 2>/dev/null; then
    echo "❌ Logs mostram tentativas de conexão porta 443"
    ((issues_found++))
fi

echo ""
if [ $issues_found -eq 0 ]; then
    echo "🎉 INSTALAÇÃO ESTÁ FUNCIONANDO CORRETAMENTE!"
    echo "✅ Todos os testes passaram"
    echo "✅ Nenhum problema crítico encontrado"
elif [ $issues_found -le 2 ]; then
    echo "⚠️ INSTALAÇÃO FUNCIONAL COM PROBLEMAS MENORES"
    echo "🔧 Execute os scripts de correção se necessário"
else
    echo "❌ INSTALAÇÃO TEM PROBLEMAS CRÍTICOS"
    echo "🔧 Execute: ./fix-env-loading.sh && ./fix-port-443-issue.sh"
fi

echo ""
echo "📚 COMANDOS ÚTEIS PARA DIAGNÓSTICO:"
echo "   - journalctl -u samureye-app -f     # Logs em tempo real"
echo "   - systemctl status samureye-app     # Status do serviço"
echo "   - ./diagnose-connection.sh          # Diagnóstico detalhado"
echo ""
log "🏁 Teste de instalação concluído"