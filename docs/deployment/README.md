# SamurEye - Guia de Deploy Produção

Este guia fornece instruções completas para deploy da plataforma SamurEye em ambiente de produção com 4 servidores dedicados.

## Arquitetura de Produção

```
┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│   vlxsam01      │    vlxsam02     │    vlxsam03     │    vlxsam04     │
│   (Gateway)     │  (Frontend +    │   (Database)    │  (Collector)    │
│                 │   Backend)      │                 │                 │
│ 172.24.1.151    │ 172.24.1.152    │ 172.24.1.153    │ 192.168.100.151 │
│                 │                 │                 │                 │
│ - NGINX         │ - Node.js App   │ - PostgreSQL    │ - Agent         │
│ - SSL/TLS       │ - Scanner       │ - Redis         │ - Outbound only │
│ - Rate Limit    │ - API           │ - MinIO         │ - Tools         │
│ - Load Balance  │ - WebSocket     │ - Monitoring    │ - Telemetry     │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

## Pré-requisitos

- **OS:** Ubuntu 22.04 LTS
- **Domínio:** samureye.com.br (*.samureye.com.br)
- **Certificado SSL:** Wildcard Let's Encrypt configurado
- **Conectividade:** Todos os servidores com acesso à internet
- **Credenciais:** Usuário com privilégios sudo em todos os servidores

## Instalação por Servidor

Execute os servidores na seguinte ordem para resolver dependências:

### 1. vlxsam03 - Database Cluster (Primeiro)
**IP:** 172.24.1.153 | **Documentação:** [vlxsam03/README.md](vlxsam03/README.md)

PostgreSQL + Redis + MinIO + Grafana
```bash
ssh root@172.24.1.153
# Instalação manual - seguir README específico
```

### 2. vlxsam01 - Gateway/NGINX  
**IP:** 172.24.1.151 | **Documentação:** [vlxsam01/README.md](vlxsam01/README.md)

SSL Termination + Rate Limiting + Proxy Reverso
```bash
ssh root@172.24.1.151
./vlxsam01/install.sh
```

### 3. vlxsam02 - Application Server
**IP:** 172.24.1.152 | **Documentação:** [vlxsam02/README.md](vlxsam02/README.md)

React Frontend + Node.js Backend + Scanner Service
```bash
ssh root@172.24.1.152
./vlxsam02/install.sh
```

### 4. vlxsam04 - Collector Agent
**IP:** 192.168.100.151 | **Documentação:** [vlxsam04/README.md](vlxsam04/README.md)

Agente Coletor (Outbound-only)
```bash
ssh root@192.168.100.151
# Instalação manual - seguir README específico
```

## Verificação da Instalação

Após completar todos os servidores, execute a verificação completa:

```bash
# Script de verificação consolidada (execute de qualquer local)
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/scripts/verify-full-installation.sh | bash

# OU clonar e executar localmente
git clone https://github.com/GruppenIT/SamurEye.git
cd SamurEye/docs/deployment/
chmod +x scripts/verify-full-installation.sh
./scripts/verify-full-installation.sh
```

Este script verifica:
- ✅ Conectividade entre todos os servidores
- ✅ Status de todos os serviços  
- ✅ Certificados SSL e HTTPS
- ✅ Integrações e dependências
- ✅ Performance básica dos endpoints

## Configuração Pós-Instalação

### 1. Configurar Variáveis de Ambiente
```bash
# Em cada servidor, editar as variáveis específicas
nano /etc/samureye/.env
```

### 2. Configurar Integração Delinea
```bash
# No vlxsam02, configurar API keys
./scripts/configure-delinea.sh
```

### 3. Testar Funcionalidades
```bash
# Executar testes de integração
./scripts/integration-tests.sh
```

## Monitoramento e Logs

### Verificar Status Geral
```bash
# Status de todos os serviços
systemctl status samureye-*

# Logs em tempo real
tail -f /var/log/samureye/*.log
```

### URLs de Acesso
- **Frontend:** https://app.samureye.com.br
- **API:** https://api.samureye.com.br
- **Monitoring:** https://monitor.samureye.com.br
- **Admin:** https://admin.samureye.com.br

## Troubleshooting

### Problemas Comuns

1. **Certificado SSL inválido**
   ```bash
   ./scripts/renew-ssl.sh
   ```

2. **Banco de dados inacessível**
   ```bash
   ./scripts/check-database.sh
   ```

3. **Aplicação não responde**
   ```bash
   ./scripts/restart-app.sh
   ```

4. **Collector desconectado**
   ```bash
   ./scripts/check-collector.sh
   ```

### Logs de Debug
```bash
# Gateway (vlxsam01)
tail -f /var/log/nginx/error.log

# Application (vlxsam02) 
tail -f /var/log/samureye/app.log

# Database (vlxsam03)
tail -f /var/log/postgresql/postgresql-15-main.log

# Collector (vlxsam04)
tail -f /var/log/samureye/collector.log
```

## Backup e Recuperação

### Backup Diário Automatizado
```bash
# Configurar backup automático
crontab -e
# 0 2 * * * /opt/samureye/scripts/daily-backup.sh
```

### Recuperação de Emergência
```bash
# Restaurar a partir de backup
./scripts/restore-from-backup.sh [backup-date]
```

## Manutenção

### Updates Regulares
```bash
# Update da aplicação (vlxsam02)
./scripts/update-app.sh

# Update do sistema (todos os servidores)
./scripts/system-update.sh
```

### Renovação de Certificados
```bash
# Renovar certificados SSL (automático via cron)
./scripts/renew-ssl.sh --check
```

## Suporte

Para suporte técnico:
- **Email:** suporte@samureye.com.br  
- **Documentação:** https://docs.samureye.com.br
- **Status:** https://status.samureye.com.br