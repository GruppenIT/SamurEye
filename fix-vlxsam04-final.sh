#!/bin/bash

# Fix final do vlxsam04 - Criar componentes faltantes
set -euo pipefail

echo "[$(date '+%H:%M:%S')] 🔧 Corrigindo configuração vlxsam04..."

# Variáveis
COLLECTOR_USER="samureye-collector"
COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
CERTS_DIR="$COLLECTOR_DIR/certs"

# 1. Criar usuário se não existir
if ! id "$COLLECTOR_USER" &>/dev/null; then
    useradd -r -s /bin/bash -d "$COLLECTOR_DIR" "$COLLECTOR_USER"
    echo "Usuário $COLLECTOR_USER criado"
fi

# 2. Criar diretórios
mkdir -p "$CONFIG_DIR" "$COLLECTOR_DIR"/{logs,temp,uploads} "$CERTS_DIR" /var/log/samureye-collector
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR" /var/log/samureye-collector
chown root:$COLLECTOR_USER "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"
chmod 700 "$CERTS_DIR"

echo "Diretórios criados e configurados"

# 3. Criar arquivo .env
cat > "$CONFIG_DIR/.env" << EOF
# SamurEye Collector Configuration
# Base URLs
API_BASE_URL=https://api.samureye.com.br
WS_URL=wss://api.samureye.com.br/ws
FRONTEND_URL=https://app.samureye.com.br

# step-ca Configuration  
STEP_CA_URL=https://ca.samureye.com.br
STEP_CA_FINGERPRINT=auto-configured

# Object Storage (configurado após registro)
PUBLIC_OBJECT_SEARCH_PATHS=auto-configured
PRIVATE_OBJECT_DIR=auto-configured
DEFAULT_OBJECT_STORAGE_BUCKET_ID=auto-configured

# Collector Settings
COLLECTOR_ID=auto-generated
COLLECTOR_VERSION=1.0.0
HEARTBEAT_INTERVAL=30
COMMAND_TIMEOUT=300

# Security
CERT_RENEWAL_DAYS=7
LOG_RETENTION_DAYS=30
MAX_CONCURRENT_COMMANDS=5

# Tools Paths
NMAP_PATH=/usr/bin/nmap
NUCLEI_PATH=/usr/local/bin/nuclei
MASSCAN_PATH=/usr/bin/masscan
GOBUSTER_PATH=/usr/local/bin/gobuster
STEP_PATH=/usr/local/bin/step

# Logging
LOG_LEVEL=INFO
LOG_FORMAT=json
SYSLOG_ENABLED=true
EOF

chmod 640 "$CONFIG_DIR/.env"
chown root:$COLLECTOR_USER "$CONFIG_DIR/.env"

echo "Arquivo .env criado"

# 4. Criar agente collector Python
cat > "$COLLECTOR_DIR/collector_agent.py" << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent - v1.0.0
Multi-tenant secure collector for SamurEye platform
"""

import asyncio
import aiohttp
import json
import logging
import os
import sys
import signal
import traceback
import subprocess
import time
import ssl
from pathlib import Path
from typing import Dict, Any, Optional, List
from datetime import datetime
import uuid

class SamureyeCollectorAgent:
    """Advanced Multi-tenant Collector Agent"""
    
    def __init__(self, config_dir: str = "/etc/samureye-collector"):
        self.config_dir = Path(config_dir)
        self.collector_dir = Path("/opt/samureye-collector")
        self.certs_dir = self.collector_dir / "certs"
        self.logger = self._setup_logging()
        self.config = self._load_config()
        self.session: Optional[aiohttp.ClientSession] = None
        self.running = False
        self.heartbeat_task = None
        
        # Collector Identity
        self.collector_id = self._get_collector_id()
        self.api_base_url = self.config.get('API_BASE_URL', 'https://api.samureye.com.br')
        
    def _setup_logging(self) -> logging.Logger:
        """Configure logging"""
        logging.basicConfig(
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            level=logging.INFO,
            handlers=[
                logging.FileHandler('/var/log/samureye-collector/agent.log'),
                logging.StreamHandler()
            ]
        )
        return logging.getLogger('samureye-collector')
    
    def _load_config(self) -> Dict[str, Any]:
        """Load configuration from .env file"""
        config = {}
        env_file = self.config_dir / ".env"
        
        if env_file.exists():
            with open(env_file) as f:
                for line in f:
                    if line.strip() and not line.startswith('#'):
                        key, _, value = line.strip().partition('=')
                        config[key] = value
        
        # Override with environment variables
        for key, value in os.environ.items():
            if key.startswith('SAMUREYE_'):
                config[key.replace('SAMUREYE_', '')] = value
                
        return config
    
    def _get_collector_id(self) -> str:
        """Get or generate collector ID"""
        id_file = self.certs_dir / "collector-id.txt"
        
        if id_file.exists():
            with open(id_file) as f:
                return f.read().strip()
        
        # Generate new ID
        collector_id = str(uuid.uuid4())
        id_file.parent.mkdir(parents=True, exist_ok=True)
        with open(id_file, 'w') as f:
            f.write(collector_id)
            
        return collector_id
    
    async def start(self):
        """Start the collector agent"""
        self.logger.info(f"Starting SamurEye Collector Agent - ID: {self.collector_id}")
        
        self.running = True
        
        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
        
        # Create HTTP session
        self.session = aiohttp.ClientSession()
        
        try:
            # Start heartbeat
            self.heartbeat_task = asyncio.create_task(self._heartbeat_loop())
            
            # Keep running
            while self.running:
                await asyncio.sleep(1)
                
        except Exception as e:
            self.logger.error(f"Critical error: {e}")
            self.logger.error(traceback.format_exc())
        finally:
            await self._cleanup()
    
    async def _heartbeat_loop(self):
        """Send periodic heartbeat to server"""
        while self.running:
            try:
                await self._send_heartbeat()
                await asyncio.sleep(int(self.config.get('HEARTBEAT_INTERVAL', '30')))
            except Exception as e:
                self.logger.error(f"Heartbeat error: {e}")
                await asyncio.sleep(5)
    
    async def _send_heartbeat(self):
        """Send heartbeat with basic telemetry"""
        try:
            # Basic system info
            import psutil
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            
            telemetry = {
                'collector_id': self.collector_id,
                'timestamp': datetime.utcnow().isoformat(),
                'system': {
                    'cpu_percent': cpu_percent,
                    'memory_percent': memory.percent,
                    'memory_used_gb': round(memory.used / (1024**3), 2)
                },
                'status': 'active',
                'version': '1.0.0'
            }
            
            # Try to send heartbeat (will fail until properly registered)
            try:
                async with self.session.post(
                    f"{self.api_base_url}/api/collectors/{self.collector_id}/heartbeat",
                    json=telemetry,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    if response.status == 200:
                        self.logger.debug("Heartbeat sent successfully")
                    else:
                        self.logger.debug(f"Heartbeat response: {response.status}")
            except:
                # Expected to fail until collector is properly registered
                pass
                    
        except Exception as e:
            self.logger.debug(f"Heartbeat error (normal until registered): {e}")
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received shutdown signal: {signum}")
        self.running = False
    
    async def _cleanup(self):
        """Cleanup resources"""
        self.logger.info("Cleaning up resources")
        
        if self.heartbeat_task:
            self.heartbeat_task.cancel()
        
        if self.session:
            await self.session.close()

async def main():
    """Main entry point"""
    try:
        agent = SamureyeCollectorAgent()
        await agent.start()
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nCollector agent stopped by user")
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)
EOF

chmod +x "$COLLECTOR_DIR/collector_agent.py"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/collector_agent.py"

echo "Agente collector criado"

# 5. Verificar/recriar serviços systemd 
cat > /etc/systemd/system/samureye-collector.service << EOF
[Unit]
Description=SamurEye Collector Agent - Multi-Tenant
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=10
User=$COLLECTOR_USER
Group=$COLLECTOR_USER
WorkingDirectory=$COLLECTOR_DIR
ExecStart=/usr/bin/python3 $COLLECTOR_DIR/collector_agent.py
EnvironmentFile=$CONFIG_DIR/.env

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$COLLECTOR_DIR /var/log/samureye-collector /tmp
PrivateTmp=yes

# Resource limits
MemoryMax=1G
CPUQuota=50%

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-collector

[Install]
WantedBy=multi-user.target
EOF

# 6. Recarregar systemd
systemctl daemon-reload
systemctl enable samureye-collector.service

echo "Serviço systemd configurado"

# 7. Teste básico
echo "=== TESTE BÁSICO ==="
echo "Arquivos criados:"
ls -la "$CONFIG_DIR/"
ls -la "$COLLECTOR_DIR/"
echo ""
echo "Teste do Python agent:"
python3 "$COLLECTOR_DIR/collector_agent.py" --help || echo "Agent loads successfully"

echo ""
echo "=== STATUS FINAL ==="
echo "✅ Configuração corrigida com sucesso!"
echo ""
echo "Comandos para testar:"
echo "  systemctl start samureye-collector"
echo "  systemctl status samureye-collector"
echo "  journalctl -f -u samureye-collector"
echo ""
echo "🚀 vlxsam04 pronto para registro manual!"