#!/bin/bash

# =============================================================================
# DIAGNÓSTICO PROBLEMA AUTENTICAÇÃO - vlxsam02
# =============================================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK") echo -e "${GREEN}✅ $message${NC}" ;;
        "FAIL") echo -e "${RED}❌ $message${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠️ $message${NC}" ;;
        "INFO") echo -e "${BLUE}ℹ️ $message${NC}" ;;
    esac
}

echo "============================================="
echo "DIAGNÓSTICO PROBLEMA AUTENTICAÇÃO - vlxsam02"
echo "============================================="

# Configurações
API_BASE="http://localhost:3000"
APP_WORKING_DIR="/opt/samureye"

echo ""
print_status "INFO" "1. TESTANDO ROTAS DE AUTENTICAÇÃO"

# Testar rota /api/user sem autenticação
echo "Testando /api/user sem autenticação..."
response=$(curl -s -w "%{http_code}" "$API_BASE/api/user" -o /tmp/user_response.txt)
http_code="${response: -3}"

if [ "$http_code" = "200" ]; then
    print_status "FAIL" "Rota /api/user retorna 200 sem autenticação (PROBLEMA DE SEGURANÇA!)"
    echo "   Resposta: $(cat /tmp/user_response.txt)"
elif [ "$http_code" = "401" ]; then
    print_status "OK" "Rota /api/user corretamente protegida (401 Unauthorized)"
else
    print_status "WARN" "Rota /api/user retorna código $http_code"
fi

# Testar rota /api/admin/me 
echo ""
echo "Testando /api/admin/me..."
response=$(curl -s -w "%{http_code}" "$API_BASE/api/admin/me" -o /tmp/admin_response.txt)
http_code="${response: -3}"

if [ "$http_code" = "200" ]; then
    print_status "WARN" "Rota /api/admin/me permite acesso sem autenticação"
    echo "   Resposta: $(cat /tmp/admin_response.txt)"
else
    print_status "OK" "Rota /api/admin/me protegida (código $http_code)"
fi

# Testar outras rotas protegidas
echo ""
echo "Testando rotas administrativas protegidas..."
admin_routes=("/api/admin/tenants" "/api/admin/collectors" "/api/admin/stats")

for route in "${admin_routes[@]}"; do
    response=$(curl -s -w "%{http_code}" "$API_BASE$route" -o /tmp/route_response.txt)
    http_code="${response: -3}"
    
    if [ "$http_code" = "200" ]; then
        print_status "FAIL" "Rota $route acessível sem autenticação"
    elif [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        print_status "OK" "Rota $route protegida (código $http_code)"
    else
        print_status "WARN" "Rota $route retorna código $http_code"
    fi
done

echo ""
print_status "INFO" "2. VERIFICANDO CONFIGURAÇÃO DE SESSÃO"

# Verificar se aplicação está rodando
if ! pgrep -f "samureye-app" >/dev/null; then
    print_status "WARN" "Processo samureye-app não encontrado"
    print_status "INFO" "Tentando verificar via systemctl..."
    if systemctl is-active --quiet samureye-app; then
        print_status "OK" "Serviço samureye-app ativo"
    else
        print_status "FAIL" "Serviço samureye-app inativo"
    fi
fi

echo ""
print_status "INFO" "3. VERIFICANDO LOGS DA APLICAÇÃO"

# Verificar logs recentes
if [ -f "/var/log/samureye-app/app.log" ]; then
    print_status "INFO" "Últimas 10 linhas do log da aplicação:"
    tail -10 /var/log/samureye-app/app.log
elif [ -f "/opt/samureye/logs/app.log" ]; then
    print_status "INFO" "Últimas 10 linhas do log da aplicação:"
    tail -10 /opt/samureye/logs/app.log
else
    print_status "WARN" "Logs da aplicação não encontrados"
fi

echo ""
print_status "INFO" "4. VERIFICANDO CÓDIGO DA AUTENTICAÇÃO"

if [ -f "$APP_WORKING_DIR/server/routes.ts" ]; then
    print_status "INFO" "Verificando rota /api/user no código..."
    
    if grep -n "app.get('/api/user'" "$APP_WORKING_DIR/server/routes.ts" | grep -q "isAuthenticated"; then
        print_status "OK" "Rota /api/user possui middleware isAuthenticated"
    else
        print_status "FAIL" "Rota /api/user NÃO possui middleware isAuthenticated (PROBLEMA!)"
        print_status "INFO" "Linha da rota /api/user:"
        grep -n "app.get('/api/user'" "$APP_WORKING_DIR/server/routes.ts" || echo "   Rota não encontrada"
    fi
else
    print_status "WARN" "Arquivo routes.ts não encontrado em $APP_WORKING_DIR"
fi

echo ""
print_status "INFO" "5. RESUMO DO DIAGNÓSTICO"

echo ""
echo "🔧 POSSÍVEIS PROBLEMAS IDENTIFICADOS:"
echo "   • Rota /api/user permite acesso sem autenticação"
echo "   • Frontend não redireciona para login porque recebe resposta válida"
echo "   • Usuário consegue acessar interface sem fazer login"
echo ""
echo "💡 SOLUÇÃO RECOMENDADA:"
echo "   • Adicionar middleware 'isAuthenticated' na rota /api/user"
echo "   • Reiniciar aplicação após correção"
echo "   • Testar se login passa a ser obrigatório"
echo ""
echo "🔧 COMANDO PARA CORREÇÃO:"
echo "   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash"

echo ""
echo "============================================="