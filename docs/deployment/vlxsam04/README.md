# vlxsam04 - Collector Agent

## Visão Geral

O servidor vlxsam04 executa o agente coletor do SamurEye na rede interna:
- **Comunicação outbound-only** com a plataforma
- **Ferramentas de segurança** (Nmap, Nuclei, etc.)
- **Telemetria em tempo real** de sistema e rede
- **Execução de jornadas** de teste de segurança
- **Monitoramento local** sem exposição externa

## Especificações

- **IP:** 192.168.100.151 (rede interna)
- **OS:** Ubuntu 22.04 LTS
- **Comunicação:** Outbound HTTPS apenas (porta 443)
- **Usuário:** samureye-collector
- **Diretório:** /opt/samureye-collector

## Instalação

### Executar Script de Instalação

```bash
# Conectar no servidor como root
ssh root@192.168.100.151

# Executar instalação
curl -fsSL https://raw.githubusercontent.com/SamurEye/deploy/main/vlxsam04/install.sh | bash

# OU clonar repositório e executar localmente
git clone https://github.com/SamurEye/SamurEye.git
cd SamurEye/docs/deployment/vlxsam04/
chmod +x install.sh
./install.sh
```

### O que o Script Instala

1. **Sistema Base**
   - Python 3.10+ para o agente collector
   - Ferramentas de segurança (Nmap, Nuclei)
   - Usuário dedicado samureye-collector
   - Estrutura de diretórios segura

2. **Collector Agent**
   - Cliente HTTPS para comunicação com app
   - Sistema de telemetria local
   - Executor de comandos seguro
   - Logs estruturados

3. **Ferramentas de Segurança**
   - Nmap completo com scripts
   - Nuclei com templates atualizados
   - Masscan para scanning rápido
   - Gobuster para descoberta web

4. **Serviços**
   - samureye-collector (agente principal)
   - samureye-telemetry (coleta de métricas)
   - Scripts de health check

## Configuração Pós-Instalação

### 1. Configurar Certificado do Collector

```bash
# O script gerará um certificado único para este collector
# Copie a chave pública para registrar na aplicação
cat /opt/samureye-collector/certs/collector.pub

# Registre este collector na aplicação via interface web
# Usado para autenticação mútua
```

### 2. Configurar Endpoint da Aplicação

```bash
# Editar configuração para apontar para vlxsam02
sudo nano /etc/samureye-collector/.env

# Variável principal:
SAMUREYE_API_URL=https://api.samureye.com.br
```

### 3. Testar Conectividade

```bash
# Testar comunicação com a aplicação
./scripts/test-connectivity.sh

# Verificar registro do collector
./scripts/check-registration.sh
```

## Verificação da Instalação

### Testar Serviços

```bash
# Verificar status dos serviços
systemctl status samureye-collector
systemctl status samureye-telemetry

# Health check completo
./scripts/health-check.sh

# Testar ferramentas
nmap --version
nuclei --version
```

### Testar Comunicação

```bash
# Testar conectividade HTTPS com vlxsam02
curl -v https://api.samureye.com.br/api/health

# Verificar logs de comunicação
tail -f /var/log/samureye-collector/communication.log
```

## Arquitetura do Collector

### Componentes Principais

```
/opt/samureye-collector/
├── agent/              # Agente principal Python
│   ├── main.py         # Loop principal
│   ├── api_client.py   # Cliente HTTPS
│   ├── executor.py     # Executor de comandos
│   ├── telemetry.py    # Coleta de métricas
│   └── security.py     # Validações de segurança
├── certs/              # Certificados do collector
├── tools/              # Ferramentas de segurança
├── logs/               # Logs locais
└── temp/               # Arquivos temporários
```

### Fluxo de Comunicação

```
1. Collector → API (HTTPS)
   - Heartbeat a cada 30 segundos
   - Envio de telemetria
   - Recebimento de comandos

2. API → Collector (via HTTPS response)
   - Comandos de execução
   - Configurações
   - Updates de ferramentas

3. Collector → API (HTTPS)
   - Resultados de execução
   - Logs estruturados
   - Status de saúde
```

## Ferramentas Disponíveis

### Nmap (Descoberta de Rede)
```bash
# Scan básico de rede
nmap -sn 192.168.100.0/24

# Scan de portas com service detection
nmap -sV -sC target.example.com

# Scan de vulnerabilidades
nmap --script vuln target.example.com
```

### Nuclei (Teste de Vulnerabilidades)
```bash
# Scan básico
nuclei -target http://example.com

# Com templates específicos
nuclei -t cves/ -target http://example.com

# Scan abrangente
nuclei -t vulnerabilities/ -target http://example.com
```

### Ferramentas Auxiliares
```bash
# Masscan (scanning rápido)
masscan -p80,443 192.168.1.0/24 --rate=1000

# Gobuster (descoberta web)
gobuster dir -u http://example.com -w /usr/share/wordlists/common.txt
```

## Telemetria Coletada

### Métricas de Sistema
- CPU: Uso por core, load average
- Memória: Uso, disponível, swap
- Disco: Espaço, I/O, inodes
- Rede: Interfaces, tráfego, conectividade

### Métricas de Rede
- Descoberta de dispositivos ativos
- Mapeamento de portas abertas
- Identificação de serviços
- Mudanças na topologia

### Métricas de Segurança
- Vulnerabilidades identificadas
- Serviços expostos
- Configurações inseguras
- Indicadores de comprometimento

## Troubleshooting

### Problemas de Conectividade

```bash
# Verificar conectividade básica
ping api.samureye.com.br
curl -I https://api.samureye.com.br

# Testar com certificado do collector
./scripts/test-auth.sh

# Logs de comunicação
tail -f /var/log/samureye-collector/communication.log
```

### Problemas do Agente

```bash
# Status dos serviços
systemctl status samureye-collector
systemctl status samureye-telemetry

# Logs detalhados
tail -f /var/log/samureye-collector/agent.log
tail -f /var/log/samureye-collector/telemetry.log

# Restart dos serviços
systemctl restart samureye-collector
```

### Problemas de Ferramentas

```bash
# Verificar instalações
which nmap nuclei masscan gobuster

# Testar execução manual
nmap localhost
nuclei --version

# Verificar permissões
ls -la /opt/samureye-collector/tools/
```

## Monitoramento

### Health Check Local

```bash
# Executar verificação completa
./scripts/health-check.sh

# Verificar apenas conectividade
./scripts/check-connectivity.sh

# Status das ferramentas
./scripts/check-tools.sh
```

### Logs Importantes

```bash
# Agente principal
tail -f /var/log/samureye-collector/agent.log

# Comunicação com API
tail -f /var/log/samureye-collector/communication.log

# Execução de ferramentas
tail -f /var/log/samureye-collector/execution.log

# Telemetria
tail -f /var/log/samureye-collector/telemetry.log

# Sistema
journalctl -u samureye-collector -f
```

## Segurança

### Princípios de Segurança

1. **Outbound Only**: Nenhuma conexão inbound permitida
2. **Certificado Único**: Cada collector tem certificado próprio
3. **Validação Rigorosa**: Todos os comandos são validados
4. **Logs Completos**: Todas as ações são logadas
5. **Usuário Limitado**: Execução com usuário não-privilegiado

### Firewall Configurado

```bash
# Regras UFW aplicadas
ufw default deny incoming    # Bloquear tudo que entra
ufw default allow outgoing   # Permitir tudo que sai
ufw allow out 443           # HTTPS para comunicação
ufw allow out 53            # DNS
ufw allow in on lo          # Loopback local
```

### Validações de Comando

```python
# Comandos permitidos (whitelist)
ALLOWED_TOOLS = ['nmap', 'nuclei', 'masscan', 'gobuster']
BLOCKED_PATTERNS = ['rm -rf', 'dd if=', 'format', 'mkfs']
SAFE_TARGETS_ONLY = ['192.168.0.0/16', '10.0.0.0/8', '172.16.0.0/12']
```

## Manutenção

### Updates do Collector

```bash
# Update automático via API
# O collector recebe comandos de update da aplicação

# Update manual
./scripts/update-collector.sh

# Update das ferramentas
./scripts/update-security-tools.sh
```

### Limpeza de Dados

```bash
# Limpeza automática (via cron)
# - Logs antigos (>30 dias)
# - Arquivos temporários (>7 dias)
# - Resultados de scan antigos (>30 dias)

# Limpeza manual
./scripts/cleanup-old-data.sh
```

### Backup de Configurações

```bash
# Backup das configurações e certificados
./scripts/backup-config.sh

# Localização do backup
/opt/backup/collector-config-YYYYMMDD.tar.gz
```

## Registro na Aplicação

### Processo de Enrollment

1. **Gerar Certificado**: Durante instalação
2. **Obter Chave Pública**: `/opt/samureye-collector/certs/collector.pub`
3. **Registrar na App**: Via interface web em "Collectors"
4. **Ativar Collector**: Aprovar na aplicação
5. **Iniciar Serviços**: Collector começa comunicação

### Status na Aplicação

- **Online**: Heartbeat recente (<2 minutos)
- **Offline**: Sem heartbeat (>5 minutos)  
- **Error**: Erro de comunicação ou execução
- **Pending**: Aguardando aprovação

### Credenciais e IDs

```bash
# ID único do collector (gerado na instalação)
cat /opt/samureye-collector/collector-id.txt

# Certificado público (para registro)
cat /opt/samureye-collector/certs/collector.pub

# Informações do sistema
cat /opt/samureye-collector/system-info.json
```