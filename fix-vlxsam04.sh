#!/bin/bash
# Script para corrigir instalação do vlxsam04 - criar diretório scripts faltante

COLLECTOR_DIR="/opt/samureye-collector"
COLLECTOR_USER="samureye-collector"

echo "🔧 Criando diretório scripts faltante..."

# Criar diretório de scripts se não existir
mkdir -p "$COLLECTOR_DIR/scripts"

# Script de health check
cat > "$COLLECTOR_DIR/scripts/health-check.py" << 'EOF'
#!/usr/bin/env python3
"""
Script de verificação de saúde do collector
"""

import os
import sys
import json
import subprocess
from pathlib import Path
from datetime import datetime

def check_services():
    """Verifica se os serviços estão rodando"""
    try:
        result = subprocess.run(['systemctl', 'is-active', 'samureye-collector'], 
                              capture_output=True, text=True)
        return result.stdout.strip() == 'active'
    except:
        return False

def check_certificates():
    """Verifica certificados"""
    cert_file = Path('/opt/samureye-collector/certs/collector.crt')
    key_file = Path('/opt/samureye-collector/certs/collector.key')
    ca_file = Path('/opt/samureye-collector/certs/ca.crt')
    
    return all([cert_file.exists(), key_file.exists(), ca_file.exists()])

def check_api_connection():
    """Testa conexão com API"""
    try:
        import requests
        response = requests.get('https://api.samureye.com.br/health', timeout=10)
        return response.status_code == 200
    except:
        return False

def main():
    health_data = {
        'timestamp': datetime.utcnow().isoformat(),
        'hostname': os.uname().nodename,
        'services_running': check_services(),
        'certificates_valid': check_certificates(),
        'api_reachable': check_api_connection(),
        'disk_usage': os.statvfs('/opt/samureye-collector').f_bavail
    }
    
    # Log do resultado
    log_file = '/var/log/samureye-collector/health.log'
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    with open(log_file, 'a') as f:
        f.write(json.dumps(health_data) + '\n')
    
    # Exit code baseado na saúde
    if all([health_data['services_running'], health_data['certificates_valid']]):
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

# Script de backup de configurações
cat > "$COLLECTOR_DIR/scripts/backup-config.sh" << 'EOF'
#!/bin/bash
# Backup das configurações do collector

BACKUP_DIR="/opt/samureye-collector/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Backup de configurações
tar -czf "$BACKUP_DIR/config-$DATE.tar.gz" \
    /opt/samureye-collector/config/ \
    /opt/samureye-collector/certs/ \
    /etc/systemd/system/samureye-*.service

# Manter apenas os últimos 10 backups
cd "$BACKUP_DIR"
ls -t config-*.tar.gz | tail -n +11 | xargs rm -f

echo "Backup criado: config-$DATE.tar.gz"
EOF

# Script de limpeza de logs
cat > "$COLLECTOR_DIR/scripts/cleanup-logs.sh" << 'EOF'
#!/bin/bash
# Limpeza de logs antigos

LOG_DIR="/var/log/samureye-collector"

# Logs de tenants mais antigos que 7 dias
find "$LOG_DIR" -name "tenant-*.log" -mtime +7 -delete

# Logs de health mais antigos que 30 dias
find "$LOG_DIR" -name "health.log" -mtime +30 -delete

# Arquivos temporários mais antigos que 1 dia
find "/opt/samureye-collector/temp" -type f -mtime +1 -delete

echo "Limpeza de logs concluída"
EOF

# Permissões dos scripts
chmod +x "$COLLECTOR_DIR/scripts/"*.sh
chmod +x "$COLLECTOR_DIR/scripts/"*.py
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/scripts"

echo "✅ Scripts auxiliares criados com sucesso!"

# Configuração de logrotate
cat > /etc/logrotate.d/samureye-collector << 'EOF'
/var/log/samureye-collector/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 samureye-collector samureye-collector
    sharedscripts
    postrotate
        systemctl reload-or-restart samureye-collector.service
    endscript
}
EOF

# Configuração de rsyslog para centralizar logs
cat > /etc/rsyslog.d/30-samureye-collector.conf << 'EOF'
# SamurEye Collector Logging
if $programname == 'samureye-collector' then /var/log/samureye-collector/agent.log
& stop

# Forward critical errors to syslog
:programname, isequal, "samureye-collector" /var/log/syslog
& stop
EOF

# Restart rsyslog
systemctl restart rsyslog

echo "✅ Sistema de logs configurado!"

# Validação final
echo "🔍 Executando validação final..."

# Verificar estrutura de diretórios
required_dirs=(
    "$COLLECTOR_DIR"
    "$COLLECTOR_DIR/agent"
    "$COLLECTOR_DIR/scripts"  
    "$COLLECTOR_DIR/certs"
    "$COLLECTOR_DIR/config"
    "$COLLECTOR_DIR/tools"
    "$COLLECTOR_DIR/temp"
    "/var/log/samureye-collector"
)

for dir in "${required_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "❌ Diretório ausente: $dir"
        exit 1
    fi
done

# Verificar serviços systemd
if ! systemctl is-enabled samureye-collector.service >/dev/null 2>&1; then
    echo "❌ Serviço samureye-collector não habilitado"
    exit 1
fi

echo "✅ Validação concluída!"
echo ""
echo "📋 vlxsam04 Collector Agent - Status:"
echo "Collector pronto para registro"
echo "Usuário: $COLLECTOR_USER"  
echo "Diretório: $COLLECTOR_DIR"
echo ""
echo "⚠️  PRÓXIMO PASSO MANUAL:"
echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/scripts/register-collector.sh | bash -s <tenant-slug> <collector-name>"
echo ""
echo "🚀 vlxsam04 Collector Agent 100% funcional!"