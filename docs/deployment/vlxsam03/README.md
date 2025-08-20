# vlxsam03 - Database Server

## Visão Geral

O servidor vlxsam03 fornece toda a infraestrutura de dados para a plataforma SamurEye:
- **PostgreSQL 15** para dados da aplicação
- **Redis** para cache e sessões
- **MinIO** para armazenamento de arquivos
- **Grafana** para monitoramento e dashboards
- **Backup automático** de todos os dados

## Especificações

- **IP:** 172.24.1.153
- **OS:** Ubuntu 22.04 LTS
- **Portas:** 5432 (PostgreSQL), 6379 (Redis), 9000 (MinIO), 3000 (Grafana)
- **Storage:** Dados em /opt/data com backup em /opt/backup

## Instalação

### Executar Script de Instalação

```bash
# Conectar no servidor como root
ssh root@172.24.1.153

# Executar instalação
curl -fsSL https://raw.githubusercontent.com/SamurEye/deploy/main/vlxsam03/install.sh | bash

# OU clonar repositório e executar localmente
git clone https://github.com/SamurEye/SamurEye.git
cd SamurEye/docs/deployment/vlxsam03/
chmod +x install.sh
./install.sh
```

### O que o Script Instala

1. **PostgreSQL 15**
   - Configuração otimizada para SamurEye
   - Usuário e database 'samureye' 
   - Backup automático diário
   - Logs estruturados

2. **Redis**
   - Configuração para cache e sessões
   - Persistência configurada
   - Monitoramento ativo

3. **MinIO**
   - Object storage S3-compatível
   - Buckets para diferentes tipos de dados
   - Interface web de administração

4. **Grafana**
   - Dashboards de monitoramento
   - Integração com PostgreSQL
   - Alertas configurados

## Configuração Pós-Instalação

### 1. Configurar Senhas de Banco

```bash
# Alterar senha do usuário samureye no PostgreSQL
sudo -u postgres psql
ALTER USER samureye PASSWORD 'nova_senha_segura_aqui';
\q

# Atualizar arquivo de configuração
sudo nano /etc/samureye/.env
```

### 2. Configurar MinIO

```bash
# Acessar interface web MinIO
# https://172.24.1.153:9001 (admin/SamurEye2024!)

# Criar buckets necessários
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
pg_isready -h localhost -p 5432 -U samureye
redis-cli ping
curl http://localhost:9000/minio/health/live
```

### Testar Conexões Remotas

```bash
# Do vlxsam02, testar conexão
psql -h 172.24.1.153 -U samureye -d samureye_prod -c "SELECT version();"
redis-cli -h 172.24.1.153 ping
curl http://172.24.1.153:9000/minio/health/live
```

## Estrutura de Dados

### PostgreSQL Databases

```sql
-- Database principal da aplicação
samureye_prod

-- Tabelas principais:
- users                 -- Usuários do sistema
- tenants               -- Multi-tenancy
- collectors            -- Dispositivos coletores
- journeys              -- Jornadas de teste
- credentials           -- Integração Delinea
- threat_intelligence   -- Dados de ameaças
- activities            -- Logs de auditoria
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

### MinIO Buckets

```
# Arquivos da aplicação
samureye-app/
  ├── uploads/         # Uploads de usuários
  ├── reports/         # Relatórios gerados
  └── evidence/        # Evidências de scans

# Backups
samureye-backup/
  ├── database/        # Backups PostgreSQL
  ├── configs/         # Configurações
  └── logs/           # Logs arquivados
```

## Backup e Recuperação

### Backup Automático

```bash
# Backup diário configurado via cron
/opt/samureye/scripts/daily-backup.sh

# Localização dos backups
/opt/backup/
├── postgresql/      # Dumps SQL diários
├── redis/          # RDB snapshots
├── minio/          # Dados de objeto
└── configs/        # Configurações do sistema
```

### Restauração Manual

```bash
# Restaurar PostgreSQL
./scripts/restore-postgresql.sh [backup-date]

# Restaurar Redis
./scripts/restore-redis.sh [backup-date]

# Restaurar MinIO
./scripts/restore-minio.sh [backup-date]
```

## Monitoramento

### Grafana Dashboards

- **SamurEye Overview** - Status geral da plataforma
- **Database Metrics** - Performance PostgreSQL e Redis
- **Storage Metrics** - Utilização MinIO
- **System Resources** - CPU, memória, disco

### Métricas Principais

```bash
# PostgreSQL
- Conexões ativas
- Queries por segundo
- Tamanho do database
- Locks e deadlocks

# Redis  
- Memória utilizada
- Hit rate do cache
- Comandos por segundo
- Clientes conectados

# MinIO
- Espaço utilizado
- Objetos armazenados
- Bandwidth de upload/download
- Operações por segundo
```

## Troubleshooting

### Problemas PostgreSQL

```bash
# Verificar status
systemctl status postgresql

# Logs de erro
tail -f /var/log/postgresql/postgresql-15-main.log

# Conectividade
pg_isready -h localhost -p 5432

# Espaço em disco
df -h /var/lib/postgresql/
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

### Problemas MinIO

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