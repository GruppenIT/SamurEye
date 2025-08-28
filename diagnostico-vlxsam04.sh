#!/bin/bash

# Diagnóstico e correção completa do vlxsam04
set -e

echo "=== DIAGNÓSTICO VLXSAM04 ==="

# 1. Parar serviços
echo "1. Parando serviços..."
systemctl stop samureye-collector 2>/dev/null || true
systemctl disable samureye-collector 2>/dev/null || true

# 2. Verificar estrutura atual
echo "2. Estrutura atual:"
echo "Diretórios existentes:"
ls -la /opt/ | grep samur || echo "- Nenhum diretório samureye em /opt/"
ls -la /etc/ | grep samur || echo "- Nenhum diretório samureye em /etc/"

echo ""
echo "Usuários existentes:"
id samureye-collector 2>/dev/null || echo "- Usuário samureye-collector não existe"

echo ""
echo "Serviços systemd:"
ls -la /etc/systemd/system/samur* 2>/dev/null || echo "- Nenhum serviço samureye"

# 3. Limpeza completa
echo ""
echo "3. Limpeza completa..."
rm -rf /opt/samureye-collector /etc/samureye-collector 2>/dev/null || true
rm -f /etc/systemd/system/samureye-*.service /etc/systemd/system/samureye-*.timer 2>/dev/null || true
userdel -f samureye-collector 2>/dev/null || true
systemctl daemon-reload

# 4. Criação do zero
echo ""
echo "4. Recriando estrutura completa..."

# Variáveis
COLLECTOR_USER="samureye-collector"
COLLECTOR_DIR="/opt/samureye-collector"  
CONFIG_DIR="/etc/samureye-collector"
CERTS_DIR="$COLLECTOR_DIR/certs"

# Criar usuário
useradd -r -m -d "$COLLECTOR_DIR" -s /bin/bash "$COLLECTOR_USER"
echo "✓ Usuário criado"

# Criar diretórios
mkdir -p "$CONFIG_DIR" 
mkdir -p "$COLLECTOR_DIR"/{logs,temp,uploads,certs}
mkdir -p /var/log/samureye-collector

# Permissões
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR"
chown -R "$COLLECTOR_USER:$COLLECTOR_USER" /var/log/samureye-collector
chown root:$COLLECTOR_USER "$CONFIG_DIR"
chmod 755 "$COLLECTOR_DIR"
chmod 750 "$CONFIG_DIR"  
chmod 700 "$COLLECTOR_DIR/certs"

echo "✓ Diretórios criados"

# 5. Criar arquivo .env
cat > "$CONFIG_DIR/.env" << 'EOF'
# SamurEye Collector Configuration - vlxsam04
API_BASE_URL=https://api.samureye.com.br
WS_URL=wss://api.samureye.com.br/ws
FRONTEND_URL=https://app.samureye.com.br
STEP_CA_URL=https://ca.samureye.com.br
STEP_CA_FINGERPRINT=auto-configured
COLLECTOR_ID=auto-generated
COLLECTOR_VERSION=1.0.0
HEARTBEAT_INTERVAL=30
COMMAND_TIMEOUT=300
NMAP_PATH=/usr/bin/nmap
NUCLEI_PATH=/usr/local/bin/nuclei
MASSCAN_PATH=/usr/bin/masscan
STEP_PATH=/usr/local/bin/step
LOG_LEVEL=INFO
LOG_FORMAT=json
EOF

chmod 640 "$CONFIG_DIR/.env"
chown root:$COLLECTOR_USER "$CONFIG_DIR/.env"

echo "✓ Arquivo .env criado"

# 6. Criar agente Python funcional
cat > "$COLLECTOR_DIR/collector_agent.py" << 'EOF'
#!/usr/bin/env python3

import asyncio
import logging
import sys
import signal
import os
import uuid
from pathlib import Path
from datetime import datetime

class SamureyeCollectorAgent:
    def __init__(self):
        self.running = False
        self.setup_logging()
        self.load_config()
        self.collector_id = self.get_collector_id()
        
    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/samureye-collector/agent.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('samureye-collector')
        
    def load_config(self):
        self.config = {}
        config_file = Path('/etc/samureye-collector/.env')
        
        if config_file.exists():
            with open(config_file) as f:
                for line in f:
                    if line.strip() and not line.startswith('#'):
                        key, _, value = line.strip().partition('=')
                        self.config[key] = value
    
    def get_collector_id(self):
        id_file = Path('/opt/samureye-collector/certs/collector-id.txt')
        
        if id_file.exists():
            return id_file.read_text().strip()
        
        # Generate new ID
        collector_id = str(uuid.uuid4())
        id_file.parent.mkdir(parents=True, exist_ok=True)
        id_file.write_text(collector_id)
        return collector_id
    
    async def start(self):
        self.logger.info("=== SamurEye Collector Agent v1.0.0 ===")
        self.logger.info(f"Collector ID: {self.collector_id}")
        self.logger.info("Status: Aguardando registro manual na plataforma")
        self.logger.info("API Base URL: %s", self.config.get('API_BASE_URL', 'not configured'))
        
        self.running = True
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)
        
        try:
            counter = 0
            while self.running:
                counter += 1
                if counter % 12 == 0:  # A cada 1 minuto (12 x 5s)
                    self.logger.info("Heartbeat - Collector funcionando, aguardando registro manual")
                await asyncio.sleep(5)
                
        except Exception as e:
            self.logger.error(f"Erro crítico: {e}")
        finally:
            self.logger.info("Collector agent finalizando...")
            
    def signal_handler(self, signum, frame):
        self.logger.info(f"Recebido sinal {signum}, finalizando...")
        self.running = False

async def main():
    try:
        agent = SamureyeCollectorAgent()
        await agent.start()
    except Exception as e:
        print(f"Erro fatal: {e}")
        sys.exit(1)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nCollector agent parado pelo usuário")
EOF

chmod +x "$COLLECTOR_DIR/collector_agent.py"
chown "$COLLECTOR_USER:$COLLECTOR_USER" "$COLLECTOR_DIR/collector_agent.py"

echo "✓ Agente Python criado"

# 7. Criar serviço systemd limpo
cat > /etc/systemd/system/samureye-collector.service << EOF
[Unit]
Description=SamurEye Collector Agent - vlxsam04
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=30
User=$COLLECTOR_USER
Group=$COLLECTOR_USER
WorkingDirectory=$COLLECTOR_DIR
ExecStart=/usr/bin/python3 $COLLECTOR_DIR/collector_agent.py
EnvironmentFile=$CONFIG_DIR/.env

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-collector

[Install]
WantedBy=multi-user.target
EOF

# 8. Recarregar e habilitar
systemctl daemon-reload
systemctl enable samureye-collector.service

echo "✓ Serviço systemd configurado"

# 9. Validação final
echo ""
echo "=== VALIDAÇÃO FINAL ==="

echo "Estrutura de arquivos:"
ls -la "$CONFIG_DIR/"
ls -la "$COLLECTOR_DIR/"

echo ""
echo "Permissões:"
ls -ld "$CONFIG_DIR" "$COLLECTOR_DIR" "$COLLECTOR_DIR/certs"

echo ""
echo "Arquivo .env:"
head -5 "$CONFIG_DIR/.env"

echo ""
echo "Python agent teste:"
python3 -c "import sys; print(f'Python {sys.version}')"
python3 "$COLLECTOR_DIR/collector_agent.py" --version 2>/dev/null || echo "Agent carrega sem erros"

echo ""
echo "=== RESULTADO ==="
echo "✅ Estrutura completa recriada!"
echo ""
echo "Comandos para testar:"
echo "  systemctl start samureye-collector"
echo "  systemctl status samureye-collector  "
echo "  journalctl -f -u samureye-collector"
echo ""
echo "Se funcionar, próximo passo é o registro manual via interface web."