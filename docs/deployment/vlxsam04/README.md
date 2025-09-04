# vlxsam04 - Collector Agent

Agente coletor de dados com ferramentas de segurança para ambiente on-premise SamurEye.

## 📋 Informações do Servidor

- **IP**: 192.168.100.154
- **Função**: Collector Agent
- **OS**: Ubuntu 24.04 LTS
- **Serviços**: Python 3.11, Node.js 20, Security Tools

## 🎯 Cenários de Instalação

### ✅ Instalação Padrão
```bash
ssh root@192.168.100.154
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/install.sh | bash
```

### 🔥 **HARD RESET (Recomendado para ambiente corrompido)**
```bash
ssh root@192.168.100.154
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/install-hard-reset.sh | bash
```

**⚠️ O hard reset remove todas as ferramentas e dados coletados!**

## 🏗️ Arquitetura

```
┌─────────────────────────────────────┐
│            vlxsam02                 │
│         (192.168.100.152)          │
│        SamurEye API Server          │
└─────────────┬───────────────────────┘
              │ HTTPS API Calls
              ↑ Heartbeat & Results
┌─────────────────────────────────────┐
│            vlxsam04                 │
│         (192.168.100.154)          │
│          Collector Agent            │
│                                     │
│  ┌─────────────────────────────────┐ │
│  │     SamurEye Collector          │ │
│  │       Python 3.11               │ │
│  │    samureye-collector.service   │ │
│  └─────────────────────────────────┘ │
│                                     │
│  ┌──────────┐  ┌─────────────────┐  │
│  │Security  │  │   System        │  │
│  │Tools     │  │   Telemetry     │  │
│  │Nmap      │  │   CPU/Memory    │  │
│  │Nuclei    │  │   Network       │  │
│  │Masscan   │  │   Process       │  │
│  │Gobuster  │  │   Monitoring    │  │
│  └──────────┘  └─────────────────┘  │
└─────────────────────────────────────┘
```

## 🛡️ Ferramentas de Segurança

### Network Scanning
- **Nmap**: Port scanning, OS detection, service enumeration
- **Masscan**: High-speed port scanner
- **Gobuster**: Directory/file brute-forcer

### Vulnerability Assessment
- **Nuclei**: Vulnerability scanner com templates atualizados
- **Templates**: Atualizados automaticamente

### Runtime Environment
- **Python 3.11**: Scanner engine e automação
- **Node.js 20**: Ferramentas auxiliares e integração

## 🚀 Sistema de Execução de Jornadas

### Funcionalidades de Execução

**Polling Automático:**
- Verifica periodicamente por jornadas pendentes no servidor
- Execução automática baseada no agendamento
- Relatório automático de resultados

**Ferramentas Integradas:**
- **Nmap**: Scanning avançado de rede e portas
- **Nuclei**: Detecção de vulnerabilidades
- **Masscan**: Scanning de alta velocidade
- **Gobuster**: Brute-force de diretórios

**Capacidades Técnicas:**
- Timeouts configuráveis (15min nmap, 20min nuclei)
- Parse automático de resultados JSON
- Logging detalhado de execuções
- Retry automático em falhas de comunicação

### API de Execução

O collector se comunica com o servidor via HTTPS:
- **Polling**: `GET /collector-api/journeys/pending`
- **Resultados**: `POST /collector-api/journeys/results`
- **Heartbeat**: `POST /collector-api/heartbeat`

## 🤖 SamurEye Collector Agent

### Serviço Principal
- **Nome**: samureye-collector
- **Usuário**: samureye-collector
- **Diretório**: /opt/samureye/collector
- **Logs**: /var/log/samureye-collector
- **Configuração**: /etc/samureye-collector

### Funcionalidades
- **Heartbeat**: Envio de telemetria a cada 30 segundos
- **Scan Execution**: Execução de scans Nmap e Nuclei
- **System Monitoring**: CPU, Memory, Disk, Network
- **Auto-registration**: Script de registro automático

### Telemetria Coletada
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "cpu_percent": 15.2,
  "memory_total": 8589934592,
  "memory_used": 2147483648,
  "memory_percent": 25.0,
  "disk_total": 107374182400,
  "disk_used": 21474836480,
  "disk_percent": 20.0,
  "network_io": {
    "bytes_sent": 1048576,
    "bytes_recv": 2097152
  },
  "processes": 127
}
```

## 📊 Monitoramento e Logs

### Status do Collector
```bash
# Status do serviço
systemctl status samureye-collector

# Logs em tempo real
tail -f /var/log/samureye-collector/collector.log

# Logs de erro
tail -f /var/log/samureye-collector/error.log

# Verificar processo
ps aux | grep collector
```

### Teste de Funcionalidades
```bash
# Verificar ferramentas instaladas
which nmap nuclei masscan gobuster

# Testar Nmap
nmap -sS -O 127.0.0.1

# Testar Nuclei
nuclei -version
nuclei -update-templates

# Testar conectividade com API
curl -k https://api.samureye.com.br/api/health
```

### Logs de Sistema
```bash
# Systemd journal
journalctl -u samureye-collector -f

# Application logs
tail -f /var/log/samureye-collector/*.log

# System logs
tail -f /var/log/syslog | grep collector
```

## 🔧 Comandos de Manutenção

### Controle do Serviço
```bash
# Iniciar
systemctl start samureye-collector

# Parar
systemctl stop samureye-collector

# Reiniciar
systemctl restart samureye-collector

# Status
systemctl status samureye-collector

# Enable/Disable
systemctl enable samureye-collector
systemctl disable samureye-collector
```

### Registro no Servidor
```bash
# Script automático de registro
/opt/samureye/collector/scripts/register.sh

# Verificar token salvo
cat /etc/samureye-collector/token.conf

# Aplicar token manualmente
systemctl restart samureye-collector
```

### Atualização de Ferramentas
```bash
# Atualizar Nuclei templates
sudo -u samureye-collector nuclei -update-templates

# Atualizar repositório Git (se aplicável)
cd /opt/samureye/collector/agent
git pull origin main

# Reinstalar dependências Python
pip3 install --upgrade psutil requests
```

### Limpeza Automática
```bash
# Script de limpeza (executado via cron)
/opt/samureye/collector/scripts/cleanup.sh

# Limpeza manual
find /opt/samureye/collector/temp -type f -mtime +1 -delete
find /var/log/samureye-collector -name "*.log" -mtime +7 -delete
```

## 🚨 Resolução de Problemas

### Problema: Collector não inicia
```bash
# Verificar logs de inicialização
journalctl -u samureye-collector -f

# Verificar dependências Python
python3 -c "import psutil, requests"

# Verificar permissões
ls -la /opt/samureye/collector/agent/

# Testar manualmente
sudo -u samureye-collector python3 /opt/samureye/collector/agent/collector.py
```

### Problema: Não conecta com API
```bash
# Testar conectividade
curl -k https://api.samureye.com.br/api/health

# Verificar DNS
nslookup api.samureye.com.br

# Verificar certificados SSL
openssl s_client -connect api.samureye.com.br:443

# Verificar firewall
ufw status
```

### Problema: Scanner tools não funcionam
```bash
# Verificar instalação
which nmap nuclei masscan gobuster

# Testar permissões
sudo -u samureye-collector nmap -sS 127.0.0.1

# Verificar templates Nuclei
ls -la /home/samureye-collector/nuclei-templates/

# Logs de execução
grep -i "scan" /var/log/samureye-collector/collector.log
```

### Problema: High CPU/Memory usage
```bash
# Verificar processos
top -u samureye-collector

# Verificar scans em execução
ps aux | grep -E 'nmap|nuclei|masscan'

# Limpar processos antigos
pkill -u samureye-collector nmap
pkill -u samureye-collector nuclei

# Verificar logs
tail -50 /var/log/samureye-collector/collector.log
```

## 📋 Checklist Pós-Instalação

### ✅ Validação de Ambiente
- [ ] Python 3.11: `python3 --version`
- [ ] Node.js 20: `node --version`
- [ ] Collector ativo: `systemctl is-active samureye-collector`
- [ ] Usuário criado: `id samureye-collector`

### ✅ Ferramentas de Segurança
- [ ] Nmap: `which nmap && nmap --version`
- [ ] Nuclei: `which nuclei && nuclei -version`
- [ ] Masscan: `which masscan && masscan --version`
- [ ] Gobuster: `which gobuster && gobuster version`

### ✅ Conectividade
- [ ] API acessível: `curl -k https://api.samureye.com.br/api/health`
- [ ] DNS resolve: `nslookup api.samureye.com.br`
- [ ] Firewall configurado: `ufw status`

### ✅ Funcionalidade
- [ ] Logs sendo gerados: `ls -la /var/log/samureye-collector/`
- [ ] Heartbeat funcionando: `grep heartbeat /var/log/samureye-collector/collector.log`
- [ ] Telemetria coletada: Verificar logs recentes

### ✅ Automação
- [ ] Cron job ativo: `crontab -l | grep cleanup`
- [ ] Auto-start configurado: `systemctl is-enabled samureye-collector`

## 🔐 Segurança e Acesso

### Firewall UFW
- **SSH (22)**: Acesso administrativo
- **HTTPS (443)**: Saída para API SamurEye
- **Rede interna**: 192.168.100.0/24 liberada
- **Regra padrão**: Deny incoming, Allow outgoing

### Usuário de Serviço
- **User**: samureye-collector
- **Home**: /opt/samureye/collector
- **Shell**: /bin/bash (para manutenção)
- **Privilégios**: Limitados, sem sudo

### Diretórios Protegidos
- **Certs**: /opt/samureye/collector/certs (700)
- **Config**: /etc/samureye-collector (750)
- **Logs**: /var/log/samureye-collector (755)

## 📁 Estrutura de Arquivos

```
/opt/samureye/collector/
├── agent/
│   └── collector.py            # Agente principal Python
├── tools/
│   ├── nmap/                   # Scripts Nmap
│   ├── nuclei/                 # Configurações Nuclei
│   ├── masscan/                # Configurações Masscan
│   └── custom/                 # Ferramentas customizadas
├── scripts/
│   ├── register.sh             # Registro no servidor
│   └── cleanup.sh              # Limpeza automática
├── certs/                      # Certificados mTLS
├── logs/                       # Logs locais
├── temp/                       # Arquivos temporários
├── uploads/                    # Resultados de scan
├── config/                     # Configurações
└── backups/                    # Backups locais

/etc/samureye-collector/
└── token.conf                  # Token de autenticação

/var/log/samureye-collector/
├── collector.log               # Logs principais
├── error.log                   # Logs de erro
├── cleanup.log                 # Logs de limpeza
└── scan-*.log                  # Logs de scans específicos

/etc/systemd/system/
└── samureye-collector.service  # Serviço systemd
```

## 🔧 Scripts Personalizados

### Registration Script
```bash
# /opt/samureye/collector/scripts/register.sh
# Registra o collector no servidor SamurEye
# Obtém token de enrollment
# Salva configuração automaticamente
```

### Cleanup Script
```bash
# /opt/samureye/collector/scripts/cleanup.sh
# Executa diariamente às 02:00 via cron
# Remove logs antigos (>7 dias)
# Remove arquivos temporários (>1 dia)
# Remove uploads antigos (>3 dias)
```

### Health Check
```bash
# Verificação completa do collector
curl -s http://localhost:8080/health 2>/dev/null || echo "Health endpoint not available"
systemctl is-active samureye-collector
ps aux | grep -c collector
df -h /opt/samureye/collector | tail -1 | awk '{print $5}'
```

## 🔗 Links Relacionados

- **Gateway**: [vlxsam01/README.md](../vlxsam01/README.md)
- **Aplicação**: [vlxsam02/README.md](../vlxsam02/README.md)
- **Banco de Dados**: [vlxsam03/README.md](../vlxsam03/README.md)
- **Arquitetura**: [../NETWORK-ARCHITECTURE.md](../NETWORK-ARCHITECTURE.md)