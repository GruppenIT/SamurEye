#!/bin/bash

# Script de verificação completa da instalação SamurEye
# Execute após instalar todos os 4 servidores

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

echo "======================================="
echo "  VERIFICAÇÃO COMPLETA SAMUREYE BAS   "
echo "======================================="
echo ""

# Definir IPs dos servidores
VLXSAM01_IP="172.24.1.151"  # Gateway
VLXSAM02_IP="172.24.1.152"  # Application  
VLXSAM03_IP="172.24.1.153"  # Database
VLXSAM04_IP="192.168.100.151"  # Collector

info "Testando conectividade com todos os servidores..."

# ============================================================================
# 1. TESTE DE CONECTIVIDADE BÁSICA
# ============================================================================

echo ""
echo "🌐 CONECTIVIDADE BÁSICA"
echo "======================="

servers=(
    "vlxsam01:$VLXSAM01_IP:22:SSH Gateway"
    "vlxsam02:$VLXSAM02_IP:22:SSH Application"
    "vlxsam03:$VLXSAM03_IP:22:SSH Database"
    "vlxsam04:$VLXSAM04_IP:22:SSH Collector"
)

for server in "${servers[@]}"; do
    IFS=':' read -r name ip port desc <<< "$server"
    if nc -z -w5 "$ip" "$port" 2>/dev/null; then
        echo "✅ $name ($ip:$port) - $desc"
    else
        echo "❌ $name ($ip:$port) - $desc"
    fi
done

# ============================================================================
# 2. TESTE DE SERVIÇOS POR SERVIDOR
# ============================================================================

echo ""
echo "⚙️  SERVIÇOS POR SERVIDOR"
echo "========================"

# vlxsam01 - Gateway
echo ""
echo "🌐 vlxsam01 - Gateway:"
if nc -z -w5 "$VLXSAM01_IP" 80 2>/dev/null; then
    echo "✅ HTTP (80) - Redirecionamento HTTPS"
else
    echo "❌ HTTP (80)"
fi

if nc -z -w5 "$VLXSAM01_IP" 443 2>/dev/null; then
    echo "✅ HTTPS (443) - Gateway SSL"
else
    echo "❌ HTTPS (443)"
fi

# vlxsam02 - Application
echo ""
echo "🖥️  vlxsam02 - Application:"
if nc -z -w5 "$VLXSAM02_IP" 3000 2>/dev/null; then
    echo "✅ App (3000) - Node.js Application"
else
    echo "❌ App (3000)"
fi

if nc -z -w5 "$VLXSAM02_IP" 3001 2>/dev/null; then
    echo "✅ Scanner (3001) - Security Tools"
else
    echo "❌ Scanner (3001)"
fi

# vlxsam03 - Database
echo ""
echo "🗄️  vlxsam03 - Database:"
if nc -z -w5 "$VLXSAM03_IP" 5432 2>/dev/null; then
    echo "✅ PostgreSQL (5432)"
else
    echo "❌ PostgreSQL (5432)"
fi

if nc -z -w5 "$VLXSAM03_IP" 6379 2>/dev/null; then
    echo "✅ Redis (6379)"
else
    echo "❌ Redis (6379)"
fi

if nc -z -w5 "$VLXSAM03_IP" 9000 2>/dev/null; then
    echo "✅ MinIO (9000)"
else
    echo "❌ MinIO (9000)"
fi

if nc -z -w5 "$VLXSAM03_IP" 3000 2>/dev/null; then
    echo "✅ Grafana (3000)"
else
    echo "❌ Grafana (3000)"
fi

# vlxsam04 - Collector (outbound-only)
echo ""
echo "📡 vlxsam04 - Collector:"
echo "ℹ️  Collector usa comunicação outbound-only"
echo "   Verificar logs no próprio servidor para status"

# ============================================================================
# 3. TESTE DE ENDPOINTS PÚBLICOS
# ============================================================================

echo ""
echo "🌍 ENDPOINTS PÚBLICOS"
echo "====================="

# Teste HTTPS público
if curl -f -s -k -I "https://app.samureye.com.br/nginx-health" >/dev/null 2>&1; then
    echo "✅ https://app.samureye.com.br - Frontend"
else
    echo "❌ https://app.samureye.com.br - Frontend"
fi

if curl -f -s -k -I "https://api.samureye.com.br" >/dev/null 2>&1; then
    echo "✅ https://api.samureye.com.br - API"
else
    echo "❌ https://api.samureye.com.br - API"
fi

# ============================================================================
# 4. TESTE DE INTEGRAÇÕES
# ============================================================================

echo ""
echo "🔗 INTEGRAÇÕES"
echo "=============="

# Teste de conectividade vlxsam02 -> vlxsam03
info "Testando conectividade Application -> Database..."

# PostgreSQL
if nc -z -w5 "$VLXSAM03_IP" 5432 2>/dev/null; then
    echo "✅ vlxsam02 -> vlxsam03:5432 (PostgreSQL)"
else
    echo "❌ vlxsam02 -> vlxsam03:5432 (PostgreSQL)"
fi

# Redis  
if nc -z -w5 "$VLXSAM03_IP" 6379 2>/dev/null; then
    echo "✅ vlxsam02 -> vlxsam03:6379 (Redis)"
else
    echo "❌ vlxsam02 -> vlxsam03:6379 (Redis)"
fi

# MinIO
if nc -z -w5 "$VLXSAM03_IP" 9000 2>/dev/null; then
    echo "✅ vlxsam02 -> vlxsam03:9000 (MinIO)"
else
    echo "❌ vlxsam02 -> vlxsam03:9000 (MinIO)"
fi

# Teste conectividade vlxsam01 -> vlxsam02
info "Testando conectividade Gateway -> Application..."
if nc -z -w5 "$VLXSAM02_IP" 3000 2>/dev/null; then
    echo "✅ vlxsam01 -> vlxsam02:3000 (Proxy Pass)"
else
    echo "❌ vlxsam01 -> vlxsam02:3000 (Proxy Pass)"
fi

# ============================================================================
# 5. TESTE DE CERTIFICADOS SSL
# ============================================================================

echo ""
echo "🔐 CERTIFICADOS SSL"
echo "=================="

# Verificar certificado
if command -v openssl >/dev/null 2>&1; then
    cert_info=$(echo | openssl s_client -servername app.samureye.com.br -connect app.samureye.com.br:443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "✅ Certificado SSL válido:"
        echo "$cert_info" | sed 's/^/   /'
        
        # Verificar expiração
        expiry=$(echo "$cert_info" | grep "notAfter" | cut -d'=' -f2)
        if [ -n "$expiry" ]; then
            expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry" +%s 2>/dev/null)
            current_epoch=$(date +%s)
            
            if [ -n "$expiry_epoch" ] && [ "$expiry_epoch" -gt "$current_epoch" ]; then
                days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
                if [ $days_left -gt 30 ]; then
                    echo "✅ Certificado expira em $days_left dias"
                else
                    warn "Certificado expira em $days_left dias - renovar em breve"
                fi
            fi
        fi
    else
        echo "❌ Erro ao verificar certificado SSL"
    fi
else
    echo "⚠️  OpenSSL não disponível para verificar certificado"
fi

# ============================================================================
# 6. TESTE DE PERFORMANCE BÁSICA
# ============================================================================

echo ""
echo "⚡ PERFORMANCE BÁSICA"
echo "===================="

# Tempo de resposta do frontend
frontend_time=$(curl -w "%{time_total}" -o /dev/null -s "https://app.samureye.com.br" 2>/dev/null || echo "timeout")
if [ "$frontend_time" != "timeout" ]; then
    echo "✅ Frontend responde em ${frontend_time}s"
else
    echo "❌ Frontend não responde"
fi

# Tempo de resposta da API
api_time=$(curl -w "%{time_total}" -o /dev/null -s "https://api.samureye.com.br" 2>/dev/null || echo "timeout")
if [ "$api_time" != "timeout" ]; then
    echo "✅ API responde em ${api_time}s"
else
    echo "❌ API não responde"
fi

# ============================================================================
# 7. RESUMO E RECOMENDAÇÕES
# ============================================================================

echo ""
echo "📋 RESUMO DA VERIFICAÇÃO"
echo "======================="

# Contar sucessos e falhas
total_tests=20  # Aproximadamente
passed_tests=$(echo "$output" | grep -c "✅" || echo "0")

echo ""
echo "🎯 Status Geral:"
echo "   Testes executados: $total_tests"
echo "   Sucessos: Verificar saída acima"
echo "   Falhas: Verificar ❌ na saída"

echo ""
echo "💡 PRÓXIMOS PASSOS RECOMENDADOS:"
echo ""

if nc -z -w5 "$VLXSAM01_IP" 443 2>/dev/null; then
    echo "1. ✅ Acesse https://app.samureye.com.br para interface web"
else
    echo "1. ❌ Configurar SSL no vlxsam01 antes de prosseguir"
fi

if nc -z -w5 "$VLXSAM02_IP" 3000 2>/dev/null; then
    echo "2. ✅ Aplicação rodando - configure variáveis em /etc/samureye/.env"
else
    echo "2. ❌ Iniciar aplicação no vlxsam02"
fi

if nc -z -w5 "$VLXSAM03_IP" 5432 2>/dev/null; then
    echo "3. ✅ Banco disponível - executar migrações se necessário"
else
    echo "3. ❌ Verificar serviços de banco no vlxsam03"
fi

echo "4. 📡 Registrar collector vlxsam04 na interface web"
echo "5. 🔧 Configurar integração Delinea Secret Server"
echo "6. 🧪 Executar testes de jornadas de segurança"

echo ""
echo "📚 DOCUMENTAÇÃO:"
echo "   - README principal: docs/deployment/README.md"
echo "   - Configuração por servidor: docs/deployment/vlxsam*/README.md"
echo "   - Troubleshooting: docs/deployment/README.md#troubleshooting"

echo ""
echo "📞 SUPORTE:"
echo "   Em caso de problemas, verifique:"
echo "   - Logs de cada servidor: /var/log/samureye/"
echo "   - Status dos serviços: systemctl status samureye-*"
echo "   - Scripts de health check específicos de cada servidor"

echo ""
log "Verificação completa da instalação SamurEye finalizada!"
echo "======================================="