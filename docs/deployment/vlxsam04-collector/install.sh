#!/bin/bash
# SamurEye Collector Installation Script (vlxsam04)
# Execute como root: sudo bash install.sh

set -e

echo "🚀 Iniciando instalação do SamurEye Collector (vlxsam04)..."

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para log
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

# Variáveis
COLLECTOR_USER="collector"
COLLECTOR_DIR="/opt/collector"
LOG_DIR="/var/log/collector"

# Verificar conectividade
log "Verificando conectividade com a internet..."
if ! ping -c 1 google.com &> /dev/null; then
    error "Sem conectividade com a internet"
fi

# Atualizar sistema
log "Atualizando sistema..."
apt update && apt upgrade -y

# Instalar pacotes essenciais
log "Instalando pacotes essenciais..."
apt install -y python3 python3-pip python3-venv curl wget git nmap masscan nuclei ufw htop unzip software-properties-common build-essential

# Configurar timezone
log "Configurando timezone para America/Sao_Paulo..."
timedatectl set-timezone America/Sao_Paulo

# Configurar firewall UFW (apenas SSH e HTTPS para comunicação)
log "Configurando firewall UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 443/tcp  # HTTPS para comunicação com a plataforma
ufw --force enable

# Instalar Nuclei templates
log "Instalando Nuclei templates..."
nuclei -update-templates

# Criar usuário para collector
log "Criando usuário para collector..."
if ! id "$COLLECTOR_USER" &>/dev/null; then
    useradd -m -s /bin/bash $COLLECTOR_USER
    usermod -aG sudo $COLLECTOR_USER
    log "Usuário $COLLECTOR_USER criado"
else
    log "Usuário $COLLECTOR_USER já existe"
fi

# Criar diretórios
log "Criando diretórios do collector..."
mkdir -p $COLLECTOR_DIR
mkdir -p $LOG_DIR
mkdir -p /opt/backup
mkdir -p /etc/collector

# Definir permissões
chown -R $COLLECTOR_USER:$COLLECTOR_USER $COLLECTOR_DIR
chown -R $COLLECTOR_USER:$COLLECTOR_USER $LOG_DIR
chmod 755 $COLLECTOR_DIR
chmod 755 $LOG_DIR

# Instalar dependências Python
log "Instalando dependências Python..."
pip3 install requests psutil schedule websocket-client cryptography

# Criar ambiente virtual para o collector
log "Criando ambiente virtual Python..."
sudo -u $COLLECTOR_USER python3 -m venv $COLLECTOR_DIR/venv
sudo -u $COLLECTOR_USER $COLLECTOR_DIR/venv/bin/pip install --upgrade pip
sudo -u $COLLECTOR_USER $COLLECTOR_DIR/venv/bin/pip install requests psutil schedule websocket-client cryptography

# Criar script principal do collector
log "Criando script principal do collector..."
cat > $COLLECTOR_DIR/collector.py << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent
Agente de coleta para a plataforma SamurEye BAS
"""

import os
import sys
import json
import time
import subprocess
import requests
import psutil
import schedule
import logging
import socket
import platform
from datetime import datetime
from threading import Thread
import websocket

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/collector/collector.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class SamurEyeCollector:
    def __init__(self):
        self.config = self.load_config()
        self.collector_id = self.config.get('collector_id')
        self.api_endpoint = self.config.get('api_endpoint', 'https://api.samureye.com.br')
        self.enrollment_token = self.config.get('enrollment_token')
        self.api_key = self.config.get('api_key')
        self.ws_endpoint = self.config.get('ws_endpoint', 'wss://app.samureye.com.br/ws')
        self.ws = None
        
        # Informações do sistema
        self.hostname = socket.gethostname()
        self.ip_address = self.get_local_ip()
        self.version = "1.0.0"
        
        # Estado do collector
        self.is_enrolled = bool(self.collector_id and self.api_key)
        self.last_heartbeat = None
        
    def load_config(self):
        """Carrega configuração do arquivo"""
        config_file = '/etc/collector/config.json'
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                return json.load(f)
        return {}
    
    def save_config(self):
        """Salva configuração no arquivo"""
        config_file = '/etc/collector/config.json'
        os.makedirs(os.path.dirname(config_file), exist_ok=True)
        with open(config_file, 'w') as f:
            json.dump(self.config, f, indent=2)
        os.chmod(config_file, 0o600)
    
    def get_local_ip(self):
        """Obtém IP local do collector"""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("8.8.8.8", 80))
                return s.getsockname()[0]
        except:
            return "127.0.0.1"
    
    def enroll(self):
        """Processo de enrollment do collector"""
        if not self.enrollment_token:
            logger.error("Token de enrollment não configurado")
            return False
        
        try:
            data = {
                'enrollment_token': self.enrollment_token,
                'hostname': self.hostname,
                'ip_address': self.ip_address,
                'version': self.version,
                'os_info': platform.uname()._asdict()
            }
            
            response = requests.post(
                f"{self.api_endpoint}/api/collectors/enroll",
                json=data,
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                self.collector_id = result.get('collector_id')
                self.api_key = result.get('api_key')
                
                # Atualizar configuração
                self.config.update({
                    'collector_id': self.collector_id,
                    'api_key': self.api_key,
                    'enrolled_at': datetime.now().isoformat()
                })
                self.save_config()
                
                self.is_enrolled = True
                logger.info(f"Collector enrolled successfully: {self.collector_id}")
                return True
            else:
                logger.error(f"Enrollment failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Enrollment error: {e}")
            return False
    
    def get_system_telemetry(self):
        """Coleta telemetria do sistema"""
        try:
            # CPU Usage
            cpu_usage = psutil.cpu_percent(interval=1)
            
            # Memory Usage
            memory = psutil.virtual_memory()
            memory_usage = memory.percent
            
            # Disk Usage
            disk = psutil.disk_usage('/')
            disk_usage = (disk.used / disk.total) * 100
            
            # Network throughput
            network_io = psutil.net_io_counters()
            
            # Running processes
            processes = []
            for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']):
                try:
                    processes.append(proc.info)
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass
            
            # Sort by CPU usage and get top 10
            processes.sort(key=lambda x: x['cpu_percent'] or 0, reverse=True)
            top_processes = processes[:10]
            
            return {
                'timestamp': datetime.now().isoformat(),
                'cpu_usage': cpu_usage,
                'memory_usage': memory_usage,
                'disk_usage': disk_usage,
                'network_throughput': {
                    'bytes_sent': network_io.bytes_sent,
                    'bytes_recv': network_io.bytes_recv,
                    'packets_sent': network_io.packets_sent,
                    'packets_recv': network_io.packets_recv
                },
                'processes': top_processes
            }
        except Exception as e:
            logger.error(f"Error collecting telemetry: {e}")
            return None
    
    def send_telemetry(self):
        """Envia telemetria para a plataforma"""
        if not self.is_enrolled:
            logger.warning("Collector not enrolled, skipping telemetry")
            return
        
        telemetry = self.get_system_telemetry()
        if not telemetry:
            return
        
        try:
            headers = {
                'Authorization': f'Bearer {self.api_key}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                f"{self.api_endpoint}/api/collectors/{self.collector_id}/telemetry",
                json=telemetry,
                headers=headers,
                timeout=30
            )
            
            if response.status_code == 200:
                logger.debug("Telemetry sent successfully")
            else:
                logger.warning(f"Failed to send telemetry: {response.status_code}")
                
        except Exception as e:
            logger.error(f"Error sending telemetry: {e}")
    
    def send_heartbeat(self):
        """Envia heartbeat para manter conexão ativa"""
        if not self.is_enrolled:
            return
        
        try:
            headers = {
                'Authorization': f'Bearer {self.api_key}',
                'Content-Type': 'application/json'
            }
            
            data = {
                'timestamp': datetime.now().isoformat(),
                'status': 'online'
            }
            
            response = requests.post(
                f"{self.api_endpoint}/api/collectors/{self.collector_id}/heartbeat",
                json=data,
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 200:
                self.last_heartbeat = datetime.now()
                logger.debug("Heartbeat sent successfully")
            else:
                logger.warning(f"Heartbeat failed: {response.status_code}")
                
        except Exception as e:
            logger.error(f"Error sending heartbeat: {e}")
    
    def execute_journey(self, journey_data):
        """Executa jornada de teste"""
        journey_id = journey_data.get('journey_id')
        journey_type = journey_data.get('type')
        config = journey_data.get('config', {})
        
        logger.info(f"Executing journey {journey_id} of type {journey_type}")
        
        try:
            if journey_type == 'attack_surface':
                result = self.execute_attack_surface_journey(config)
            elif journey_type == 'ad_hygiene':
                result = self.execute_ad_hygiene_journey(config)
            elif journey_type == 'edr_testing':
                result = self.execute_edr_testing_journey(config)
            else:
                raise ValueError(f"Unknown journey type: {journey_type}")
            
            # Enviar resultado
            self.send_journey_result(journey_id, 'completed', result)
            
        except Exception as e:
            logger.error(f"Journey execution failed: {e}")
            self.send_journey_result(journey_id, 'failed', {'error': str(e)})
    
    def execute_attack_surface_journey(self, config):
        """Executa jornada de Attack Surface"""
        targets = config.get('targets', [])
        scan_type = config.get('scan_type', 'nmap')
        
        if scan_type == 'nmap':
            return self.run_nmap_scan(targets, config)
        elif scan_type == 'nuclei':
            return self.run_nuclei_scan(targets, config)
        else:
            raise ValueError(f"Unknown scan type: {scan_type}")
    
    def execute_ad_hygiene_journey(self, config):
        """Executa jornada de AD/LDAP Hygiene"""
        # Implementar verificações de higiene do AD
        return {"message": "AD Hygiene journey executed", "config": config}
    
    def execute_edr_testing_journey(self, config):
        """Executa jornada de teste de EDR/AV"""
        # Implementar testes de EDR/AV
        return {"message": "EDR Testing journey executed", "config": config}
    
    def run_nmap_scan(self, targets, config):
        """Executa scan com Nmap"""
        try:
            cmd = ['nmap', '-sS', '-sV', '--script=default,vuln']
            
            # Adicionar opções do config
            if config.get('ports'):
                cmd.extend(['-p', config['ports']])
            if config.get('timing'):
                cmd.append(f'-T{config["timing"]}')
            
            cmd.extend(targets)
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
            
            return {
                'command': ' '.join(cmd),
                'exit_code': result.returncode,
                'stdout': result.stdout,
                'stderr': result.stderr
            }
        except Exception as e:
            raise Exception(f"Nmap scan failed: {e}")
    
    def run_nuclei_scan(self, targets, config):
        """Executa scan com Nuclei"""
        try:
            cmd = ['nuclei', '-l', '-']
            
            # Adicionar templates
            templates = config.get('templates', ['cves', 'vulnerabilities'])
            cmd.extend(['-t', ','.join(templates)])
            
            # Adicionar severidade
            if config.get('severity'):
                cmd.extend(['-severity', config['severity']])
            
            cmd.extend(['-j'])  # JSON output
            
            # Executar com targets via stdin
            targets_input = '\n'.join(targets)
            result = subprocess.run(
                cmd, 
                input=targets_input, 
                capture_output=True, 
                text=True, 
                timeout=3600
            )
            
            return {
                'command': ' '.join(cmd),
                'exit_code': result.returncode,
                'stdout': result.stdout,
                'stderr': result.stderr
            }
        except Exception as e:
            raise Exception(f"Nuclei scan failed: {e}")
    
    def send_journey_result(self, journey_id, status, result):
        """Envia resultado da jornada"""
        try:
            headers = {
                'Authorization': f'Bearer {self.api_key}',
                'Content-Type': 'application/json'
            }
            
            data = {
                'status': status,
                'result': result,
                'completed_at': datetime.now().isoformat()
            }
            
            response = requests.patch(
                f"{self.api_endpoint}/api/journeys/{journey_id}/result",
                json=data,
                headers=headers,
                timeout=30
            )
            
            if response.status_code == 200:
                logger.info(f"Journey result sent for {journey_id}")
            else:
                logger.error(f"Failed to send journey result: {response.status_code}")
                
        except Exception as e:
            logger.error(f"Error sending journey result: {e}")
    
    def connect_websocket(self):
        """Conecta ao WebSocket para comandos em tempo real"""
        if not self.is_enrolled:
            return
        
        try:
            def on_message(ws, message):
                try:
                    data = json.loads(message)
                    command_type = data.get('type')
                    
                    if command_type == 'execute_journey':
                        Thread(target=self.execute_journey, args=(data.get('data'),)).start()
                    elif command_type == 'ping':
                        ws.send(json.dumps({'type': 'pong', 'timestamp': datetime.now().isoformat()}))
                        
                except Exception as e:
                    logger.error(f"WebSocket message error: {e}")
            
            def on_error(ws, error):
                logger.error(f"WebSocket error: {error}")
            
            def on_close(ws, close_status_code, close_msg):
                logger.info("WebSocket connection closed")
            
            def on_open(ws):
                logger.info("WebSocket connection opened")
                # Enviar identificação
                ws.send(json.dumps({
                    'type': 'identify',
                    'collector_id': self.collector_id,
                    'api_key': self.api_key
                }))
            
            self.ws = websocket.WebSocketApp(
                f"{self.ws_endpoint}?collector_id={self.collector_id}",
                header=[f"Authorization: Bearer {self.api_key}"],
                on_open=on_open,
                on_message=on_message,
                on_error=on_error,
                on_close=on_close
            )
            
            self.ws.run_forever()
            
        except Exception as e:
            logger.error(f"WebSocket connection error: {e}")
    
    def run(self):
        """Loop principal do collector"""
        logger.info("Starting SamurEye Collector")
        
        # Fazer enrollment se necessário
        if not self.is_enrolled:
            if not self.enroll():
                logger.error("Failed to enroll collector")
                return
        
        # Configurar schedules
        schedule.every(30).seconds.do(self.send_heartbeat)
        schedule.every(1).minutes.do(self.send_telemetry)
        
        # Conectar WebSocket em thread separada
        ws_thread = Thread(target=self.connect_websocket)
        ws_thread.daemon = True
        ws_thread.start()
        
        # Loop principal
        try:
            while True:
                schedule.run_pending()
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("Collector stopped by user")
        except Exception as e:
            logger.error(f"Collector error: {e}")

if __name__ == "__main__":
    collector = SamurEyeCollector()
    collector.run()
EOF

chmod +x $COLLECTOR_DIR/collector.py
chown $COLLECTOR_USER:$COLLECTOR_USER $COLLECTOR_DIR/collector.py

# Criar arquivo de configuração template
cat > /etc/collector/config.json.template << 'EOF'
{
  "api_endpoint": "https://api.samureye.com.br",
  "ws_endpoint": "wss://app.samureye.com.br/ws",
  "enrollment_token": "your_enrollment_token_here",
  "log_level": "INFO",
  "telemetry_interval": 60,
  "heartbeat_interval": 30
}
EOF

chmod 600 /etc/collector/config.json.template

# Criar systemd service
log "Criando systemd service..."
cat > /etc/systemd/system/samureye-collector.service << 'EOF'
[Unit]
Description=SamurEye Collector Agent
After=network.target
Wants=network.target

[Service]
Type=simple
User=collector
WorkingDirectory=/opt/collector
ExecStart=/opt/collector/venv/bin/python /opt/collector/collector.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Environment
Environment=PYTHONPATH=/opt/collector
Environment=PYTHONUNBUFFERED=1

# Security
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/collector /var/log/collector /etc/collector

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable samureye-collector

# Configurar logrotate
log "Configurando logrotate..."
cat > /etc/logrotate.d/samureye-collector << 'EOF'
/var/log/collector/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 collector collector
    postrotate
        systemctl restart samureye-collector
    endscript
}
EOF

# Script de status e diagnóstico
cat > /opt/collector-status.sh << 'EOF'
#!/bin/bash

echo "=== SamurEye Collector Status ==="
echo "Service Status:"
systemctl status samureye-collector --no-pager

echo ""
echo "Recent Logs:"
journalctl -u samureye-collector --no-pager -n 20

echo ""
echo "Configuration:"
if [ -f /etc/collector/config.json ]; then
    echo "✓ Config file exists"
    python3 -m json.tool /etc/collector/config.json | grep -v token | grep -v api_key
else
    echo "✗ Config file missing"
fi

echo ""
echo "Network Connectivity:"
if curl -s --connect-timeout 5 https://api.samureye.com.br/health > /dev/null; then
    echo "✓ API connectivity OK"
else
    echo "✗ API connectivity FAILED"
fi

echo ""
echo "Tools Check:"
command -v nmap >/dev/null 2>&1 && echo "✓ nmap available" || echo "✗ nmap missing"
command -v nuclei >/dev/null 2>&1 && echo "✓ nuclei available" || echo "✗ nuclei missing"

echo ""
echo "System Resources:"
echo "CPU: $(cat /proc/loadavg | cut -d' ' -f1)"
echo "Memory: $(free -h | grep '^Mem:' | awk '{print $3"/"$2}')"
echo "Disk: $(df -h /opt | tail -1 | awk '{print $3"/"$2" ("$5" used)"}')"
EOF

chmod +x /opt/collector-status.sh

log "Configuração concluída!"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo ""
echo "1. Configurar arquivo de configuração:"
echo "   cp /etc/collector/config.json.template /etc/collector/config.json"
echo "   nano /etc/collector/config.json"
echo "   # Adicionar enrollment_token obtido da plataforma"
echo ""
echo "2. Iniciar o collector:"
echo "   systemctl start samureye-collector"
echo ""
echo "3. Verificar status:"
echo "   /opt/collector-status.sh"
echo "   journalctl -u samureye-collector -f"
echo ""
echo "4. Testar ferramentas:"
echo "   nmap --version"
echo "   nuclei -version"
echo ""
echo "🔗 Para obter o enrollment token:"
echo "   Acesse a plataforma SamurEye > Collectors > Adicionar Collector"
echo ""
echo "✅ Instalação do Collector concluída com sucesso!"