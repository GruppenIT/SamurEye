#!/bin/bash

echo "🔍 APLICANDO DEBUG DETALHADO NO COLLECTOR vlxsam04"
echo "================================================"

# Parar serviço
echo "⏹️ Parando serviço collector..."
systemctl stop samureye-collector

# Backup do arquivo atual
echo "💾 Fazendo backup do heartbeat.py atual..."
cp /opt/samureye/collector/heartbeat.py /opt/samureye/collector/heartbeat.py.backup.$(date +%Y%m%d_%H%M%S)

# Criar novo heartbeat.py com debug detalhado
echo "🔍 Aplicando novo heartbeat.py com debug detalhado..."
cat > /opt/samureye/collector/heartbeat.py << 'HEARTBEAT_DEBUG_EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent - Heartbeat with Debug
Sistema de heartbeat robusto com debug detalhado para resolver token inválido
"""

import os
import sys
import time
import json
import logging
import socket
import requests
import psutil
from datetime import datetime
from pathlib import Path

# Configurar logging detalhado
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/samureye-collector/collector.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class CollectorHeartbeat:
    def __init__(self):
        self.collector_id = None
        self.collector_name = None
        self.hostname = None
        self.ip_address = None
        self.api_base = None
        self.collector_token = None
        self.enrollment_token = None
        self.heartbeat_interval = 30
        self.session = requests.Session()
        
        # Configurar session
        self.session.headers.update({
            'User-Agent': 'SamurEye-Collector/1.0',
            'Accept': 'application/json',
            'Content-Type': 'application/json'
        })
        
        self.load_config()
        
    def load_config(self):
        """Carrega configuração do arquivo .env"""
        try:
            config_file = "/etc/samureye-collector/.env"
            config = {}
            
            if os.path.exists(config_file):
                with open(config_file, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#') and '=' in line:
                            key, value = line.split('=', 1)
                            config[key.strip()] = value.strip()
            
            self.collector_id = config.get('COLLECTOR_ID', 'vlxsam04')
            self.collector_name = config.get('COLLECTOR_NAME', self.collector_id)
            self.hostname = config.get('HOSTNAME', socket.gethostname())
            self.ip_address = config.get('IP_ADDRESS', self.get_local_ip())
            self.api_base = config.get('SAMUREYE_API_URL', 'https://api.samureye.com.br')
            self.collector_token = config.get('COLLECTOR_TOKEN', '')
            self.enrollment_token = config.get('ENROLLMENT_TOKEN', '')
            self.heartbeat_interval = int(config.get('HEARTBEAT_INTERVAL', '30'))
            
            logger.info(f"Configuração carregada - ID: {self.collector_id}, Token: {self.collector_token[:8]}...{self.collector_token[-8:] if len(self.collector_token) > 16 else self.collector_token}")
            
        except Exception as e:
            logger.error(f"Erro ao carregar configuração: {e}")
            sys.exit(1)
            
    def get_local_ip(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "127.0.0.1"
            
    def get_telemetry(self):
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
            return {"cpu_percent": 0, "memory_percent": 0, "disk_percent": 0, "processes": 0}
            
    def send_heartbeat(self):
        try:
            url = f"{self.api_base}/collector-api/heartbeat"
            telemetry = self.get_telemetry()
            
            data = {
                "collector_id": self.collector_id,
                "hostname": self.hostname,
                "ipAddress": self.ip_address,
                "status": "online",
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                "telemetry": telemetry,
                "capabilities": ["nmap", "nuclei", "masscan", "journey_execution"],
                "version": "1.0.1"
            }
            
            if not self.collector_token:
                logger.debug("COLLECTOR_TOKEN ausente - não enviando heartbeat")
                return False
            
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.collector_token}",
                "X-Collector-Token": self.collector_token
            }
                
            response = self.session.post(url, json=data, headers=headers, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                logger.debug(f"Heartbeat enviado - Status: {result.get('status', 'unknown')}")
                
                if result.get('transitioned'):
                    logger.info("✅ Collector transicionou de ENROLLING para ONLINE")
                    
                return True
            elif response.status_code == 401:
                logger.warning("Token inválido ou expirado - collector precisa ser re-registrado")
                return False
            elif response.status_code == 404:
                logger.warning("Collector não encontrado na API")
                return False
            else:
                logger.error(f"Erro no heartbeat: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Erro ao enviar heartbeat: {e}")
            return False

    def get_pending_journeys(self):
        """Busca jornadas pendentes para este collector"""
        try:
            if not self.collector_token or not self.collector_id:
                logger.error("🚨 DEBUG: collector_token ou collector_id ausente!")
                logger.error(f"   collector_token: {'SET' if self.collector_token else 'MISSING'}")
                logger.error(f"   collector_id: {'SET' if self.collector_id else 'MISSING'}")
                return []

            url = f"{self.api_base}/collector-api/journeys/pending"
            params = {
                "collector_id": self.collector_id,
                "token": self.collector_token  # Usar apenas collector_token permanente
            }
            
            # 🔍 DEBUG DETALHADO
            logger.info("🔍 DEBUG: Fazendo requisição para buscar jornadas pendentes...")
            logger.info(f"   URL: {url}")
            logger.info(f"   collector_id: {self.collector_id}")
            logger.info(f"   token: {self.collector_token[:8]}...{self.collector_token[-8:] if len(self.collector_token) > 16 else self.collector_token}")
            logger.info(f"   URL completa: {url}?collector_id={self.collector_id}&token={self.collector_token[:8]}...{self.collector_token[-8:]}")
            
            start_time = time.time()
            response = self.session.get(url, params=params, timeout=30)
            duration = time.time() - start_time
            
            # 🔍 DEBUG RESPOSTA
            logger.info(f"🔍 DEBUG: Resposta recebida em {duration:.2f}s")
            logger.info(f"   Status Code: {response.status_code}")
            logger.info(f"   Headers: {dict(response.headers)}")
            logger.info(f"   Response Body: {response.text[:500]}...")
            
            if response.status_code == 200:
                try:
                    journeys = response.json()
                    logger.info(f"✅ DEBUG: {len(journeys)} jornadas pendentes encontradas")
                    if journeys:
                        logger.info(f"   Primeira jornada: {journeys[0] if journeys else 'N/A'}")
                    return journeys
                except Exception as json_err:
                    logger.error(f"🚨 DEBUG: Erro ao fazer parse JSON: {json_err}")
                    logger.error(f"   Response text: {response.text}")
                    return []
            elif response.status_code == 401:
                logger.error("🚨 DEBUG: HTTP 401 - Token inválido ou expirado")
                logger.error(f"   Response: {response.text}")
                logger.error(f"   Headers enviados: {dict(self.session.headers) if hasattr(self.session, 'headers') else 'N/A'}")
                return []
            else:
                logger.error(f"🚨 DEBUG: HTTP {response.status_code} - Erro inesperado")
                logger.error(f"   Response: {response.text}")
                return []
                
        except Exception as e:
            logger.error(f"🚨 DEBUG: Exception ao buscar jornadas pendentes: {e}")
            logger.error(f"   Tipo: {type(e)}")
            logger.error(f"   Args: {e.args}")
            import traceback
            logger.error(f"   Traceback: {traceback.format_exc()}")
            return []

    def process_pending_journeys(self):
        """Processa jornadas pendentes"""
        try:
            pending_journeys = self.get_pending_journeys()
            
            for journey_execution in pending_journeys:
                execution_id = journey_execution.get("id")
                logger.info(f"Processando jornada {execution_id}")
                
        except Exception as e:
            logger.error(f"Erro ao processar jornadas pendentes: {e}")
            
    def run(self):
        logger.info("Iniciando heartbeat collector...")
        
        if not self.collector_token:
            logger.warning("COLLECTOR_TOKEN não encontrado - collector precisa ser registrado")
            logger.info("Execute: curl -fsSL .../register-collector.sh | bash -s -- <tenant> <token>")
                
        consecutive_failures = 0
        max_failures = 5
        
        while True:
            try:
                # Recarregar configuração periodicamente para pegar novo token
                if consecutive_failures % 3 == 0:
                    self.load_config()
                
                # Só tentar heartbeat se há token
                if self.collector_token:
                    # Enviar heartbeat
                    if self.send_heartbeat():
                        consecutive_failures = 0
                    else:
                        consecutive_failures += 1
                        
                        if consecutive_failures >= max_failures:
                            logger.warning("Muitas falhas consecutivas - recarregando configuração")
                            self.load_config()
                            consecutive_failures = 0
                    
                    # Processar jornadas pendentes a cada ciclo
                    try:
                        self.process_pending_journeys()
                    except Exception as e:
                        logger.error(f"Erro no processamento de jornadas: {e}")
                else:
                    logger.debug("Aguardando COLLECTOR_TOKEN...")
                    consecutive_failures += 1
                        
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
HEARTBEAT_DEBUG_EOF

# Aplicar permissões
chmod +x /opt/samureye/collector/heartbeat.py
chown samureye-collector:samureye-collector /opt/samureye/collector/heartbeat.py

# Reiniciar serviço
echo "🔄 Reiniciando serviço collector..."
systemctl start samureye-collector
systemctl status samureye-collector --no-pager

echo ""
echo "🔍 DEBUG APLICADO! Monitore os logs para ver detalhes:"
echo "   tail -f /var/log/samureye-collector/collector.log"
echo ""
echo "✅ Agora você verá:"
echo "   📋 URL completa da requisição"
echo "   📋 Parâmetros enviados"
echo "   📋 Status code e headers da resposta"
echo "   📋 Body completo da resposta"
echo "   📋 Detalhes de qualquer erro"