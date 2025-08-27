# vlxsam04 - Collector Agent Installation

## ⚠️ IMPORTANTE: Ubuntu 24.04 Compatibility

**O script foi totalmente atualizado para Ubuntu 24.04!** Se você encontrar erros como:
- `E: Unable to locate package python3.11`
- `E: Package 'netcat' has no installation candidate`

Significa que você está usando uma versão desatualizada do script. Use sempre o comando local abaixo.

## 🚀 Instalação Rápida

### Método Recomendado (Script Local Atualizado):
```bash
# Baixar e executar script local atualizado
sudo bash /path/to/SamurEye/docs/deployment/vlxsam04/install.sh
```

### ❌ EVITAR (Script GitHub pode estar desatualizado):
```bash
# NÃO USE - pode estar desatualizado
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/install.sh | bash
```

## 📋 Pré-requisitos

- **SO**: Ubuntu 24.04 LTS (Noble)
- **Usuário**: root ou sudo
- **Conectividade**: Internet para downloads
- **Espaço**: ~2GB livre
- **RAM**: Mínimo 2GB recomendado

## 🏗️ O que o Script Instala

### Componentes Base
- ✅ **Python 3.12** (nativo Ubuntu 24.04)
- ✅ **Node.js 20.x** (LTS)
- ✅ **netcat-openbsd** (substitui netcat legacy)
- ✅ **build-essential** para compilação
- ✅ **Dependências do sistema**

### Ferramentas de Segurança
- ✅ **Nmap** (network scanning)
- ✅ **Nuclei** (vulnerability scanner)
- ✅ **Masscan** (port scanner)
- ✅ **Gobuster** (directory brute-force)
- ✅ **step-ca** (certificate authority)

### Estrutura do Collector
- ✅ **Multi-tenant support** (isolamento por tenant)
- ✅ **mTLS communication** (certificados X.509)
- ✅ **WebSocket real-time** streaming
- ✅ **Object Storage** integration
- ✅ **Logging e telemetria** por tenant

## 🔧 Estrutura Criada

```
/opt/samureye-collector/
├── agent/                  # Código do agente Python
│   ├── main.py            # Agente principal
│   ├── telemetry.py       # Coleta de telemetria
│   └── executor.py        # Executor de comandos
├── certs/                 # Certificados mTLS (modo 700)
├── tools/                 # Ferramentas de segurança
│   ├── nmap/
│   ├── nuclei/
│   ├── masscan/
│   └── gobuster/
├── logs/                  # Logs por tenant
│   ├── system/
│   └── tenant-{1..10}/
├── temp/                  # Arquivos temporários por tenant
│   └── tenant-{1..10}/
├── uploads/               # Uploads por tenant
│   └── tenant-{1..10}/
└── scripts/               # Scripts de manutenção

/etc/samureye-collector/
└── .env                   # Configurações principais

/var/log/samureye-collector/
├── collector.log          # Log principal
├── telemetry.log          # Log de telemetria
├── ubuntu-24-04-compatibility.log  # Log de compatibilidade
└── tenant-*.log           # Logs por tenant
```

## ⚙️ Próximos Passos Obrigatórios

### 1. Configurar step-ca Connection
```bash
# Editar configuração step-ca
sudo nano /etc/samureye-collector/.env

# Adicionar:
STEP_CA_URL=https://ca.samureye.com.br
STEP_CA_FINGERPRINT=<fingerprint_from_ca_server>
COLLECTOR_ID=vlxsam04
```

### 2. Executar Setup step-ca
```bash
sudo /opt/samureye-collector/scripts/setup-step-ca.sh
```

### 3. Registrar Collector na Plataforma
- Acessar interface web: https://app.samureye.com.br
- Login como admin
- Registrar novo collector vlxsam04
- Copiar token de registro

### 4. Iniciar Serviços
```bash
# Habilitar e iniciar serviços
sudo systemctl enable samureye-collector samureye-telemetry
sudo systemctl start samureye-collector samureye-telemetry

# Verificar status
sudo systemctl status samureye-collector
sudo systemctl status samureye-telemetry
```

### 5. Verificar Health Check
```bash
sudo /opt/samureye-collector/scripts/health-check.sh
```

## 🧪 Validação e Testes

### Testar Conectividade mTLS
```bash
sudo /opt/samureye-collector/scripts/test-mtls-connection.sh
```

### Verificar Logs
```bash
# Log principal
sudo tail -f /var/log/samureye-collector/collector.log

# Log de telemetria
sudo tail -f /var/log/samureye-collector/telemetry.log

# Compatibilidade Ubuntu 24.04
sudo cat /var/log/samureye-collector/ubuntu-24-04-compatibility.log
```

### Testar Ferramentas de Segurança
```bash
# Testar Nmap
sudo -u samureye-collector nmap -sV localhost

# Testar Nuclei
sudo -u samureye-collector nuclei -version

# Testar Masscan
sudo -u samureye-collector masscan --version
```

## 🛠️ Troubleshooting

### Problema: Python 3.11 não encontrado
**Solução**: Use o script local atualizado, não o do GitHub
```bash
sudo bash docs/deployment/vlxsam04/install.sh  # Script local corrigido
```

### Problema: netcat não encontrado
**Solução**: Já corrigido no script local (usa netcat-openbsd)

### Problema: Serviço não inicia
```bash
# Verificar logs detalhados
sudo journalctl -u samureye-collector -f

# Verificar configuração
sudo /opt/samureye-collector/scripts/health-check.sh
```

### Problema: Certificados mTLS
```bash
# Reconfigurar step-ca
sudo /opt/samureye-collector/scripts/setup-step-ca.sh --force

# Verificar conexão CA
curl -k https://ca.samureye.com.br/health
```

## 📊 Monitoramento

### Logs em Tempo Real
```bash
# Todos os logs
sudo tail -f /var/log/samureye-collector/*.log

# Apenas erros
sudo grep -i error /var/log/samureye-collector/*.log
```

### Status dos Serviços
```bash
# Status completo
sudo systemctl status samureye-collector samureye-telemetry

# Reiniciar se necessário
sudo systemctl restart samureye-collector
```

### Métricas de Sistema
```bash
# Uso de CPU/RAM do collector
sudo ps aux | grep samureye

# Espaço em disco
sudo df -h /opt/samureye-collector
sudo du -sh /var/log/samureye-collector
```

## 🔐 Segurança

### Permissões Importantes
- `samureye-collector` user: Execução isolada
- `/opt/samureye-collector/certs/`: Modo 700 (certificados privados)
- Logs: Apenas root e samureye-collector

### Certificados mTLS
- Renovação automática via step-ca
- Validação bidirecional client/server
- Isolamento por tenant

### Rede
- Comunicação apenas HTTPS (porta 443)
- Sem portas abertas para entrada
- Outbound-only connectivity

## 📈 Performance

### Recursos Recomendados
- **CPU**: 2+ cores
- **RAM**: 4GB+ (2GB por tenant ativo)
- **Disk**: SSD recomendado
- **Network**: 100Mbps+ para scans grandes

### Otimizações
- Logs com rotação automática
- Limpeza automática de arquivos temporários
- Isolamento de processos por tenant
- Cache inteligente de resultados

## 📞 Suporte

### Arquivos de Log para Suporte
```bash
# Compactar logs para análise
sudo tar -czf vlxsam04-logs-$(date +%Y%m%d).tar.gz \
    /var/log/samureye-collector/ \
    /etc/samureye-collector/.env \
    /opt/samureye-collector/scripts/

# Enviar tar.gz para suporte
```

### Informações do Sistema
```bash
# Relatório completo do sistema
sudo /opt/samureye-collector/scripts/system-report.sh
```

---

## ✅ Status: Ubuntu 24.04 Compatível

Este script foi **totalmente atualizado e testado** para Ubuntu 24.04 LTS (Noble).

**Correções aplicadas**:
- ✅ Python 3.11 → Python 3.12
- ✅ netcat → netcat-openbsd  
- ✅ Validação automática de compatibilidade
- ✅ Dependências testadas e funcionando
- ✅ Log de compatibilidade gerado

**Data da última atualização**: 27/08/2025