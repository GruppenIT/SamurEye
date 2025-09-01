#!/bin/bash

# vlxsam04 - Corrigir Configuração do Collector (Situação Real)
# Recriar configuração e serviço do collector

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-collector-config.sh"
fi

echo "🔧 vlxsam04 - CORRIGIR CONFIGURAÇÃO COLLECTOR"
echo "=============================================="
echo ""

# ============================================================================
# 1. DETECTAR SITUAÇÃO ATUAL
# ============================================================================

log "🔍 Detectando situação atual do collector..."

# Verificar se serviço existe
if systemctl list-unit-files | grep -q samureye-collector; then
    log "📋 Serviço samureye-collector encontrado"
    SERVICE_EXISTS=true
    
    if systemctl is-active --quiet samureye-collector; then
        log "✅ Serviço está ativo"
        systemctl stop samureye-collector
        log "⏹️ Serviço parado para reconfiguração"
    fi
else
    log "📋 Serviço samureye-collector não encontrado"
    SERVICE_EXISTS=false
fi

# Verificar diretórios existentes
INSTALL_DIRS=(
    "/opt/samureye-collector"
    "/opt/samureye"
    "/home/samureye"
    "/var/samureye"
)

INSTALL_DIR=""
for dir in "${INSTALL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        INSTALL_DIR="$dir"
        log "📁 Diretório encontrado: $INSTALL_DIR"
        break
    fi
done

if [ -z "$INSTALL_DIR" ]; then
    INSTALL_DIR="/opt/samureye-collector"
    log "📁 Criando novo diretório: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi

# Verificar usuário samureye
if ! id samureye >/dev/null 2>&1; then
    log "👤 Criando usuário samureye..."
    useradd -r -s /bin/false -m -d "/home/samureye" samureye
fi

# ============================================================================
# 2. CRIAR CONFIGURAÇÃO CORRETA
# ============================================================================

log "⚙️ Criando configuração do collector..."

# Criar diretório de configuração
mkdir -p /etc/samureye
mkdir -p /var/log/samureye

# Detectar hostname e IP
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Criar configuração
cat > /etc/samureye/collector.conf << EOF
{
  "collector_name": "vlxsam04",
  "hostname": "$HOSTNAME",
  "ip_address": "$IP_ADDRESS",
  "tenant_slug": "default",
  "server_url": "https://app.samureye.com.br",
  "heartbeat_interval": 120,
  "log_level": "INFO",
  "capabilities": ["nmap", "nuclei", "system_scan"],
  "version": "1.0.0"
}
EOF

log "✅ Configuração criada: /etc/samureye/collector.conf"

# ============================================================================
# 3. INSTALAR DEPENDÊNCIAS PYTHON
# ============================================================================

log "📦 Verificando dependências Python..."

# Instalar Python e dependências se necessário
if ! command -v python3 >/dev/null 2>&1; then
    apt-get update -q
    apt-get install -y python3 python3-pip python3-venv
fi

# Criar ambiente virtual
if [ ! -d "$INSTALL_DIR/venv" ]; then
    log "🐍 Criando ambiente virtual Python..."
    python3 -m venv "$INSTALL_DIR/venv"
fi

# Ativar ambiente virtual e instalar dependências
source "$INSTALL_DIR/venv/bin/activate"
pip install --upgrade pip --quiet
pip install requests psutil schedule --quiet

log "✅ Dependências Python instaladas"

# ============================================================================
# 4. CRIAR COLLECTOR AGENT ATUALIZADO
# ============================================================================

log "🤖 Criando collector agent atualizado..."

cat > "$INSTALL_DIR/collector_agent.py" << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent - Versão Corrigida
Envia telemetria real e executa comandos de segurança
"""

import json
import time
import requests
import psutil
import subprocess
import logging
import schedule
import os
import sys
from datetime import datetime, timezone
from threading import Thread
import signal

class SamurEyeCollector:
    def __init__(self, config_file='/etc/samureye/collector.conf'):
        self.config_file = config_file
        self.config = self.load_config()
        self.setup_logging()
        self.running = True
        
        # Setup signal handlers para graceful shutdown
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)
        
    def signal_handler(self, signum, frame):
        self.logger.info(f"Recebido sinal {signum}, parando collector...")
        self.running = False
        
    def load_config(self):
        """Carregar configuração do collector"""
        try:
            with open(self.config_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"ERRO: Arquivo de configuração não encontrado: {self.config_file}")
            sys.exit(1)
        except json.JSONDecodeError:
            print(f"ERRO: JSON inválido no arquivo: {self.config_file}")
            sys.exit(1)
    
    def setup_logging(self):
        """Configurar logging"""
        log_level = getattr(logging, self.config.get('log_level', 'INFO'))
        
        logging.basicConfig(
            level=log_level,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/samureye/collector.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('samureye-collector')
    
    def get_system_telemetry(self):
        """Coletar telemetria real do sistema"""
        try:
            # CPU usage (média de 1 segundo)
            cpu_percent = psutil.cpu_percent(interval=1)
            
            # Memory usage
            memory = psutil.virtual_memory()
            memory_percent = memory.percent
            memory_used_gb = round(memory.used / (1024**3), 2)
            memory_total_gb = round(memory.total / (1024**3), 2)
            
            # Disk usage (raiz)
            disk = psutil.disk_usage('/')
            disk_percent = round((disk.used / disk.total) * 100, 2)
            disk_used_gb = round(disk.used / (1024**3), 2)
            disk_total_gb = round(disk.total / (1024**3), 2)
            
            # Network I/O
            network = psutil.net_io_counters()
            
            # Process count
            process_count = len(psutil.pids())
            
            # Load average
            load_avg = os.getloadavg()
            
            return {
                'cpuUsage': round(cpu_percent, 2),
                'memoryUsage': round(memory_percent, 2),
                'diskUsage': disk_percent,
                'memoryDetails': {
                    'used_gb': memory_used_gb,
                    'total_gb': memory_total_gb,
                    'available_gb': round(memory.available / (1024**3), 2)
                },
                'diskDetails': {
                    'used_gb': disk_used_gb,
                    'total_gb': disk_total_gb,
                    'free_gb': round(disk.free / (1024**3), 2)
                },
                'networkIO': {
                    'bytes_sent': network.bytes_sent,
                    'bytes_recv': network.bytes_recv,
                    'packets_sent': network.packets_sent,
                    'packets_recv': network.packets_recv
                },
                'processCount': process_count,
                'loadAverage': list(load_avg),
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'hostname': self.config.get('hostname', 'unknown'),
                'collector_version': self.config.get('version', '1.0.0')
            }
        except Exception as e:
            self.logger.error(f"Erro ao coletar telemetria: {e}")
            return None
    
    def send_heartbeat(self):
        """Enviar heartbeat com telemetria para o servidor"""
        try:
            telemetry = self.get_system_telemetry()
            
            if not telemetry:
                self.logger.warning("Telemetria indisponível, enviando heartbeat básico")
                telemetry = {
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'status': 'error_collecting_telemetry'
                }
            
            payload = {
                'collector_id': self.config['collector_name'],
                'hostname': self.config.get('hostname'),
                'ip_address': self.config.get('ip_address'),
                'status': 'active',
                'telemetry': telemetry,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'capabilities': self.config.get('capabilities', []),
                'version': self.config.get('version', '1.0.0')
            }
            
            url = f"{self.config['server_url']}/collector-api/heartbeat"
            
            # Usar timeout mais longo e retry
            for attempt in range(3):
                try:
                    response = requests.post(url, json=payload, timeout=30, verify=False)
                    response.raise_for_status()
                    
                    self.logger.info("Heartbeat enviado com sucesso")
                    return
                    
                except requests.exceptions.RequestException as e:
                    if attempt == 2:  # última tentativa
                        raise e
                    self.logger.warning(f"Tentativa {attempt+1} falhou, tentando novamente...")
                    time.sleep(5)
            
        except Exception as e:
            self.logger.error(f"Falha ao enviar heartbeat: {e}")
    
    def execute_command(self, command_type, parameters):
        """Executar comando de segurança"""
        try:
            self.logger.info(f"Executando comando: {command_type}")
            
            if command_type == 'update_packages':
                return self.update_packages()
            elif command_type == 'nmap_scan':
                return self.run_nmap_scan(parameters.get('target'))
            elif command_type == 'nuclei_scan':
                return self.run_nuclei_scan(parameters.get('target'))
            else:
                return {'error': f'Comando desconhecido: {command_type}'}
                
        except Exception as e:
            self.logger.error(f"Erro ao executar comando {command_type}: {e}")
            return {'error': str(e)}
    
    def update_packages(self):
        """Atualizar pacotes do sistema"""
        try:
            self.logger.info("Iniciando update de pacotes...")
            
            # Update package list
            result1 = subprocess.run(['apt-get', 'update'], capture_output=True, text=True, timeout=300)
            
            # Upgrade packages
            result2 = subprocess.run(['apt-get', 'upgrade', '-y'], capture_output=True, text=True, timeout=600)
            
            return {
                'status': 'success',
                'message': 'Pacotes atualizados com sucesso',
                'update_output': result1.stdout,
                'upgrade_output': result2.stdout
            }
            
        except subprocess.TimeoutExpired:
            return {'status': 'error', 'message': 'Timeout durante update de pacotes'}
        except Exception as e:
            return {'status': 'error', 'message': str(e)}
    
    def run_nmap_scan(self, target):
        """Executar scan nmap"""
        if not target:
            return {'error': 'Target não especificado'}
            
        try:
            cmd = ['nmap', '-sS', '-T4', target]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            
            return {
                'scan_type': 'nmap',
                'target': target,
                'exit_code': result.returncode,
                'output': result.stdout,
                'error': result.stderr
            }
            
        except Exception as e:
            return {'error': str(e)}
    
    def start_scheduler(self):
        """Iniciar tarefas agendadas"""
        # Heartbeat a cada 2 minutos
        schedule.every(2).minutes.do(self.send_heartbeat)
        
        self.logger.info("Scheduler iniciado - heartbeat a cada 2 minutos")
        
        while self.running:
            schedule.run_pending()
            time.sleep(10)
    
    def run(self):
        """Loop principal do collector"""
        self.logger.info(f"Iniciando SamurEye Collector Agent {self.config['collector_name']}")
        self.logger.info(f"Servidor: {self.config['server_url']}")
        self.logger.info(f"Hostname: {self.config.get('hostname', 'unknown')}")
        
        # Enviar heartbeat inicial
        self.send_heartbeat()
        
        # Iniciar scheduler em thread separada
        scheduler_thread = Thread(target=self.start_scheduler, daemon=True)
        scheduler_thread.start()
        
        try:
            # Manter thread principal viva
            while self.running:
                time.sleep(60)
                
        except KeyboardInterrupt:
            self.logger.info("Collector interrompido pelo usuário")
        except Exception as e:
            self.logger.error(f"Erro no collector: {e}")
        finally:
            self.running = False
            self.logger.info("Collector finalizado")

if __name__ == '__main__':
    collector = SamurEyeCollector()
    collector.run()
EOF

chmod +x "$INSTALL_DIR/collector_agent.py"
log "✅ Collector agent criado"

# ============================================================================
# 5. CRIAR SERVIÇO SYSTEMD CORRIGIDO
# ============================================================================

log "🔧 Criando serviço systemd..."

cat > /etc/systemd/system/samureye-collector.service << EOF
[Unit]
Description=SamurEye Collector Agent - vlxsam04
Documentation=https://github.com/GruppenIT/SamurEye
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=samureye
Group=samureye
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONPATH=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/collector_agent.py
Restart=always
RestartSec=10
StartLimitInterval=0

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-collector

# Security
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/log/samureye /tmp

[Install]
WantedBy=multi-user.target
EOF

# ============================================================================
# 6. AJUSTAR PERMISSÕES E INICIAR
# ============================================================================

log "🔧 Ajustando permissões..."

chown -R samureye:samureye "$INSTALL_DIR"
chown -R samureye:samureye /var/log/samureye
chown samureye:samureye /etc/samureye/collector.conf
chmod 640 /etc/samureye/collector.conf

# ============================================================================
# 7. HABILITAR E INICIAR SERVIÇO
# ============================================================================

log "🚀 Habilitando e iniciando serviço..."

systemctl daemon-reload
systemctl enable samureye-collector.service
systemctl start samureye-collector.service

# Aguardar inicialização
sleep 10

# ============================================================================
# 8. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Verificando funcionamento..."

if systemctl is-active --quiet samureye-collector; then
    log "✅ Serviço ativo"
    
    # Verificar logs
    if journalctl -u samureye-collector --no-pager -n 5 | grep -q "Heartbeat enviado"; then
        log "✅ Heartbeat funcionando"
    else
        warn "⚠️ Heartbeat ainda não confirmado"
    fi
    
    # Mostrar últimos logs
    log "📝 Últimos logs:"
    journalctl -u samureye-collector --no-pager -n 10
    
else
    error "❌ Serviço não está ativo"
fi

# ============================================================================
# 9. RESULTADO FINAL
# ============================================================================

echo ""
log "🎯 COLLECTOR CONFIGURADO COM SUCESSO"
echo "════════════════════════════════════════════════"
echo ""
echo "📊 CONFIGURAÇÃO:"
echo "   ✓ Nome: vlxsam04"
echo "   ✓ Hostname: $HOSTNAME"
echo "   ✓ IP: $IP_ADDRESS"
echo "   ✓ Server: https://app.samureye.com.br"
echo ""
echo "🔧 SERVIÇO:"
echo "   ✓ Status: Ativo"
echo "   ✓ Heartbeat: A cada 2 minutos"
echo "   ✓ Telemetria: CPU, memória, disco real"
echo ""
echo "📁 ARQUIVOS:"
echo "   • Config: /etc/samureye/collector.conf"
echo "   • Agent: $INSTALL_DIR/collector_agent.py"
echo "   • Logs: /var/log/samureye/collector.log"
echo ""
echo "📝 MONITORAMENTO:"
echo "   • Status: systemctl status samureye-collector"
echo "   • Logs: journalctl -u samureye-collector -f"
echo "   • Config: cat /etc/samureye/collector.conf"
echo ""
echo "💡 PRÓXIMO PASSO:"
echo "   Verificar na interface se collector aparece online"
echo "   URL: https://app.samureye.com.br/collectors"

exit 0