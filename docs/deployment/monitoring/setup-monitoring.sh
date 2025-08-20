#!/bin/bash
# Script para configuração de monitoramento e logs para SamurEye
# Execute em todos os servidores

set -e

echo "📊 Configurando monitoramento e logs para SamurEye..."

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Este script deve ser executado como root (sudo)"
fi

# Detectar servidor baseado no hostname
HOSTNAME=$(hostname)
if [[ $HOSTNAME == *"vlxsam01"* ]]; then
    SERVER_TYPE="gateway"
elif [[ $HOSTNAME == *"vlxsam02"* ]]; then
    SERVER_TYPE="app"
elif [[ $HOSTNAME == *"vlxsam03"* ]]; then
    SERVER_TYPE="database"
elif [[ $HOSTNAME == *"vlxsam04"* ]]; then
    SERVER_TYPE="collector"
else
    echo "Tipo de servidor não detectado. Escolha:"
    echo "1) Gateway (vlxsam01)"
    echo "2) App (vlxsam02)"
    echo "3) Database (vlxsam03)"
    echo "4) Collector (vlxsam04)"
    read -p "Digite sua escolha (1-4): " choice
    case $choice in
        1) SERVER_TYPE="gateway" ;;
        2) SERVER_TYPE="app" ;;
        3) SERVER_TYPE="database" ;;
        4) SERVER_TYPE="collector" ;;
        *) error "Opção inválida" ;;
    esac
fi

log "Configurando monitoramento para servidor tipo: $SERVER_TYPE"

# Instalar pacotes básicos de monitoramento
log "Instalando ferramentas de monitoramento..."
apt update
apt install -y htop iotop nethogs sysstat rsyslog logrotate curl jq

# Configurar rsyslog para centralização
configure_centralized_logging() {
    log "Configurando rsyslog para logs centralizados..."
    
    # Backup da configuração original
    cp /etc/rsyslog.conf /etc/rsyslog.conf.bak
    
    # Configuração para envio para servidor central (vlxsam03)
    cat >> /etc/rsyslog.conf << 'EOF'

# SamurEye Centralized Logging
# Enviar logs para servidor central
*.* @@172.24.1.153:514

# Log local para SamurEye
$template SamurEyeFormat,"%TIMESTAMP% %HOSTNAME% %syslogtag%%msg%\n"
if $programname startswith 'samureye' then /var/log/samureye/system.log;SamurEyeFormat
& stop
EOF
    
    # Criar diretório de logs
    mkdir -p /var/log/samureye
    
    # Reiniciar rsyslog
    systemctl restart rsyslog
}

# Configurar monitoramento específico por tipo de servidor
case $SERVER_TYPE in
    "gateway")
        configure_gateway_monitoring
        ;;
    "app")
        configure_app_monitoring
        ;;
    "database")
        configure_database_monitoring
        ;;
    "collector")
        configure_collector_monitoring
        ;;
esac

configure_gateway_monitoring() {
    log "Configurando monitoramento para Gateway (NGINX)..."
    
    # Script de monitoramento do NGINX
    cat > /opt/monitor-nginx.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/samureye/nginx-monitor.log"
NGINX_ACCESS_LOG="/var/log/nginx/samureye-app.access.log"
NGINX_ERROR_LOG="/var/log/nginx/samureye-app.error.log"

# Função para enviar para FortiSIEM via CEF
send_to_fortisiem() {
    local message="$1"
    local severity="$2"
    
    # CEF Format: CEF:Version|Device Vendor|Device Product|Device Version|Signature ID|Name|Severity|Extension
    cef_message="CEF:0|SamurEye|Gateway|1.0|nginx-monitor|NGINX Monitoring|$severity|msg=$message"
    
    # Enviar via logger (será capturado pelo rsyslog)
    logger -p local0.info "$cef_message"
}

# Verificar status do NGINX
if ! systemctl is-active --quiet nginx; then
    send_to_fortisiem "NGINX service is down" "High"
    echo "$(date): ERROR: NGINX is down" >> $LOG_FILE
    systemctl start nginx
else
    echo "$(date): NGINX is running" >> $LOG_FILE
fi

# Verificar rate limiting
rate_limit_errors=$(tail -100 $NGINX_ERROR_LOG | grep -c "limiting requests" || echo "0")
if [ $rate_limit_errors -gt 10 ]; then
    send_to_fortisiem "High rate limiting activity detected: $rate_limit_errors events" "Medium"
fi

# Verificar erros 5xx
server_errors=$(tail -1000 $NGINX_ACCESS_LOG | grep -c " 5[0-9][0-9] " || echo "0")
if [ $server_errors -gt 50 ]; then
    send_to_fortisiem "High number of 5xx errors: $server_errors" "High"
fi

# Verificar erros 4xx suspeitos
client_errors=$(tail -1000 $NGINX_ACCESS_LOG | grep -c " 4[0-9][0-9] " || echo "0")
if [ $client_errors -gt 100 ]; then
    send_to_fortisiem "High number of 4xx errors: $client_errors" "Medium"
fi

# Verificar espaço em disco
disk_usage=$(df /var/log | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $disk_usage -gt 85 ]; then
    send_to_fortisiem "High disk usage on log partition: ${disk_usage}%" "High"
fi

# Estatísticas de conexões
connections=$(ss -ant | grep :443 | wc -l)
echo "$(date): Active HTTPS connections: $connections" >> $LOG_FILE

if [ $connections -gt 1000 ]; then
    send_to_fortisiem "High number of HTTPS connections: $connections" "Medium"
fi
EOF
    
    chmod +x /opt/monitor-nginx.sh
    
    # Configurar cron para monitoramento
    (crontab -l 2>/dev/null; echo "*/5 * * * * /opt/monitor-nginx.sh") | crontab -
    
    # Configurar fail2ban para logs estruturados
    cat > /etc/fail2ban/action.d/fortisiem.conf << 'EOF'
[Definition]
actionstart = 
actionstop = 
actioncheck = 
actionban = logger -p local0.warn "CEF:0|SamurEye|Gateway|1.0|fail2ban-ban|IP Banned by Fail2ban|High|src=<ip> msg=IP banned for <failures> failures in <name> jail"
actionunban = logger -p local0.info "CEF:0|SamurEye|Gateway|1.0|fail2ban-unban|IP Unbanned by Fail2ban|Low|src=<ip> msg=IP unbanned from <name> jail"
EOF
    
    # Atualizar jails do fail2ban para usar ação do FortiSIEM
    sed -i '/^action = /c\action = %(action_)s\n         fortisiem' /etc/fail2ban/jail.local
    systemctl restart fail2ban
}

configure_app_monitoring() {
    log "Configurando monitoramento para Application Server..."
    
    # Script de monitoramento da aplicação
    cat > /opt/monitor-app.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/samureye/app-monitor.log"

send_to_fortisiem() {
    local message="$1"
    local severity="$2"
    cef_message="CEF:0|SamurEye|AppServer|1.0|app-monitor|Application Monitoring|$severity|msg=$message"
    logger -p local0.info "$cef_message"
}

# Verificar PM2 processes
if command -v pm2 &> /dev/null; then
    pm2_status=$(pm2 jlist | jq -r '.[] | select(.pm2_env.status != "online") | .name' 2>/dev/null)
    if [ -n "$pm2_status" ]; then
        send_to_fortisiem "PM2 processes not online: $pm2_status" "High"
        echo "$(date): ERROR: PM2 processes down: $pm2_status" >> $LOG_FILE
        pm2 restart all
    else
        echo "$(date): All PM2 processes online" >> $LOG_FILE
    fi
fi

# Verificar API health
if curl -sf http://localhost:3000/api/health > /dev/null; then
    echo "$(date): API health check OK" >> $LOG_FILE
else
    send_to_fortisiem "API health check failed" "High"
    echo "$(date): ERROR: API health check failed" >> $LOG_FILE
fi

# Verificar scanner service
if curl -sf http://localhost:3001/health > /dev/null; then
    echo "$(date): Scanner service health check OK" >> $LOG_FILE
else
    send_to_fortisiem "Scanner service health check failed" "High"
    echo "$(date): ERROR: Scanner service health check failed" >> $LOG_FILE
fi

# Verificar uso de memória
memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [ $memory_usage -gt 85 ]; then
    send_to_fortisiem "High memory usage: ${memory_usage}%" "Medium"
fi

# Verificar load average
load_avg=$(cat /proc/loadavg | cut -d' ' -f1)
load_threshold="4.0"
if (( $(echo "$load_avg > $load_threshold" | bc -l) )); then
    send_to_fortisiem "High load average: $load_avg" "Medium"
fi

# Verificar conexões de banco de dados (para vlxsam03)
db_connections=$(netstat -an | grep :5432 | grep ESTABLISHED | wc -l)
echo "$(date): Database connections: $db_connections" >> $LOG_FILE

if [ $db_connections -gt 100 ]; then
    send_to_fortisiem "High number of database connections: $db_connections" "Medium"
fi
EOF
    
    chmod +x /opt/monitor-app.sh
    (crontab -l 2>/dev/null; echo "*/5 * * * * /opt/monitor-app.sh") | crontab -
    
    # Configurar monitoramento de logs da aplicação
    cat > /opt/parse-app-logs.sh << 'EOF'
#!/bin/bash

APP_LOG="/var/log/samureye/app.log"
LAST_CHECK_FILE="/tmp/app-log-lastcheck"

# Obter timestamp da última verificação
if [ -f "$LAST_CHECK_FILE" ]; then
    LAST_CHECK=$(cat $LAST_CHECK_FILE)
else
    LAST_CHECK=$(date -d "1 minute ago" '+%Y-%m-%d %H:%M:%S')
fi

# Atualizar timestamp atual
date '+%Y-%m-%d %H:%M:%S' > $LAST_CHECK_FILE

# Verificar erros desde a última verificação
if [ -f "$APP_LOG" ]; then
    # Buscar por padrões de erro
    errors=$(awk -v last_check="$LAST_CHECK" '
        $1 " " $2 >= last_check {
            if (/ERROR|CRITICAL|FATAL/) print $0
        }' $APP_LOG)
    
    if [ -n "$errors" ]; then
        while IFS= read -r error_line; do
            cef_message="CEF:0|SamurEye|AppServer|1.0|app-error|Application Error|High|msg=$error_line"
            logger -p local0.warn "$cef_message"
        done <<< "$errors"
    fi
    
    # Buscar por padrões de segurança
    security_events=$(awk -v last_check="$LAST_CHECK" '
        $1 " " $2 >= last_check {
            if (/Unauthorized|Authentication failed|Invalid token|CSRF/) print $0
        }' $APP_LOG)
    
    if [ -n "$security_events" ]; then
        while IFS= read -r security_line; do
            cef_message="CEF:0|SamurEye|AppServer|1.0|security-event|Security Event|High|msg=$security_line"
            logger -p local0.warn "$cef_message"
        done <<< "$security_events"
    fi
fi
EOF
    
    chmod +x /opt/parse-app-logs.sh
    (crontab -l 2>/dev/null; echo "* * * * * /opt/parse-app-logs.sh") | crontab -
}

configure_database_monitoring() {
    log "Configurando monitoramento para Database Server..."
    
    # Script de monitoramento do PostgreSQL
    cat > /opt/monitor-database.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/samureye/db-monitor.log"

send_to_fortisiem() {
    local message="$1"
    local severity="$2"
    cef_message="CEF:0|SamurEye|DatabaseServer|1.0|db-monitor|Database Monitoring|$severity|msg=$message"
    logger -p local0.info "$cef_message"
}

# Verificar status do PostgreSQL
if ! systemctl is-active --quiet postgresql; then
    send_to_fortisiem "PostgreSQL service is down" "Critical"
    echo "$(date): ERROR: PostgreSQL is down" >> $LOG_FILE
    systemctl start postgresql
else
    echo "$(date): PostgreSQL is running" >> $LOG_FILE
fi

# Verificar status do Redis
if ! systemctl is-active --quiet redis-server; then
    send_to_fortisiem "Redis service is down" "High"
    echo "$(date): ERROR: Redis is down" >> $LOG_FILE
    systemctl start redis-server
else
    echo "$(date): Redis is running" >> $LOG_FILE
fi

# Verificar status do MinIO
if ! systemctl is-active --quiet minio; then
    send_to_fortisiem "MinIO service is down" "High"
    echo "$(date): ERROR: MinIO is down" >> $LOG_FILE
    systemctl start minio
else
    echo "$(date): MinIO is running" >> $LOG_FILE
fi

# Verificar conexões do PostgreSQL
pg_connections=$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | xargs)
if [ -n "$pg_connections" ]; then
    echo "$(date): Active PostgreSQL connections: $pg_connections" >> $LOG_FILE
    if [ $pg_connections -gt 150 ]; then
        send_to_fortisiem "High number of PostgreSQL connections: $pg_connections" "Medium"
    fi
fi

# Verificar tamanho do banco de dados
db_size=$(sudo -u postgres psql -t -c "SELECT pg_size_pretty(pg_database_size('samureye'));" 2>/dev/null | xargs)
if [ -n "$db_size" ]; then
    echo "$(date): Database size: $db_size" >> $LOG_FILE
fi

# Verificar replicação (se configurada)
replication_lag=$(sudo -u postgres psql -t -c "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));" 2>/dev/null | xargs)
if [ -n "$replication_lag" ] && [ "$replication_lag" != "" ]; then
    if (( $(echo "$replication_lag > 60" | bc -l) )); then
        send_to_fortisiem "High replication lag: ${replication_lag}s" "Medium"
    fi
fi

# Verificar espaço em disco para dados
data_disk_usage=$(df /var/lib/postgresql | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $data_disk_usage -gt 85 ]; then
    send_to_fortisiem "High disk usage on data partition: ${data_disk_usage}%" "High"
fi

# Verificar backup mais recente
if [ -d "/opt/backup" ]; then
    latest_backup=$(ls -t /opt/backup/postgresql_*.sql.gz 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
        backup_age=$(( ($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600 ))
        echo "$(date): Latest backup age: ${backup_age}h" >> $LOG_FILE
        if [ $backup_age -gt 36 ]; then
            send_to_fortisiem "Backup is older than 36 hours: ${backup_age}h" "Medium"
        fi
    else
        send_to_fortisiem "No recent backups found" "High"
    fi
fi
EOF
    
    chmod +x /opt/monitor-database.sh
    (crontab -l 2>/dev/null; echo "*/5 * * * * /opt/monitor-database.sh") | crontab -
    
    # Configurar servidor de logs centralizado
    cat >> /etc/rsyslog.conf << 'EOF'

# SamurEye Log Server Configuration
$ModLoad imudp
$UDPServerRun 514
$UDPServerAddress 0.0.0.0

# Template para logs do SamurEye
$template SamurEyeLogFormat,"/var/log/samureye/centralized/%HOSTNAME%/%PROGRAMNAME%.log"
if $fromhost-ip startswith '192.168.' or $fromhost-ip startswith '10.' or $fromhost-ip startswith '172.' then ?SamurEyeLogFormat
& stop
EOF
    
    mkdir -p /var/log/samureye/centralized
    systemctl restart rsyslog
}

configure_collector_monitoring() {
    log "Configurando monitoramento para Collector..."
    
    # Script de monitoramento do collector
    cat > /opt/monitor-collector.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/collector/monitor.log"

send_to_fortisiem() {
    local message="$1"
    local severity="$2"
    cef_message="CEF:0|SamurEye|Collector|1.0|collector-monitor|Collector Monitoring|$severity|msg=$message"
    logger -p local0.info "$cef_message"
}

# Verificar status do collector
if ! systemctl is-active --quiet samureye-collector; then
    send_to_fortisiem "SamurEye Collector service is down" "High"
    echo "$(date): ERROR: Collector service is down" >> $LOG_FILE
    systemctl start samureye-collector
else
    echo "$(date): Collector service is running" >> $LOG_FILE
fi

# Verificar conectividade com a API
if curl -sf --connect-timeout 5 https://api.samureye.com.br/health > /dev/null; then
    echo "$(date): API connectivity OK" >> $LOG_FILE
else
    send_to_fortisiem "Cannot reach SamurEye API" "High"
    echo "$(date): ERROR: Cannot reach API" >> $LOG_FILE
fi

# Verificar último heartbeat (se configurado)
if [ -f "/var/log/collector/collector.log" ]; then
    last_heartbeat=$(grep "Heartbeat sent" /var/log/collector/collector.log | tail -1 | cut -d' ' -f1-2)
    if [ -n "$last_heartbeat" ]; then
        heartbeat_age=$(( $(date +%s) - $(date -d "$last_heartbeat" +%s) ))
        if [ $heartbeat_age -gt 300 ]; then  # 5 minutos
            send_to_fortisiem "No heartbeat for ${heartbeat_age}s" "Medium"
        fi
    fi
fi

# Verificar ferramentas de scan
for tool in nmap nuclei; do
    if ! command -v $tool &> /dev/null; then
        send_to_fortisiem "Scan tool not available: $tool" "Medium"
    fi
done

# Verificar uso de recursos
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

echo "$(date): CPU: ${cpu_usage}%, Memory: ${memory_usage}%" >> $LOG_FILE

if (( $(echo "$cpu_usage > 80" | bc -l) )); then
    send_to_fortisiem "High CPU usage: ${cpu_usage}%" "Medium"
fi

if [ $memory_usage -gt 85 ]; then
    send_to_fortisiem "High memory usage: ${memory_usage}%" "Medium"
fi
EOF
    
    chmod +x /opt/monitor-collector.sh
    (crontab -l 2>/dev/null; echo "*/5 * * * * /opt/monitor-collector.sh") | crontab -
}

# Configurar logrotate comum
configure_logrotate() {
    log "Configurando logrotate para logs do SamurEye..."
    
    cat > /etc/logrotate.d/samureye-common << 'EOF'
/var/log/samureye/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 root root
    postrotate
        systemctl reload rsyslog
    endscript
}

/var/log/samureye/centralized/*/*.log {
    weekly
    missingok
    rotate 12
    compress
    delaycompress
    notifempty
    create 0644 root root
}
EOF
}

# Configurar monitoramento de sistema básico
configure_system_monitoring() {
    log "Configurando monitoramento básico do sistema..."
    
    # Habilitar coleta de estatísticas do sistema
    sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
    systemctl enable sysstat
    systemctl start sysstat
    
    # Script de alertas do sistema
    cat > /opt/system-alerts.sh << 'EOF'
#!/bin/bash

send_alert() {
    local message="$1"
    local severity="$2"
    cef_message="CEF:0|SamurEye|System|1.0|system-alert|System Alert|$severity|msg=$message"
    logger -p local0.warn "$cef_message"
}

# Verificar espaço em disco
df -h | awk 'NR>1 {
    usage = substr($5, 1, length($5)-1)
    if (usage > 85) {
        system("echo \"High disk usage on " $6 ": " $5 "\" | logger -p local0.warn")
    }
}'

# Verificar load average
load=$(cat /proc/loadavg | cut -d' ' -f1)
cpu_count=$(nproc)
load_threshold=$(echo "$cpu_count * 2" | bc)

if (( $(echo "$load > $load_threshold" | bc -l) )); then
    send_alert "High load average: $load (threshold: $load_threshold)" "Medium"
fi

# Verificar memória swap
swap_usage=$(free | grep Swap | awk '{if($2>0) printf "%.0f", $3/$2 * 100.0; else print 0}')
if [ $swap_usage -gt 50 ]; then
    send_alert "High swap usage: ${swap_usage}%" "Medium"
fi

# Verificar processos zumbis
zombies=$(ps aux | awk '{print $8}' | grep -c Z || echo 0)
if [ $zombies -gt 5 ]; then
    send_alert "High number of zombie processes: $zombies" "Low"
fi
EOF
    
    chmod +x /opt/system-alerts.sh
    (crontab -l 2>/dev/null; echo "*/10 * * * * /opt/system-alerts.sh") | crontab -
}

# Executar configurações
configure_centralized_logging
configure_logrotate
configure_system_monitoring

log "Configuração de monitoramento concluída para servidor $SERVER_TYPE!"
echo ""
echo "📊 RECURSOS CONFIGURADOS:"
echo "• Logs centralizados via rsyslog"
echo "• Monitoramento específico para $SERVER_TYPE"
echo "• Alertas via CEF para FortiSIEM"
echo "• Rotação automática de logs"
echo "• Coleta de estatísticas do sistema"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "• Configurar FortiSIEM para receber logs via UDP 514"
echo "• Ajustar thresholds de alertas conforme necessário"
echo "• Testar conectividade: logger 'Test message from $HOSTNAME'"
echo ""
echo "🔍 COMANDOS ÚTEIS:"
echo "• Verificar logs: tail -f /var/log/samureye/*.log"
echo "• Verificar rsyslog: systemctl status rsyslog"
echo "• Testar CEF: logger -p local0.info 'CEF:0|Test|Test|1.0|test|Test Message|Low|'"
echo ""
echo "✅ Monitoramento configurado com sucesso!"