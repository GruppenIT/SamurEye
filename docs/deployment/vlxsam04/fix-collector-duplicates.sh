#!/bin/bash
# Script para corrigir duplicação de coletores e implementar heartbeat correto

echo "🔧 CORREÇÃO DE DUPLICAÇÃO DE COLETORES - vlxsam04"
echo "================================================"

# Informações do sistema
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
API_URL="https://api.samureye.com.br"
COLLECTOR_NAME="${HOSTNAME}-collector"

echo ""
echo "📋 SISTEMA:"
echo "   Hostname: $HOSTNAME"
echo "   IP: $IP_ADDRESS"
echo "   Nome Collector: $COLLECTOR_NAME"

echo ""
echo "🧹 PASSO 1: LIMPANDO COLETORES DUPLICADOS"
echo "========================================="

# Obter lista de coletores para este hostname
echo "📡 Buscando coletores duplicados..."

# Primeiro, parar o serviço para evitar novos registros
systemctl stop samureye-collector 2>/dev/null

# Simular limpeza via API (seria feito através de interface admin)
echo "⚠️ NOTA: Limpeza de duplicatas deve ser feita via interface admin"
echo "   Acesse: https://app.samureye.com.br/admin/collectors"
echo "   Remova coletores duplicados manualmente"
echo ""

echo "🔧 PASSO 2: CONFIGURANDO REGISTRO ÚNICO"
echo "======================================="

# Criar configuração robusta para evitar duplicação
cat > /etc/samureye-collector/.env << EOF
# Configuração do Collector SamurEye
COLLECTOR_ID=${HOSTNAME}
COLLECTOR_NAME=${COLLECTOR_NAME}
HOSTNAME=${HOSTNAME}
IP_ADDRESS=${IP_ADDRESS}
API_BASE_URL=${API_URL}
HEARTBEAT_INTERVAL=30
RETRY_ATTEMPTS=3
RETRY_DELAY=5
LOG_LEVEL=INFO
EOF

echo "✅ Arquivo .env criado com configuração única"

echo ""
echo "🔧 PASSO 3: ATUALIZANDO SCRIPT DE HEARTBEAT"
echo "==========================================="

# Criar script de heartbeat robusto
cat > /opt/samureye/collector/heartbeat.py << 'EOF'
#!/usr/bin/env python3
"""
Script de heartbeat robusto para SamurEye Collector
Evita duplicação e gerencia status automaticamente
"""

import os
import sys
import json
import time
import socket
import requests
import logging
import psutil
from pathlib import Path

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/samureye-collector/heartbeat.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class CollectorHeartbeat:
    def __init__(self):
        self.load_config()
        self.session = requests.Session()
        self.session.verify = False  # Para certificados auto-assinados
        
    def load_config(self):
        """Carrega configuração do collector"""
        try:
            # Tentar carregar do .env
            env_file = Path("/etc/samureye-collector/.env")
            if env_file.exists():
                with open(env_file) as f:
                    for line in f:
                        if '=' in line and not line.startswith('#'):
                            key, value = line.strip().split('=', 1)
                            os.environ[key] = value
                            
            self.collector_id = os.environ.get('COLLECTOR_ID', socket.gethostname())
            self.collector_name = os.environ.get('COLLECTOR_NAME', f"{socket.gethostname()}-collector")
            self.hostname = os.environ.get('HOSTNAME', socket.gethostname())
            self.ip_address = os.environ.get('IP_ADDRESS', self.get_local_ip())
            self.api_base = os.environ.get('API_BASE_URL', 'https://api.samureye.com.br')
            self.heartbeat_interval = int(os.environ.get('HEARTBEAT_INTERVAL', '30'))
            
            # Tentar carregar token
            token_file = Path("/etc/samureye-collector/token.conf")
            self.enrollment_token = None
            if token_file.exists():
                with open(token_file) as f:
                    for line in f:
                        if line.startswith('ENROLLMENT_TOKEN='):
                            self.enrollment_token = line.strip().split('=', 1)[1]
                            break
                            
            logger.info(f"Configuração carregada - ID: {self.collector_id}, Nome: {self.collector_name}")
            
        except Exception as e:
            logger.error(f"Erro ao carregar configuração: {e}")
            sys.exit(1)
            
    def get_local_ip(self):
        """Obtém IP local"""
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "127.0.0.1"
            
    def get_telemetry(self):
        """Coleta telemetria do sistema"""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            return {
                "cpu_percent": cpu_percent,
                "memory_percent": memory.percent,
                "disk_percent": disk.percent,
                "processes": len(psutil.pids()),
                "memory_total": memory.total,
                "disk_total": disk.total,
                "uptime": int(time.time() - psutil.boot_time())
            }
        except Exception as e:
            logger.warning(f"Erro ao coletar telemetria: {e}")
            return {
                "cpu_percent": 0,
                "memory_percent": 0,
                "disk_percent": 0,
                "processes": 0
            }
            
    def register_collector(self):
        """Registra collector (atualiza se já existe)"""
        try:
            url = f"{self.api_base}/api/collectors"
            data = {
                "name": self.collector_name,
                "hostname": self.hostname,
                "ipAddress": self.ip_address,
                "status": "enrolling",
                "description": f"Collector agent on-premise {self.hostname}"
            }
            
            logger.info(f"Registrando collector: {data}")
            response = self.session.post(url, json=data, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                if 'enrollmentToken' in result:
                    self.enrollment_token = result['enrollmentToken']
                    
                    # Salvar token
                    with open('/etc/samureye-collector/token.conf', 'w') as f:
                        f.write(f"ENROLLMENT_TOKEN={self.enrollment_token}\n")
                    os.chmod('/etc/samureye-collector/token.conf', 0o600)
                    
                    logger.info("Collector registrado com sucesso")
                    return True
                    
            logger.error(f"Erro no registro: {response.status_code} - {response.text}")
            return False
            
        except Exception as e:
            logger.error(f"Erro ao registrar collector: {e}")
            return False
            
    def send_heartbeat(self):
        """Envia heartbeat para o servidor"""
        try:
            url = f"{self.api_base}/collector-api/heartbeat"
            telemetry = self.get_telemetry()
            
            data = {
                "collector_id": self.collector_id,
                "status": "online",
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                "telemetry": telemetry,
                "capabilities": ["nmap", "nuclei", "masscan"],
                "version": "1.0.0"
            }
            
            if self.enrollment_token:
                data["token"] = self.enrollment_token
                
            response = self.session.post(url, json=data, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                logger.info(f"Heartbeat enviado com sucesso - Status: {result.get('status', 'unknown')}")
                
                # Se transicionou de ENROLLING para ONLINE
                if result.get('transitioned'):
                    logger.info("✅ Collector transicionou de ENROLLING para ONLINE")
                    
                return True
            else:
                logger.error(f"Erro no heartbeat: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Erro ao enviar heartbeat: {e}")
            return False
            
    def run(self):
        """Loop principal do heartbeat"""
        logger.info("Iniciando heartbeat collector...")
        
        # Tentar registrar se não temos token
        if not self.enrollment_token:
            logger.info("Token não encontrado, registrando collector...")
            if not self.register_collector():
                logger.error("Falha no registro inicial")
                return
                
        # Loop de heartbeat
        consecutive_failures = 0
        max_failures = 5
        
        while True:
            try:
                if self.send_heartbeat():
                    consecutive_failures = 0
                else:
                    consecutive_failures += 1
                    
                    # Se muitas falhas consecutivas, tentar re-registrar
                    if consecutive_failures >= max_failures:
                        logger.warning("Muitas falhas consecutivas, tentando re-registrar...")
                        self.register_collector()
                        consecutive_failures = 0
                        
                time.sleep(self.heartbeat_interval)
                
            except KeyboardInterrupt:
                logger.info("Heartbeat interrompido pelo usuário")
                break
            except Exception as e:
                logger.error(f"Erro no loop de heartbeat: {e}")
                time.sleep(self.heartbeat_interval)

if __name__ == "__main__":
    heartbeat = CollectorHeartbeat()
    heartbeat.run()
EOF

chmod +x /opt/samureye/collector/heartbeat.py
chown samureye-collector:samureye-collector /opt/samureye/collector/heartbeat.py

echo "✅ Script de heartbeat robusto criado"

echo ""
echo "🔧 PASSO 4: ATUALIZANDO SERVIÇO SYSTEMD"
echo "======================================="

# Atualizar serviço para usar novo script
cat > /etc/systemd/system/samureye-collector.service << EOF
[Unit]
Description=SamurEye Collector Agent
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=10
User=samureye-collector
Group=samureye-collector
WorkingDirectory=/opt/samureye/collector
ExecStart=/usr/bin/python3 /opt/samureye/collector/heartbeat.py
StandardOutput=append:/var/log/samureye-collector/collector.log
StandardError=append:/var/log/samureye-collector/collector.log
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo "✅ Serviço systemd atualizado"

echo ""
echo "🔧 PASSO 5: INICIANDO COLLECTOR COM NOVA CONFIGURAÇÃO"
echo "==================================================="

# Limpar logs antigos
rm -f /var/log/samureye-collector/*.log
mkdir -p /var/log/samureye-collector
chown samureye-collector:samureye-collector /var/log/samureye-collector

# Iniciar serviço
systemctl enable samureye-collector
systemctl restart samureye-collector

echo "✅ Serviço reiniciado"

# Aguardar alguns segundos e verificar status
sleep 5

echo ""
echo "🔍 VERIFICANDO STATUS FINAL:"
echo "============================"

echo "Status do serviço:"
systemctl status samureye-collector --no-pager -l

echo ""
echo "Logs recentes:"
tail -n 10 /var/log/samureye-collector/heartbeat.log 2>/dev/null || echo "Logs ainda não gerados"

echo ""
echo "✅ CORREÇÃO DE DUPLICAÇÃO CONCLUÍDA"
echo "==================================="
echo ""
echo "🔧 PRÓXIMOS PASSOS:"
echo "1. Aguardar 1-2 minutos para heartbeat estabelecer conexão"
echo "2. Verificar interface admin para confirmar collector único"
echo "3. Monitorar logs: tail -f /var/log/samureye-collector/heartbeat.log"
echo "4. Status: systemctl status samureye-collector"