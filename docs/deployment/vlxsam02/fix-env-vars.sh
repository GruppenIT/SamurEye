#!/bin/bash

# ============================================================================
# CORREÇÃO VARIÁVEIS DE AMBIENTE - SAMUREYE VLXSAM02
# Script para adicionar variáveis de ambiente faltantes
# ============================================================================

set -euo pipefail

# Variáveis
readonly ETC_DIR="/etc/samureye"
readonly WORKING_DIR="/opt/samureye/SamurEye"

# Função de logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

echo "🔧 CORREÇÃO VARIÁVEIS DE AMBIENTE"
echo "================================"
log "🎯 Adicionando variáveis faltantes ao .env..."

# 1. Verificar se é root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script deve ser executado como root"
    exit 1
fi

# 2. Parar serviço
log "⏹️ Parando serviço..."
systemctl stop samureye-app

# 3. Backup do .env atual
log "💾 Fazendo backup do .env..."
cp "$ETC_DIR/.env" "$ETC_DIR/.env.backup.$(date +%Y%m%d_%H%M%S)"

# 4. Criar .env completo com todas as variáveis necessárias
log "📝 Atualizando arquivo .env..."
cat > "$ETC_DIR/.env" << 'EOF'
# Configuração SamurEye - vlxsam02
NODE_ENV=development
PORT=5000

# Configuração do banco PostgreSQL (vlxsam03)
PGHOST=172.24.1.153
PGPORT=5432
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye

# Configuração Redis (vlxsam03)
REDIS_HOST=172.24.1.153
REDIS_PORT=6379

# Configuração de sessão
SESSION_SECRET=SamurEye_Session_Secret_2024_vlxsam02

# Configuração do servidor
FRONTEND_URL=https://samureye.com.br
API_BASE_URL=https://api.samureye.com.br

# Configuração Replit Auth (NECESSÁRIAS)
REPLIT_DOMAINS=samureye.com.br,app.samureye.com.br,api.samureye.com.br,vlxsam02.samureye.com.br
REPL_ID=samureye-production-vlxsam02
ISSUER_URL=https://replit.com/oidc

# Configuração de upload
MAX_FILE_SIZE=10485760
UPLOAD_PATH=/opt/samureye/uploads

# Configuração de logs
LOG_LEVEL=info
LOG_FILE=/var/log/samureye/app.log

# Certificados e SSL
SSL_CERT_PATH=/etc/ssl/certs/samureye.pem
SSL_KEY_PATH=/etc/ssl/private/samureye.key

# Configuração mTLS para coletores
MTLS_CA_PATH=/opt/samureye/ssl/ca.pem
MTLS_CERT_PATH=/opt/samureye/ssl/server.pem
MTLS_KEY_PATH=/opt/samureye/ssl/server-key.pem

# Configuração de auditoria
AUDIT_LOG_ENABLED=true
AUDIT_LOG_PATH=/var/log/samureye/audit.log

# Configurações adicionais para produção
CORS_ORIGIN=https://samureye.com.br,https://app.samureye.com.br
RATE_LIMIT_MAX=1000
RATE_LIMIT_WINDOW_MS=900000

# Configuração de email (opcional)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=noreply@samureye.com.br
SMTP_PASS=

# Configuração de backup
BACKUP_ENABLED=true
BACKUP_SCHEDULE=0 2 * * *
BACKUP_RETENTION_DAYS=30

# Configuração de monitoramento
METRICS_ENABLED=true
HEALTH_CHECK_ENABLED=true
PING_TIMEOUT=5000
EOF

# 5. Configurar permissões
chown samureye:samureye "$ETC_DIR/.env"
chmod 600 "$ETC_DIR/.env"

# 6. Testar carregamento das variáveis
log "🧪 Testando carregamento das novas variáveis..."
cd "$WORKING_DIR"

# Criar script de teste
cat > test-env-complete.mjs << 'EOF'
import dotenv from 'dotenv';

console.log('=== TESTE COMPLETO DE VARIÁVEIS ===');

try {
    const result = dotenv.config();
    
    if (result.error) {
        console.log('❌ ERRO ao carregar .env:', result.error.message);
        process.exit(1);
    }
    
    console.log('✅ dotenv carregado com sucesso');
    
    // Verificar variáveis essenciais
    const requiredVars = [
        'DATABASE_URL', 
        'PGHOST', 
        'PGPORT', 
        'NODE_ENV',
        'REPLIT_DOMAINS',
        'REPL_ID',
        'SESSION_SECRET'
    ];
    
    let allOk = true;
    
    for (const varName of requiredVars) {
        if (process.env[varName]) {
            const displayValue = varName === 'DATABASE_URL' || varName === 'SESSION_SECRET' ? 
                process.env[varName].substring(0, 30) + '...' : 
                process.env[varName];
            console.log(`✅ ${varName}: ${displayValue}`);
        } else {
            console.log(`❌ ${varName}: NÃO DEFINIDA`);
            allOk = false;
        }
    }
    
    if (allOk) {
        console.log('');
        console.log('🎉 TODAS AS VARIÁVEIS NECESSÁRIAS ESTÃO PRESENTES!');
        console.log('✅ O serviço pode ser iniciado agora');
    } else {
        console.log('❌ ALGUMAS VARIÁVEIS AINDA FALTANDO');
        process.exit(1);
    }
    
} catch (error) {
    console.log('❌ ERRO:', error.message);
    process.exit(1);
}
EOF

# Executar teste
echo ""
echo "=== RESULTADO DO TESTE ==="
if sudo -u samureye NODE_ENV=development node test-env-complete.mjs; then
    echo ""
    log "✅ TESTE: Todas as variáveis carregaram corretamente"
else
    echo ""
    log "❌ TESTE: Ainda há problemas com as variáveis"
    rm -f test-env-complete.mjs
    exit 1
fi

# Limpeza
rm -f test-env-complete.mjs

# 7. Iniciar serviço
log "🚀 Iniciando serviço com novas variáveis..."
systemctl start samureye-app

# Aguardar um pouco
sleep 5

# 8. Verificar resultado
echo ""
echo "=== STATUS FINAL ==="
if systemctl is-active --quiet samureye-app; then
    log "✅ SERVIÇO INICIADO COM SUCESSO!"
    echo "✅ Status: $(systemctl is-active samureye-app)"
    echo ""
    echo "🌐 URLS DISPONÍVEIS:"
    echo "  https://samureye.com.br"
    echo "  https://app.samureye.com.br"
    echo "  https://api.samureye.com.br"
    echo ""
    echo "📋 COMANDOS ÚTEIS:"
    echo "  systemctl status samureye-app"
    echo "  journalctl -u samureye-app -f"
    echo "  curl -s http://localhost:5000/api/health | jq"
else
    log "❌ SERVIÇO AINDA COM PROBLEMAS"
    echo ""
    echo "=== LOGS DE ERRO ==="
    journalctl -u samureye-app --no-pager -n 15
fi

echo ""
echo "================== RESUMO =================="
log "🔧 Variáveis de ambiente atualizadas"
log "📄 Arquivo: $ETC_DIR/.env"
log "💾 Backup: $ETC_DIR/.env.backup.*"
log "🎯 REPLIT_DOMAINS adicionado"
log "🎯 REPL_ID adicionado"
log "✅ Configuração completa"
echo "============================================="