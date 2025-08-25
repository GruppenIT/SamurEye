# vlxsam03 - Database Server

## Visão Geral

O servidor vlxsam03 fornece infraestrutura de dados local e conexões para a plataforma SamurEye:
- **Neon Database** (PostgreSQL serverless) para dados da aplicação
- **Redis** para cache e sessões
- **Google Cloud Storage** para object storage (via integração)
- **MinIO** (opcional) para armazenamento local de backup
- **Grafana** para monitoramento e dashboards
- **Sistema Multi-tenant** com isolamento de dados
- **Backup automático** de configurações e logs

## Especificações

- **IP:** 172.24.1.153
- **OS:** Ubuntu 22.04 LTS
- **Portas:** 6379 (Redis), 9000 (MinIO - opcional), 3000 (Grafana)
- **Database:** Neon Database (PostgreSQL serverless) - conexão remota
- **Object Storage:** Google Cloud Storage - integração via API
- **Storage Local:** Logs e backup em /opt/data

## Instalação

### Executar Script de Instalação

```bash
# Conectar no servidor como root
ssh root@172.24.1.153

# Executar instalação
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam03/install.sh | bash

# OU clonar repositório e executar localmente
git clone https://github.com/GruppenIT/SamurEye.git
cd SamurEye/docs/deployment/vlxsam03/
chmod +x install.sh
./install.sh
```

### O que o Script Instala

1. **Neon Database Configuration**
   - Configuração de conexão para PostgreSQL serverless
   - Variáveis de ambiente para DATABASE_URL
   - Scripts de teste de conectividade
   - Schema multi-tenant configurado

2. **Redis**
   - Configuração para cache e sessões
   - Persistência configurada
   - Suporte a session storage
   - Monitoramento ativo

3. **Object Storage Integration**
   - Configuração Google Cloud Storage
   - Environment variables para buckets
   - Scripts de teste de conectividade
   - MinIO local opcional para backup

4. **Grafana**
   - Dashboards de monitoramento multi-tenant
   - Integração com Neon Database
   - Métricas de sistema e aplicação
   - Alertas configurados

## Configuração Pós-Instalação

### 1. Configurar Neon Database

```bash
# As configurações do Neon Database são feitas via variáveis de ambiente
# Editar arquivo de configuração
sudo nano /etc/samureye/.env

# Configurar DATABASE_URL para Neon
DATABASE_URL=postgresql://user:pass@ep-xyz.us-east-1.aws.neon.tech/samureye?sslmode=require

# Testar conexão
./scripts/test-neon-connection.sh
```

### 2. Configurar Object Storage

```bash
# Object Storage é configurado automaticamente via Google Cloud Storage
# Verificar configuração
./scripts/test-object-storage.sh

# Configurar MinIO local (opcional - backup)
# Acessar interface web MinIO
# http://172.24.1.153:9001 (admin/SamurEye2024!)
./scripts/setup-minio-buckets.sh
```

### 3. Configurar Grafana

```bash
# Acessar Grafana
# http://172.24.1.153:3000 (admin/admin)

# Importar dashboards pré-configurados
./scripts/setup-grafana-dashboards.sh
```

## Verificação da Instalação

### Testar Serviços

```bash
# Verificar status de todos os serviços
./scripts/health-check.sh

# Testar conectividade individual
./scripts/test-neon-connection.sh
redis-cli ping
./scripts/test-object-storage.sh
curl http://localhost:9000/minio/health/live  # MinIO local (opcional)
```

### Testar Conexões Remotas

```bash
# Do vlxsam02, testar conexão
# Neon Database (remoto) - testar do vlxsam02
export DATABASE_URL="postgresql://..."
psql $DATABASE_URL -c "SELECT version();"

# Redis local
redis-cli -h 172.24.1.153 ping

# Object Storage (Google Cloud) - testar conectividade
curl -s "https://storage.googleapis.com" > /dev/null
echo "Object Storage: $?"

# MinIO local (opcional)
curl http://172.24.1.153:9000/minio/health/live
```

## Estrutura de Dados

### Neon Database (PostgreSQL Serverless)

```sql
-- Database principal da aplicação (Neon)
samureye_database

-- Tabelas principais (Multi-tenant):
- users                 -- Usuários globais e SOC
- tenants               -- Organizações/tenants
- tenant_users          -- Usuários por tenant
- sessions              -- Sessões de usuário
- collectors            -- Dispositivos coletores por tenant
- journeys              -- Jornadas de teste por tenant
- credentials           -- Integração Delinea por tenant
- threat_intelligence   -- Dados de ameaças compartilhados
- activities            -- Logs de auditoria por tenant
- object_entities       -- Metadados Object Storage
```

### Redis Estruturas

```
# Sessões de usuário
session:*

# Cache de dados frequentes
cache:tenants:*
cache:collectors:*
cache:credentials:*

# Filas de jobs
queue:journeys
queue:scans
queue:notifications
```

### Object Storage Structure

```
# Google Cloud Storage Buckets
repl-default-bucket-{REPL_ID}/
  ├── public/              # Assets públicos por tenant
  │   ├── tenant-1/        # Assets do tenant 1
  │   └── tenant-2/        # Assets do tenant 2
  └── .private/            # Arquivos privados
      ├── uploads/         # Uploads de usuários
      ├── reports/         # Relatórios por tenant
      └── evidence/        # Evidências de scans

# MinIO Local (Backup Opcional)
samureye-backup/
  ├── configs/         # Configurações do sistema
  ├── logs/            # Logs arquivados
  └── redis/           # Snapshots Redis
```

## Backup e Recuperação

### Backup Automático

```bash
# Backup diário configurado via cron
/opt/samureye/scripts/daily-backup.sh

# Localização dos backups locais
/opt/backup/
├── neon/            # Dumps Neon Database (diários)
├── redis/           # RDB snapshots
├── configs/         # Configurações do sistema
├── logs/            # Logs de sistema
└── object-storage/  # Backup metadados (opcional)

# Nota: Neon Database tem backup automático nativo
# Object Storage tem versionamento automático
```

### Restauração Manual

```bash
# Restaurar Neon Database (via backup local)
./scripts/restore-neon.sh [backup-date]

# Restaurar Redis
./scripts/restore-redis.sh [backup-date]

# Restaurar configurações
./scripts/restore-configs.sh [backup-date]

# Nota: Object Storage tem versionamento nativo
# Neon Database tem point-in-time recovery nativo
```

## Monitoramento

### Grafana Dashboards

- **SamurEye Multi-Tenant Overview** - Status geral por tenant
- **Neon Database Metrics** - Performance e conectividade
- **Redis Cache Metrics** - Performance de cache e sessões
- **Object Storage Metrics** - Utilização Google Cloud Storage
- **System Resources** - CPU, memória, disco vlxsam03

### Métricas Principais

```bash
# Neon Database
- Conectividade e latência
- Queries por segundo
- Tamanho do database por tenant
- Pool de conexões

# Redis Local
- Memória utilizada
- Hit rate do cache
- Sessões ativas por tenant
- Comandos por segundo

# Object Storage
- Usage por tenant
- Objetos por bucket
- API calls para Google Cloud
- Transferência de dados

# System
- CPU e memória vlxsam03
- Conectividade de rede
- Espaço em disco local
```

## Troubleshooting

### Problemas Neon Database

```bash
# Testar conectividade
./scripts/test-neon-connection.sh

# Verificar variáveis de ambiente
echo $DATABASE_URL

# Testar conexão manual
psql $DATABASE_URL -c "SELECT version();"

# Verificar latência
time psql $DATABASE_URL -c "SELECT 1;"

# Logs de conexão (no vlxsam02)
journalctl -u samureye-app -f | grep -i database
```

### Problemas Redis

```bash
# Status do serviço
systemctl status redis-server

# Logs
tail -f /var/log/redis/redis-server.log

# Conectividade e info
redis-cli info
redis-cli config get '*'
```

### Problemas Object Storage

```bash
# Testar conectividade Google Cloud Storage
./scripts/test-object-storage.sh

# Verificar variáveis de ambiente
echo $PUBLIC_OBJECT_SEARCH_PATHS
echo $PRIVATE_OBJECT_DIR

# Testar API calls
curl -s "https://storage.googleapis.com" > /dev/null
echo "GCS API: $?"

# Verificar permissões (no vlxsam02)
journalctl -u samureye-app -f | grep -i "object.*storage"
```

### Problemas MinIO Local (Opcional)

```bash
# Status do serviço
systemctl status minio

# Logs
journalctl -u minio -f

# Health check
curl http://localhost:9000/minio/health/live
```

## Manutenção

### Updates Regulares

```bash
# Update PostgreSQL
./scripts/update-postgresql.sh

# Update Redis
./scripts/update-redis.sh

# Update MinIO
./scripts/update-minio.sh
```

### Limpeza de Dados

```bash
# Limpar logs antigos
./scripts/cleanup-logs.sh

# Limpar backups antigos (manter últimos 30 dias)
./scripts/cleanup-backups.sh

# Otimizar PostgreSQL
./scripts/optimize-postgresql.sh
```

### Monitoramento de Espaço

```bash
# Verificar espaço em disco
df -h

# Tamanhos dos databases
./scripts/check-database-sizes.sh

# Tamanho dos backups
./scripts/check-backup-sizes.sh
```

## Segurança

### Configurações de Acesso

```bash
# PostgreSQL: Apenas rede interna
# /etc/postgresql/15/main/postgresql.conf
listen_addresses = '172.24.1.153'

# /etc/postgresql/15/main/pg_hba.conf
host samureye_prod samureye 172.24.1.0/24 md5

# Redis: Apenas rede interna
# /etc/redis/redis.conf
bind 172.24.1.153

# MinIO: HTTPS recomendado para produção
```

### Firewall

```bash
# Portas abertas apenas para rede interna
ufw allow from 172.24.1.0/24 to any port 5432   # PostgreSQL
ufw allow from 172.24.1.0/24 to any port 6379   # Redis
ufw allow from 172.24.1.0/24 to any port 9000   # MinIO
ufw allow from 172.24.1.0/24 to any port 3000   # Grafana
```

### Credenciais Padrão

```bash
# PostgreSQL
Usuário: samureye
Senha: SamurEye2024! (ALTERAR)
Database: samureye_prod

# MinIO
Access Key: samureye
Secret Key: SamurEye2024! (ALTERAR)

# Grafana
Usuário: admin
Senha: admin (ALTERAR no primeiro login)
```