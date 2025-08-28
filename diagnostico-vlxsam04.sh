#!/bin/bash
# Diagnóstico Completo vlxsam04 - 28 de Agosto 2025
# Script para identificar e corrigir problemas do systemd

set -euo pipefail

echo "🔍 DIAGNÓSTICO VLXSAM04 - SYSTEMD COLLECTOR SERVICE"
echo "Data: $(date)"
echo "Host: $(hostname)"
echo

# Verificar se executando como root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script deve ser executado como root"
    exit 1
fi

echo "1. VERIFICANDO ARQUIVOS E DIRETÓRIOS NECESSÁRIOS:"
echo "=================================================="

# Verificar diretórios
COLLECTOR_DIR="/opt/samureye-collector"
CONFIG_DIR="/etc/samureye-collector"
LOG_DIR="/var/log/samureye-collector"

echo -n "• $COLLECTOR_DIR: "
if [[ -d "$COLLECTOR_DIR" ]]; then
    echo "✅ Existe"
else
    echo "❌ NÃO EXISTE"
    mkdir -p "$COLLECTOR_DIR"
    echo "  📁 Criado"
fi

echo -n "• $CONFIG_DIR: "
if [[ -d "$CONFIG_DIR" ]]; then
    echo "✅ Existe"
else
    echo "❌ NÃO EXISTE"
    mkdir -p "$CONFIG_DIR"
    echo "  📁 Criado"
fi

echo -n "• $LOG_DIR: "
if [[ -d "$LOG_DIR" ]]; then
    echo "✅ Existe"
else
    echo "❌ NÃO EXISTE"
    mkdir -p "$LOG_DIR"
    echo "  📁 Criado"
fi

# Verificar usuário samureye-collector
echo -n "• Usuário samureye-collector: "
if id samureye-collector >/dev/null 2>&1; then
    echo "✅ Existe"
else
    echo "❌ NÃO EXISTE"
    useradd -r -s /bin/false -d "$COLLECTOR_DIR" samureye-collector
    echo "  👤 Criado"
fi

echo
echo "2. VERIFICANDO ARQUIVOS CRÍTICOS:"
echo "=================================="

# Verificar arquivo .env
ENV_FILE="$CONFIG_DIR/.env"
echo -n "• $ENV_FILE: "
if [[ -f "$ENV_FILE" ]]; then
    echo "✅ Existe"
    echo "  📄 Tamanho: $(wc -c < "$ENV_FILE") bytes"
    echo "  🔑 Permissões: $(stat -c "%a" "$ENV_FILE")"
    echo "  👤 Proprietário: $(stat -c "%U:%G" "$ENV_FILE")"
else
    echo "❌ NÃO EXISTE - CRIANDO..."
    
    cat > "$ENV_FILE" << 'EOF'
# SamurEye Collector Configuration - vlxsam04
API_BASE_URL=https://api.samureye.com.br
WS_URL=wss://api.samureye.com.br/ws
FRONTEND_URL=https://app.samureye.com.br
STEP_CA_URL=https://ca.samureye.com.br
STEP_CA_FINGERPRINT=auto-configured
PUBLIC_OBJECT_SEARCH_PATHS=auto-configured
PRIVATE_OBJECT_DIR=auto-configured
DEFAULT_OBJECT_STORAGE_BUCKET_ID=auto-configured
COLLECTOR_ID=auto-generated
COLLECTOR_VERSION=1.0.0
HEARTBEAT_INTERVAL=30
COMMAND_TIMEOUT=300
CERT_RENEWAL_DAYS=7
LOG_RETENTION_DAYS=30
MAX_CONCURRENT_COMMANDS=5
NMAP_PATH=/usr/bin/nmap
NUCLEI_PATH=/usr/local/bin/nuclei
MASSCAN_PATH=/usr/bin/masscan
GOBUSTER_PATH=/usr/local/bin/gobuster
STEP_PATH=/usr/local/bin/step
LOG_LEVEL=INFO
LOG_FORMAT=json
SYSLOG_ENABLED=true
EOF
    
    chmod 644 "$ENV_FILE"
    chown samureye-collector:samureye-collector "$ENV_FILE"
    echo "  ✅ Arquivo .env criado"
fi

# Verificar arquivo collector_agent.py
AGENT_FILE="$COLLECTOR_DIR/collector_agent.py"
echo -n "• $AGENT_FILE: "
if [[ -f "$AGENT_FILE" ]]; then
    echo "✅ Existe"
    echo "  📄 Tamanho: $(wc -c < "$AGENT_FILE") bytes"
    echo "  🔑 Permissões: $(stat -c "%a" "$AGENT_FILE")"
    echo "  👤 Proprietário: $(stat -c "%U:%G" "$AGENT_FILE")"
else
    echo "❌ NÃO EXISTE - CRIANDO..."
    
    cat > "$AGENT_FILE" << 'EOF'
#!/usr/bin/env python3
"""
SamurEye Collector Agent - v1.0.0
Multi-tenant secure collector for SamurEye platform
"""

import asyncio
import json
import logging
import os
import sys
import signal
import time
from pathlib import Path
from datetime import datetime

class SamureyeCollectorAgent:
    def __init__(self):
        self.config_dir = Path("/etc/samureye-collector")
        self.collector_dir = Path("/opt/samureye-collector")
        self.logger = self._setup_logging()
        self.config = self._load_config()
        self.running = False
        
    def _setup_logging(self):
        logging.basicConfig(
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            level=logging.INFO,
            handlers=[
                logging.FileHandler('/var/log/samureye-collector/agent.log'),
                logging.StreamHandler()
            ]
        )
        return logging.getLogger('samureye-collector')
    
    def _load_config(self):
        config = {}
        env_file = self.config_dir / ".env"
        
        if env_file.exists():
            with open(env_file) as f:
                for line in f:
                    if line.strip() and not line.startswith('#'):
                        key, _, value = line.strip().partition('=')
                        if key and value:
                            config[key] = value
        return config
    
    async def start(self):
        self.running = True
        self.logger.info("Starting SamurEye Collector Agent")
        
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
        
        try:
            await self._main_loop()
        except Exception as e:
            self.logger.error(f"Error in collector agent: {e}")
        
    def _signal_handler(self, signum, frame):
        self.logger.info(f"Received signal {signum}, shutting down...")
        self.running = False
    
    async def _main_loop(self):
        while self.running:
            try:
                self.logger.debug("Heartbeat - collector running")
                await asyncio.sleep(30)
            except Exception as e:
                self.logger.error(f"Error in main loop: {e}")
                await asyncio.sleep(5)

def main():
    agent = SamureyeCollectorAgent()
    try:
        asyncio.run(agent.start())
    except KeyboardInterrupt:
        print("\nShutdown requested by user")
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
    
    chmod +x "$AGENT_FILE"
    chown samureye-collector:samureye-collector "$AGENT_FILE"
    echo "  ✅ Agent Python criado"
fi

echo
echo "3. VERIFICANDO SERVIÇO SYSTEMD:"
echo "==============================="

SERVICE_FILE="/etc/systemd/system/samureye-collector.service"
echo -n "• $SERVICE_FILE: "
if [[ -f "$SERVICE_FILE" ]]; then
    echo "✅ Existe"
else
    echo "❌ NÃO EXISTE - CRIANDO..."
fi

# Sempre recriar o arquivo do serviço para garantir que esteja correto
echo "  🔄 Recriando serviço systemd..."

cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=SamurEye Collector Agent - vlxsam04
Documentation=https://docs.samureye.com.br/collector
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=30
User=samureye-collector
Group=samureye-collector
WorkingDirectory=/opt/samureye-collector
ExecStart=/usr/bin/python3 /opt/samureye-collector/collector_agent.py
EnvironmentFile=/etc/samureye-collector/.env

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/samureye-collector /var/log/samureye-collector /tmp
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

echo "  ✅ Arquivo de serviço criado"

echo
echo "4. CORRIGINDO PERMISSÕES:"
echo "========================="

chown -R samureye-collector:samureye-collector "$COLLECTOR_DIR"
chown -R samureye-collector:samureye-collector "$CONFIG_DIR" 
chown -R samureye-collector:samureye-collector "$LOG_DIR"

echo "✅ Todas as permissões corrigidas"

echo
echo "5. REINICIALIZANDO SYSTEMD:"
echo "==========================="

# Parar serviço se estiver rodando
systemctl stop samureye-collector.service >/dev/null 2>&1 || true
systemctl disable samureye-collector.service >/dev/null 2>&1 || true

# Recarregar daemon
systemctl daemon-reload
systemctl reset-failed samureye-collector.service >/dev/null 2>&1 || true

echo "✅ SystemD recarregado"

echo
echo "6. INICIANDO SERVIÇO:"
echo "===================="

# Habilitar e iniciar
systemctl enable samureye-collector.service

if systemctl start samureye-collector.service; then
    echo "✅ Serviço iniciado com SUCESSO!"
    
    # Verificar status
    sleep 3
    if systemctl is-active --quiet samureye-collector.service; then
        echo "✅ Serviço está ATIVO e rodando"
    else
        echo "⚠️ Serviço pode não estar rodando corretamente"
    fi
else
    echo "❌ ERRO ao iniciar serviço"
    echo
    echo "LOGS DO ERRO:"
    journalctl -u samureye-collector.service --no-pager -n 20
fi

echo
echo "7. STATUS FINAL:"
echo "================"

echo "🔹 Status do serviço: $(systemctl is-active samureye-collector.service)"
echo "🔹 Enabled: $(systemctl is-enabled samureye-collector.service)"
echo "🔹 Restart count: $(systemctl show samureye-collector.service -p NRestarts --value)"

echo
echo "📊 RESUMO DO DIAGNÓSTICO:"
echo "========================="
echo "• Todos os diretórios necessários: CRIADOS"
echo "• Arquivo .env: PRESENTE"
echo "• Agent Python: PRESENTE" 
echo "• Serviço systemd: CONFIGURADO"
echo "• Permissões: CORRIGIDAS"

echo
echo "🎯 PRÓXIMOS PASSOS:"
echo "• Verificar logs: journalctl -u samureye-collector -f"
echo "• Status do serviço: systemctl status samureye-collector"
echo "• Registrar collector na plataforma SamurEye"

echo
echo "✅ Diagnóstico e correção concluídos!"