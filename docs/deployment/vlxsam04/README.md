# vlxsam04 - Collector Agent

## Visão Geral

O servidor vlxsam04 executa o agente coletor do SamurEye na rede interna:
- **Comunicação outbound-only** com mTLS e autenticação por certificado
- **Ferramentas de segurança** (Nmap, Nuclei, Masscan, Gobuster)
- **Telemetria em tempo real** via WebSocket e HTTPS
- **Execução de jornadas multi-tenant** de teste de segurança
- **Integração Object Storage** para upload de resultados
- **Monitoramento local** sem exposição externa
- **Autenticação step-ca** para certificados X.509

## Especificações

- **IP:** 192.168.100.151 (rede interna isolada)
- **OS:** Ubuntu 22.04 LTS
- **Comunicação:** Outbound HTTPS/WSS apenas (porta 443)
- **Autenticação:** mTLS com certificados X.509 (step-ca)
- **Usuário:** samureye-collector
- **Diretório:** /opt/samureye-collector
- **Runtime:** Python 3.11+ com Node.js 20.x (para ferramentas)
- **Storage:** Local + Object Storage (upload de resultados)

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
   - Python 3.11+ para o agente collector
   - Node.js 20.x para ferramentas modernas
   - Usuário dedicado samureye-collector
   - Estrutura de diretórios segura com isolamento

2. **Collector Agent Multi-Tenant**
   - Cliente HTTPS/WebSocket com mTLS
   - Sistema de telemetria em tempo real
   - Executor de comandos com sandbox
   - Logs estruturados por tenant
   - Integração Object Storage

3. **Ferramentas de Segurança Atualizadas**
   - Nmap 7.94+ com scripts NSE
   - Nuclei 3.x com templates atualizados
   - Masscan para scanning rápido
   - Gobuster para descoberta web
   - Custom tools para BAS (Breach & Attack Simulation)

4. **Segurança e Autenticação**
   - step-ca client para certificados
   - mTLS para todas comunicações
   - Validação de certificados X.509
   - Rotação automática de certificados

5. **Serviços Systemd**
   - samureye-collector (agente principal)
   - samureye-telemetry (métricas tempo real)
   - samureye-cert-renew (renovação certificados)
   - Scripts de health check multi-tenant

## Configuração Pós-Instalação

### 1. Configurar Certificados step-ca

```bash
# Configurar cliente step-ca e obter certificado inicial
./scripts/setup-step-ca.sh

# Verificar certificado X.509 gerado
step certificate inspect /opt/samureye-collector/certs/collector.crt

# Registrar collector na aplicação (via API ou interface web)
cat /opt/samureye-collector/certs/collector-id.txt

# Certificados são renovados automaticamente via step-ca
# Verificar status: systemctl status samureye-cert-renew
```

### 2. Configurar Endpoints e Multi-Tenancy

```bash
# Editar configuração principal
sudo nano /etc/samureye-collector/.env

# Endpoints principais:
SAMUREYE_API_URL=https://api.samureye.com.br
SAMUREYE_WS_URL=wss://api.samureye.com.br/ws
STEP_CA_URL=https://ca.samureye.com.br

# Multi-tenancy (configurado via API após registro)
COLLECTOR_TENANT_ID=auto-configured
COLLECTOR_ROLE=scanner
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
systemctl status samureye-cert-renew

# Health check completo multi-tenant
./scripts/health-check.sh

# Testar ferramentas atualizadas
nmap --version                    # 7.94+
nuclei --version                  # 3.x
masscan --version
gobuster version
step version                      # step-ca client
```

### Testar Comunicação

```bash
# Testar conectividade HTTPS com mTLS
./scripts/test-mtls-connection.sh

# Testar WebSocket real-time
./scripts/test-websocket.sh

# Testar upload Object Storage
./scripts/test-object-storage.sh

# Verificar logs de comunicação
tail -f /var/log/samureye-collector/communication.log
tail -f /var/log/samureye-collector/websocket.log
```

## Arquitetura do Collector

### Componentes Principais

```
/opt/samureye-collector/
├── agent/                  # Agente principal Python 3.11+
│   ├── main.py             # Loop principal multi-tenant
│   ├── api_client.py       # Cliente HTTPS/WebSocket com mTLS
│   ├── websocket_client.py # Cliente WebSocket real-time
│   ├── executor.py         # Executor sandbox para comandos
│   ├── telemetry.py        # Coleta de métricas tempo real
│   ├── security.py         # Validações mTLS e sandbox
│   ├── object_storage.py   # Cliente Object Storage
│   └── tenant_manager.py   # Gestão multi-tenant
├── certs/                  # Certificados X.509 step-ca
│   ├── collector.crt       # Certificado do collector
│   ├── collector.key       # Chave privada
│   ├── ca.crt              # CA root certificate
│   └── collector-id.txt    # ID único do collector
├── tools/                  # Ferramentas de segurança atualizadas
│   ├── nmap/               # Nmap 7.94+ com scripts
│   ├── nuclei/             # Nuclei 3.x com templates
│   ├── masscan/            # Masscan para scanning rápido
│   └── custom/             # Ferramentas customizadas BAS
├── logs/                   # Logs estruturados por tenant
│   ├── tenant-{id}/        # Logs por tenant
│   └── system/             # Logs de sistema
├── temp/                   # Arquivos temporários por tenant
│   └── tenant-{id}/        # Resultados por tenant
└── uploads/                # Área de upload Object Storage
    └── tenant-{id}/        # Uploads por tenant
```

### Fluxo de Comunicação Multi-Tenant

```
1. Autenticação mTLS Inicial
   - Collector → step-ca: Obter/renovar certificado X.509
   - Collector → API: Registrar com certificado mTLS
   - API → Collector: Confirmar registração e tenant assignment

2. Comunicação Real-time (WebSocket + mTLS)
   - Collector → API: Heartbeat + telemetria (30s)
   - API → Collector: Comandos de execução por tenant
   - Collector → API: Status de execução em tempo real

3. Transferência de Dados (HTTPS + mTLS)
   - Collector → Object Storage: Upload de resultados por tenant
   - Collector → API: Metadados e logs estruturados
   - API → Collector: Configurações e updates

4. Segurança e Isolamento
   - Sandbox por tenant para execução de comandos
   - Logs segregados por tenant
   - Object Storage com ACL por tenant
   - Renovação automática de certificados
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

## Telemetria Multi-Tenant Coletada

### Métricas de Sistema (Global)
- CPU: Uso por core, load average, temperatura
- Memória: Uso, disponível, swap, cache
- Disco: Espaço, I/O, inodes, performance
- Rede: Interfaces, tráfego, latência, conectividade
- Collector: Status, versão, uptime, certificados

### Métricas por Tenant
- Jornadas executadas: Status, duração, resultados
- Comandos executados: Tipo, sucesso/erro, recursos utilizados
- Descoberta de rede: Hosts ativos, serviços, mudanças
- Uploads Object Storage: Volume, latência, sucesso

### Métricas de Segurança (Por Tenant)
- Vulnerabilidades: CVEs identificados, severidade, status
- Superficie de ataque: Portas, serviços, protocolos expostos
- Configurações: Baselines, desvios, compliance
- EDR/AV Testing: Detecções, bypasses, false positives
- Indicators of Compromise: IOCs detectados, timestamps

### Métricas de Performance
- Latência de comunicação: API, WebSocket, Object Storage
- Throughput: Comandos/s, uploads/s, telemetria/s
- Recursos: CPU/memória por tenant, concorrência
- Erros: Taxa de erro por tipo, tenant, ferramenta

## Troubleshooting

### Problemas de Conectividade

```bash
# Verificar conectividade básica
ping api.samureye.com.br
curl -I https://api.samureye.com.br

# Testar mTLS com certificado do collector
./scripts/test-mtls-connection.sh

# Testar WebSocket
./scripts/test-websocket.sh

# Verificar certificados step-ca
step certificate inspect /opt/samureye-collector/certs/collector.crt
step certificate verify /opt/samureye-collector/certs/collector.crt

# Logs de comunicação
tail -f /var/log/samureye-collector/communication.log
tail -f /var/log/samureye-collector/websocket.log
tail -f /var/log/samureye-collector/mtls.log
```

### Problemas do Agente

```bash
# Status dos serviços multi-tenant
systemctl status samureye-collector
systemctl status samureye-telemetry
systemctl status samureye-cert-renew

# Logs detalhados por componente
tail -f /var/log/samureye-collector/agent.log
tail -f /var/log/samureye-collector/telemetry.log
tail -f /var/log/samureye-collector/tenant-{id}.log

# Logs de sistema
journalctl -u samureye-collector -f
journalctl -u samureye-telemetry -f

# Restart seguros dos serviços
systemctl restart samureye-collector
systemctl restart samureye-telemetry

# Verificar multi-tenancy
./scripts/check-tenant-isolation.sh
```

### Problemas de Ferramentas

```bash
# Verificar instalações atualizadas
which nmap nuclei masscan gobuster step
nmap --version                    # Deve ser 7.94+
nuclei --version                  # Deve ser 3.x+
step version                      # step-ca client

# Testar execução manual
nmap localhost
nuclei -target http://localhost -t /opt/samureye-collector/tools/nuclei/templates/

# Verificar permissões e sandbox
ls -la /opt/samureye-collector/tools/
./scripts/test-sandbox.sh

# Atualizar templates Nuclei
./scripts/update-nuclei-templates.sh
```

## Monitoramento

### Health Check Multi-Tenant

```bash
# Executar verificação completa multi-tenant
./scripts/health-check.sh

# Verificar conectividade (mTLS + WebSocket)
./scripts/check-connectivity.sh

# Status das ferramentas atualizadas
./scripts/check-tools.sh

# Verificar isolamento por tenant
./scripts/check-tenant-isolation.sh

# Testar Object Storage por tenant
./scripts/test-object-storage-tenant.sh

# Verificar certificados e renovação
./scripts/check-certificates.sh
```

### Logs Importantes Multi-Tenant

```bash
# Agente principal multi-tenant
tail -f /var/log/samureye-collector/agent.log

# Comunicação (HTTPS + WebSocket + mTLS)
tail -f /var/log/samureye-collector/communication.log
tail -f /var/log/samureye-collector/websocket.log
tail -f /var/log/samureye-collector/mtls.log

# Execução por tenant
tail -f /var/log/samureye-collector/execution.log
tail -f /var/log/samureye-collector/tenant-{id}.log

# Object Storage uploads
tail -f /var/log/samureye-collector/object-storage.log

# Telemetria e certificados
tail -f /var/log/samureye-collector/telemetry.log
tail -f /var/log/samureye-collector/certificates.log

# Sistema
journalctl -u samureye-collector -f
journalctl -u samureye-telemetry -f
journalctl -u samureye-cert-renew -f

# Logs agregados por tenant
find /var/log/samureye-collector/logs/tenant-{id}/ -name "*.log" -exec tail -f {} +
```

## Segurança

### Princípios de Segurança

1. **Outbound Only**: Nenhuma conexão inbound permitida
2. **mTLS Universal**: Todas comunicações com autenticação mútua
3. **Certificados X.509**: step-ca com renovação automática
4. **Isolamento Multi-Tenant**: Sandbox e logs separados por tenant
5. **Object Storage ACL**: Controle de acesso por tenant
6. **Execução Sandbox**: Comandos isolados com limitações de recursos
7. **Logs Auditados**: Rastreabilidade completa por tenant
8. **Validação de Comandos**: Whitelist de comandos permitidos
9. **Comunicação Criptografada**: TLS 1.3 para todas as conexões
10. **Rotação de Credenciais**: Certificados renovados automaticamente
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