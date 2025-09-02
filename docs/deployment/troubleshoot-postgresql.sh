#!/bin/bash

# ============================================================================
# SCRIPT DE TROUBLESHOOTING - CONECTIVIDADE POSTGRESQL SAMUREYE
# ============================================================================
# Use: bash troubleshoot-postgresql.sh [servidor]
# Exemplo: bash troubleshoot-postgresql.sh vlxsam02
# Exemplo: bash troubleshoot-postgresql.sh vlxsam03

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função de log
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] ℹ️  $1${NC}"
}

# ============================================================================
# IDENTIFICAR SERVIDOR E CONFIGURAÇÕES
# ============================================================================

HOSTNAME=$(hostname)
SERVER_TYPE=""

case "$HOSTNAME" in
    vlxsam01)
        SERVER_TYPE="Gateway/NGINX"
        ;;
    vlxsam02)
        SERVER_TYPE="Application"
        POSTGRES_HOST="172.24.1.153"
        POSTGRES_PORT="5432"
        POSTGRES_DB="samureye"
        APP_DIR="/opt/samureye/SamurEye"
        ;;
    vlxsam03)
        SERVER_TYPE="Database"
        POSTGRES_HOST="localhost"
        POSTGRES_PORT="5432"
        POSTGRES_DB="samureye"
        ;;
    vlxsam04)
        SERVER_TYPE="Collector"
        POSTGRES_HOST="172.24.1.153"
        POSTGRES_PORT="5432"
        POSTGRES_DB="samureye"
        ;;
    *)
        warn "Servidor não identificado: $HOSTNAME"
        SERVER_TYPE="Unknown"
        ;;
esac

echo ""
echo "🔍 TROUBLESHOOTING POSTGRESQL - SAMUREYE"
echo "========================================"
echo "🖥️  Servidor: $HOSTNAME ($SERVER_TYPE)"
echo "📅 Data/Hora: $(date)"
echo "========================================"
echo ""

# ============================================================================
# 1. INFORMAÇÕES BÁSICAS DO SISTEMA
# ============================================================================

log "1️⃣  INFORMAÇÕES DO SISTEMA"
echo "────────────────────────────────────────"
echo "• Hostname: $(hostname -f)"
echo "• IP Address: $(ip route get 8.8.8.8 | grep -oP 'src \K\S+')"
echo "• OS: $(lsb_release -d | cut -f2)"
echo "• Kernel: $(uname -r)"
echo "• Uptime: $(uptime -p)"
echo "• Timezone: $(timedatectl | grep "Time zone" | awk '{print $3}')"
echo ""

# ============================================================================
# 2. VERIFICAR REDE E CONECTIVIDADE
# ============================================================================

log "2️⃣  VERIFICAÇÕES DE REDE"
echo "────────────────────────────────────────"

if [ "$SERVER_TYPE" = "Database" ]; then
    echo "📍 Este é o servidor de banco (vlxsam03)"
    
    echo "• Interfaces de rede:"
    ip addr show | grep -E "(inet|state UP)" | head -10
    
    echo ""
    echo "• Portas abertas:"
    netstat -tlnp | grep -E ':5432|:6379|:9000|:3000'
    
else
    echo "📍 Testando conectividade para vlxsam03 (172.24.1.153)"
    
    # Ping test
    echo -n "• Ping para 172.24.1.153: "
    if ping -c 1 -W 3 172.24.1.153 >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ FAIL${NC}"
    fi
    
    # TCP connectivity test
    echo -n "• Porta TCP 5432: "
    if timeout 5 nc -z 172.24.1.153 5432 2>/dev/null; then
        echo -e "${GREEN}✅ OPEN${NC}"
    else
        echo -e "${RED}❌ CLOSED/FILTERED${NC}"
    fi
    
    # Traceroute
    echo "• Rota de rede:"
    traceroute -n -w 2 -m 5 172.24.1.153 2>/dev/null | head -5 || echo "  traceroute não disponível"
    
fi

echo ""

# ============================================================================
# 3. VERIFICAR POSTGRESQL
# ============================================================================

log "3️⃣  STATUS DO POSTGRESQL"
echo "────────────────────────────────────────"

# Status do serviço
echo -n "• Status do serviço: "
if systemctl is-active --quiet postgresql; then
    echo -e "${GREEN}✅ ATIVO${NC}"
    systemctl status postgresql --no-pager -l | grep -E "(Active:|Main PID:|Memory:|Tasks:)" | head -4
else
    echo -e "${RED}❌ INATIVO${NC}"
    systemctl status postgresql --no-pager -l | tail -5
fi

echo ""

if [ "$SERVER_TYPE" = "Database" ]; then
    log "🔍 CONFIGURAÇÕES DO POSTGRESQL (vlxsam03)"
    
    # Verificar configuração de listen
    echo "• Listen addresses:"
    grep -E "^listen_addresses|^#listen_addresses" /etc/postgresql/*/main/postgresql.conf | head -3
    
    echo ""
    echo "• Configurações pg_hba.conf relevantes:"
    grep -E "(samureye|172\.24\.1\.)" /etc/postgresql/*/main/pg_hba.conf | head -10
    
    echo ""
    echo "• Usuários PostgreSQL:"
    sudo -u postgres psql -c "\du" 2>/dev/null || echo "  Erro ao conectar como postgres"
    
    echo ""
    echo "• Bancos de dados:"
    sudo -u postgres psql -c "\l" 2>/dev/null || echo "  Erro ao listar bancos"
    
    echo ""
    echo "• Processos PostgreSQL:"
    ps aux | grep postgres | grep -v grep | head -5
    
else
    log "🔍 TESTANDO CONECTIVIDADE POSTGRESQL"
    
    # Descobrir usuários possíveis
    USERS_TO_TEST=("samureye_user" "samureye" "postgres")
    PASSWORDS_TO_TEST=("samureye_secure_2024" "SamurEye2024!" "postgres")
    
    for user in "${USERS_TO_TEST[@]}"; do
        for password in "${PASSWORDS_TO_TEST[@]}"; do
            echo -n "• Teste: $user/$password: "
            if PGPASSWORD="$password" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$user" -d "$POSTGRES_DB" -c "SELECT version();" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ SUCESSO${NC}"
                echo "  ✓ Usuário funcional: $user"
                echo "  ✓ Senha funcional: $password"
                WORKING_USER="$user"
                WORKING_PASSWORD="$password"
                break 2
            else
                echo -e "${RED}❌ FALHA${NC}"
            fi
        done
    done
    
    if [ -n "$WORKING_USER" ]; then
        echo ""
        log "✅ Credenciais funcionais encontradas: $WORKING_USER"
        
        echo "• Testando operações básicas:"
        PGPASSWORD="$WORKING_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$WORKING_USER" -d "$POSTGRES_DB" -c "
        SELECT 
            current_database() as database,
            current_user as user,
            version() as version,
            now() as timestamp;
        " 2>/dev/null || echo "  Erro ao executar consultas básicas"
        
        echo ""
        echo "• Listando tabelas existentes:"
        PGPASSWORD="$WORKING_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$WORKING_USER" -d "$POSTGRES_DB" -c "\dt" 2>/dev/null || echo "  Erro ao listar tabelas"
        
    else
        error "❌ Nenhuma credencial funcional encontrada"
    fi
fi

echo ""

# ============================================================================
# 4. VERIFICAR APLICAÇÃO SAMUREYE (SE APLICÁVEL)
# ============================================================================

if [ "$SERVER_TYPE" = "Application" ] && [ -d "$APP_DIR" ]; then
    log "4️⃣  STATUS DA APLICAÇÃO SAMUREYE"
    echo "────────────────────────────────────────"
    
    # Status do serviço
    echo -n "• Status samureye-app: "
    if systemctl is-active --quiet samureye-app; then
        echo -e "${GREEN}✅ ATIVO${NC}"
    else
        echo -e "${RED}❌ INATIVO${NC}"
    fi
    
    # Verificar arquivo .env
    if [ -f "$APP_DIR/.env" ]; then
        echo "• Configurações .env:"
        grep -E "DATABASE_URL|POSTGRES" "$APP_DIR/.env" | head -5 || echo "  Nenhuma configuração de DB encontrada"
    else
        warn "• Arquivo .env não encontrado em $APP_DIR"
    fi
    
    # Verificar logs recentes
    echo ""
    echo "• Logs recentes da aplicação:"
    journalctl -u samureye-app --no-pager -l | tail -10 || echo "  Sem logs disponíveis"
    
    # Testar porta da aplicação
    echo ""
    echo -n "• Aplicação na porta 5000: "
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000" | grep -q "200\|301\|302"; then
        echo -e "${GREEN}✅ RESPONDENDO${NC}"
    else
        echo -e "${RED}❌ NÃO RESPONDE${NC}"
    fi
    
fi

# ============================================================================
# 5. VERIFICAR LOGS E ERROS
# ============================================================================

log "5️⃣  ANÁLISE DE LOGS"
echo "────────────────────────────────────────"

if [ "$SERVER_TYPE" = "Database" ]; then
    echo "• Últimos erros PostgreSQL:"
    find /var/log/postgresql -name "*.log" -exec tail -20 {} \; 2>/dev/null | grep -E "(ERROR|FATAL)" | tail -10 || echo "  Nenhum erro recente encontrado"
    
    echo ""
    echo "• Conexões recentes:"
    find /var/log/postgresql -name "*.log" -exec tail -50 {} \; 2>/dev/null | grep -E "(connection|authentication)" | tail -5 || echo "  Nenhum log de conexão encontrado"
fi

echo ""
echo "• Logs do sistema (últimos 10):"
journalctl --no-pager -n 10 | grep -E "(postgresql|samureye|error|fail)" || echo "  Nenhum log relevante encontrado"

# ============================================================================
# 6. DIAGNÓSTICO E RECOMENDAÇÕES
# ============================================================================

echo ""
log "6️⃣  DIAGNÓSTICO E RECOMENDAÇÕES"
echo "────────────────────────────────────────"

if [ "$SERVER_TYPE" = "Database" ]; then
    echo "📋 AÇÕES RECOMENDADAS PARA vlxsam03:"
    echo ""
    
    if ! systemctl is-active --quiet postgresql; then
        error "• PostgreSQL não está rodando - executar: systemctl start postgresql"
    fi
    
    if ! netstat -tlnp | grep -q ":5432"; then
        error "• PostgreSQL não está escutando na porta 5432"
        echo "  → Verificar: /etc/postgresql/*/main/postgresql.conf"
        echo "  → Deve conter: listen_addresses = '*'"
    fi
    
    echo "✅ Comandos úteis para vlxsam03:"
    echo "   systemctl restart postgresql"
    echo "   tail -f /var/log/postgresql/postgresql-*.log"
    echo "   netstat -tlnp | grep 5432"
    echo "   PGPASSWORD=samureye_secure_2024 psql -h localhost -U samureye_user -d samureye -c 'SELECT 1;'"
    
elif [ "$SERVER_TYPE" = "Application" ]; then
    echo "📋 AÇÕES RECOMENDADAS PARA vlxsam02:"
    echo ""
    
    if [ -n "$WORKING_USER" ]; then
        info "✅ Conectividade PostgreSQL OK com usuário: $WORKING_USER"
        
        if [ -f "$APP_DIR/.env" ] && ! grep -q "DATABASE_URL.*$WORKING_USER" "$APP_DIR/.env"; then
            warn "• Arquivo .env pode ter usuário incorreto"
            echo "  → Verificar DATABASE_URL em: $APP_DIR/.env"
            echo "  → Deve usar usuário: $WORKING_USER"
        fi
        
    else
        error "• Conectividade PostgreSQL FALHOU"
        echo "  → Verificar se vlxsam03 está funcionando"
        echo "  → Executar este script em vlxsam03: bash troubleshoot-postgresql.sh"
    fi
    
    echo ""
    echo "✅ Comandos úteis para vlxsam02:"
    echo "   systemctl restart samureye-app"
    echo "   journalctl -u samureye-app -f"
    echo "   curl http://localhost:5000/api/health"
    
fi

# ============================================================================
# 7. TESTE DE CRIAÇÃO DE TENANT (SE APLICÁVEL)
# ============================================================================

if [ "$SERVER_TYPE" = "Application" ] && [ -n "$WORKING_USER" ]; then
    echo ""
    log "7️⃣  TESTE DE CRIAÇÃO DE TENANT"
    echo "────────────────────────────────────────"
    
    # Verificar se API está respondendo
    API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000/api/health" 2>/dev/null || echo "000")
    
    if [[ "$API_STATUS" =~ ^[23] ]]; then
        info "✅ API respondendo (HTTP $API_STATUS)"
        
        echo "• Testando criação de tenant via API:"
        TENANT_RESPONSE=$(curl -s -X POST "http://localhost:5000/api/admin/tenants" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Teste Troubleshoot",
                "slug": "teste-troubleshoot",
                "description": "Tenant de teste para troubleshooting",
                "isActive": true
            }' 2>&1)
        
        if echo "$TENANT_RESPONSE" | grep -q '"id"'; then
            info "✅ Criação de tenant funcionou"
        else
            warn "❌ Erro na criação de tenant:"
            echo "$TENANT_RESPONSE" | head -3
        fi
        
    else
        warn "❌ API não está respondendo (HTTP $API_STATUS)"
    fi
fi

echo ""
echo "========================================"
log "🎯 TROUBLESHOOTING CONCLUÍDO"
echo "========================================"
echo "📄 Para suporte, envie a saída completa deste script"
echo "📧 Servidor: $HOSTNAME ($SERVER_TYPE)"
echo "📅 $(date)"
echo "========================================"