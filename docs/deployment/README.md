# SamurEye On-Premise Deployment Guide

Este diretório contém todos os scripts e documentação necessários para implementar o SamurEye em ambiente on-premise, incluindo scripts de **hard reset completo** para recuperação de ambiente corrompido.

## 🎯 Cenários de Uso

### ✅ Instalação Nova (Fresh Install)
Para novo ambiente, use os scripts de instalação padrão:
- [vlxsam01/install.sh](vlxsam01/install.sh) - Gateway
- [vlxsam02/install.sh](vlxsam02/install.sh) - Application  
- [vlxsam03/install.sh](vlxsam03/install.sh) - Database
- [vlxsam04/install.sh](vlxsam04/install.sh) - Collector

### 🔥 **HARD RESET (Ambiente Corrompido)**
Para ambiente corrompido ou reset completo, execute os scripts individualmente:
- [vlxsam03/install-hard-reset.sh](vlxsam03/install-hard-reset.sh) - Database (PRIMEIRO)
- [vlxsam02/install-hard-reset.sh](vlxsam02/install-hard-reset.sh) - Application
- [vlxsam01/install-hard-reset.sh](vlxsam01/install-hard-reset.sh) - Gateway
- [vlxsam04/install-hard-reset.sh](vlxsam04/install-hard-reset.sh) - Collector

## 🏗️ Arquitetura On-Premise

```
┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│   vlxsam01      │    vlxsam02     │    vlxsam03     │    vlxsam04     │
│   (Gateway)     │  (Application)  │   (Database)    │  (Collector)    │
│                 │                 │                 │                 │
│ 192.168.100.151 │ 192.168.100.152 │ 192.168.100.153 │ 192.168.100.154 │
│                 │                 │                 │                 │
│ - NGINX Proxy   │ - Node.js 20    │ - PostgreSQL 16 │ - Python 3.11   │
│ - SSL/TLS       │ - SamurEye App  │ - Redis         │ - Node.js 20     │
│ - step-ca       │ - Port 5000     │ - MinIO         │ - Security Tools │
│ - Certificates  │ - API + WebUI   │ - Grafana       │ - Agent Service  │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

## 🚀 Quick Start - HARD RESET

Se seu ambiente está corrompido e você precisa fazer reset completo, execute os scripts **NA ORDEM CORRETA**:

**⚠️ IMPORTANTE**: Execute cada script em seu respectivo servidor, respeitando a ordem de dependências!

**⚠️ ATENÇÃO**: Os scripts fazem reset COMPLETO removendo todos os dados!

## 📋 Ordem de Execução - Hard Reset

Os scripts devem ser executados na seguinte ordem para respeitar dependências:

### 1. vlxsam03 - Database Server (PRIMEIRO)
```bash
ssh root@192.168.100.153
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam03/install-hard-reset.sh | bash
```
- Remove PostgreSQL, Redis, MinIO, Grafana completamente
- **APAGA TODOS OS DADOS** do banco
- Reinstala PostgreSQL 16 com configuração SamurEye
- Cria banco `samureye` do zero

### 2. vlxsam02 - Application Server
```bash
ssh root@192.168.100.152
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash
```
- Remove Node.js e aplicação SamurEye completamente
- Limpa dados da aplicação
- Reinstala Node.js 20 e aplicação
- Conecta ao banco limpo no vlxsam03

### 3. vlxsam01 - Gateway
```bash
ssh root@192.168.100.151
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/install-hard-reset.sh | bash
```
- Remove NGINX e step-ca completamente
- **PRESERVA certificados SSL válidos**
- Reinstala NGINX e step-ca
- Configura proxy para vlxsam02

### 4. vlxsam04 - Collector Agent
```bash
ssh root@192.168.100.154
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/install-hard-reset.sh | bash
```
- Remove Python, Node.js e ferramentas
- Reinstala ambiente completo
- Configura agente coletor
- Instala Nmap, Nuclei, Masscan, Gobuster

## 🔧 Funcionalidades dos Scripts Hard Reset

### 🛡️ Preservação de Dados Críticos
- **vlxsam01**: Backup automático de certificados SSL válidos
- **Todos**: Logs de execução detalhados para auditoria
- **Todos**: Validação de pré-requisitos antes de executar

### 🧹 Limpeza Completa
- Remove usuários, serviços e diretórios completamente
- Limpa cache de sistema e dependências
- Remove repositórios e chaves antigas
- Reset de configurações de firewall

### ✅ Validação Pós-Reset
- Testes de conectividade entre servidores
- Verificação de serviços ativos
- Validação de portas abertas
- Teste de APIs e endpoints

## 📊 Monitoramento Pós-Reset

### Comandos Úteis

**vlxsam03 - Database:**
```bash
# Testar todos os serviços
/usr/local/bin/test-samureye-db.sh

# Status individual
systemctl status postgresql redis-server minio grafana-server
```

**vlxsam02 - Application:**
```bash
# Status da aplicação
systemctl status samureye-app

# Teste de API
curl http://localhost:5000/api/health

# Logs da aplicação
journalctl -u samureye-app -f
```

**vlxsam01 - Gateway:**
```bash
# Status dos serviços
systemctl status nginx step-ca

# Teste de conectividade
curl -I https://app.samureye.com.br

# Logs do NGINX
tail -f /var/log/nginx/access.log
```

**vlxsam04 - Collector:**
```bash
# Status do collector
systemctl status samureye-collector

# Registrar no servidor
/opt/samureye/collector/scripts/register.sh

# Logs do collector
tail -f /var/log/samureye-collector/collector.log
```

## 🔐 Credenciais Padrão Pós-Reset

### Banco de Dados (vlxsam03)
- **PostgreSQL**: `samureye` / `samureye123`
- **Redis**: Senha `redis123`
- **MinIO**: `minio` / `minio123`
- **Grafana**: `admin` / `grafana123`

### Aplicação (vlxsam02)
- **Admin SamurEye**: `admin@samureye.local` / `SamurEye2024!`

### URLs de Acesso
- **App**: https://app.samureye.com.br
- **API**: https://api.samureye.com.br  
- **Grafana**: http://192.168.100.153:3000
- **MinIO**: http://192.168.100.153:9001

## 🔧 Resolução de Problemas

### Problema: Certificados SSL Expirados
```bash
# No vlxsam01 após reset
certbot --nginx -d samureye.com.br -d *.samureye.com.br
```

### Problema: Banco de Dados Não Conecta
```bash
# No vlxsam03
systemctl restart postgresql
/usr/local/bin/test-samureye-db.sh
```

### Problema: Aplicação Não Inicia
```bash
# No vlxsam02
systemctl restart samureye-app
journalctl -u samureye-app -f
```

### Problema: Collector Não Registra
```bash
# No vlxsam04
/opt/samureye/collector/scripts/register.sh
systemctl restart samureye-collector
```

## 📚 Documentação Detalhada

Cada servidor possui documentação específica:

- **[vlxsam01/README.md](vlxsam01/README.md)** - Gateway NGINX + SSL
- **[vlxsam02/README.md](vlxsam02/README.md)** - Application Server
- **[vlxsam03/README.md](vlxsam03/README.md)** - Database Cluster
- **[vlxsam04/README.md](vlxsam04/README.md)** - Collector Agent
- **[NETWORK-ARCHITECTURE.md](NETWORK-ARCHITECTURE.md)** - Arquitetura de Rede

## ⚠️ Avisos Importantes

1. **Backup**: Scripts de hard reset fazem backup automático de certificados, mas sempre verifique backups antes de executar

2. **Ordem**: Sempre execute na ordem correta (vlxsam03 → vlxsam02 → vlxsam01 → vlxsam04)

3. **Conectividade**: Certifique-se que todos os servidores têm acesso à internet

4. **Firewall**: Scripts configuram firewall automaticamente para rede 192.168.100.0/24

5. **DNS**: Configure DNS para apontar domínios para vlxsam01 (192.168.100.151)

## 🆘 Suporte

Em caso de problemas durante o reset:

1. Verifique logs detalhados de cada script
2. Execute testes de conectividade entre servidores  
3. Consulte documentação específica de cada servidor
4. Use scripts de diagnóstico incluídos em cada servidor