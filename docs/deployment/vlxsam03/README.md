# vlxsam03 - Database & Services Server

## Visão Geral

O servidor vlxsam03 é o centro de dados e serviços da plataforma SamurEye, fornecendo infraestrutura completa através de instalação totalmente automatizada:

- **PostgreSQL 16 Local** - Banco de dados principal com configuração TCP/IP automática
- **Redis** - Cache e gerenciamento de sessões 
- **MinIO** - Armazenamento de objetos local para backups
- **Grafana** - Dashboards de monitoramento e métricas
- **Sistema Multi-tenant** - Isolamento completo de dados entre organizações
- **Instalação Reset Automática** - Script install.sh funciona como mecanismo de reset confiável
- **Estrutura de Banco Automática** - Schema multi-tenant criado automaticamente

## Especificações

- **IP:** 172.24.1.153
- **OS:** Ubuntu 24.04 LTS  
- **Portas:** 5432 (PostgreSQL), 6379 (Redis), 9000 (MinIO), 3000 (Grafana)
- **Database:** PostgreSQL 16 local com TCP/IP configurado automaticamente
- **Storage:** MinIO para objetos locais em /var/lib/minio
- **Dados:** Diretório /opt/data para backups e configurações

## Instalação Totalmente Automatizada

### Script de Instalação (Mecanismo de Reset)

O script `install.sh` funciona como um mecanismo de **reset completo e confiável** para o servidor vlxsam03. Pode ser executado quantas vezes necessário, sempre resultando em uma instalação limpa e funcional.

```bash
# Conectar no servidor como root
ssh root@172.24.1.153

# Executar instalação/reset (100% automatizado)
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam03/install.sh | bash
```

### O que o Script Instala Automaticamente

1. **PostgreSQL 16 Local**
   - Instalação limpa com detecção inteligente de problemas
   - Banco `samureye_db` criado automaticamente
   - Usuário `samureye` configurado com permissões
   - Configurações TCP/IP aplicadas automaticamente
   - Schema multi-tenant completo instalado
   - Reset automático em caso de corrupção de cluster

2. **Redis**
   - Servidor configurado na porta 6379
   - Senha: `SamurEye2024Redis!`
   - Configuração otimizada para sessões
   - Testes de conectividade automáticos

3. **MinIO (Armazenamento Local)**
   - Servidor na porta 9000
   - Credenciais: `admin/SamurEye2024!`
   - Estrutura de buckets criada automaticamente
   - Configurado para backups locais

4. **Grafana**
   - Servidor na porta 3000
   - Credenciais: `admin/SamurEye2024!`
   - Integração com PostgreSQL configurada
   - Dashboards básicos instalados

## Verificação Pós-Instalação (Tudo Automatizado)

### Credenciais Instaladas Automaticamente

Após a instalação, todos os serviços estão configurados com as seguintes credenciais:

```
PostgreSQL:
- Host: 172.24.1.153:5432
- Database: samureye_db
- Usuário: samureye
- Senha: SamurEye2024DB!

Redis:
- Host: 172.24.1.153:6379
- Senha: SamurEye2024Redis!

MinIO:
- Interface: http://172.24.1.153:9000
- Credenciais: admin/SamurEye2024!

Grafana:
- Interface: http://172.24.1.153:3000
- Credenciais: admin/SamurEye2024!
```

### Scripts de Teste Automático

```bash
# Testar conectividade PostgreSQL (automaticamente instalado)
/opt/samureye/scripts/test-postgres-connection.sh

# Verificar todos os serviços
/opt/samureye/scripts/health-check.sh

# Verificar configurações
cat /etc/samureye/.env
```

## Testes de Conectividade

### Teste Local (no próprio vlxsam03)

```bash
# Teste completo automático
/opt/samureye/scripts/health-check.sh

# Teste específico PostgreSQL (mostra latência e tabelas)  
/opt/samureye/scripts/test-postgres-connection.sh

# Testes individuais
systemctl status postgresql redis-server grafana-server minio
redis-cli -a 'SamurEye2024Redis!' ping
curl -s http://localhost:9000/minio/health/live
```

### Teste Remoto (de outros servidores vlxsam)

```bash
# Do vlxsam02, testar conectividade com vlxsam03
PGPASSWORD='SamurEye2024DB!' psql -h 172.24.1.153 -U samureye -d samureye_db -c "SELECT version();"

# Redis remoto
redis-cli -h 172.24.1.153 -a 'SamurEye2024Redis!' ping

# MinIO remoto
curl -s http://172.24.1.153:9000/minio/health/live
```

## Estrutura de Dados

### PostgreSQL Local

```sql
-- Database principal da aplicação (Local)
samureye_db

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

## Resolução de Problemas

### Reset Completo (Mecanismo Confiável)

Se houver qualquer problema com a instalação, execute o reset automático:

```bash
# Reset completo - funciona 100% das vezes
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam03/install.sh | bash
```

### Problemas Específicos

```bash
# PostgreSQL não conecta
systemctl restart postgresql
/opt/samureye/scripts/test-postgres-connection.sh

# Reset emergencial PostgreSQL apenas
samureye-reset-postgres

# Redis não responde  
systemctl restart redis-server
redis-cli -a 'SamurEye2024Redis!' ping

# MinIO não inicia
systemctl restart minio
curl -s http://localhost:9000/minio/health/live
```

## Backup e Recuperação

### Backup Automático (Configurado Automaticamente)

```bash
# Backup diário via cron (já configurado)
/opt/samureye/scripts/daily-backup.sh

# Localização dos backups
/opt/backup/
├── postgresql/      # Dumps PostgreSQL locais  
├── redis/          # Snapshots Redis
├── configs/        # Configurações do sistema
└── logs/           # Logs arquivados
```

### Restauração Manual

```bash  
# Restaurar PostgreSQL local
/opt/samureye/scripts/restore-postgresql.sh [backup-date]

# Restaurar Redis
/opt/samureye/scripts/restore-redis.sh [backup-date]
```

## Monitoramento e Logs

### Logs dos Serviços

```bash
# Logs PostgreSQL
journalctl -u postgresql -f

# Logs Redis  
journalctl -u redis-server -f

# Logs MinIO
journalctl -u minio -f

# Logs Grafana
journalctl -u grafana-server -f

# Logs do sistema SamurEye
tail -f /var/log/samureye/vlxsam03.log
```

### Métricas Automáticas

- **Grafana**: Dashboards automáticos em http://172.24.1.153:3000
- **Health Checks**: Scripts automáticos em `/opt/samureye/scripts/`  
- **System Metrics**: PostgreSQL performance, Redis uso, storage disponível

## Arquivos Importantes

```
/opt/samureye/scripts/     # Scripts de teste e manutenção
/etc/samureye/.env         # Configurações de ambiente  
/opt/backup/              # Backups locais automáticos
/var/log/samureye/        # Logs da aplicação
/var/lib/minio/           # Dados MinIO
/etc/postgresql/16/main/  # Configurações PostgreSQL
```

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

## Troubleshooting e Reset

### Problemas PostgreSQL

Se o PostgreSQL não estiver funcionando corretamente após a instalação, o script inclui funcionalidades de reset automático:

```bash
# Testar conectividade PostgreSQL com auto-detecção
/opt/samureye/scripts/test-postgres-connection.sh

# Reset completo PostgreSQL (em caso de problemas de cluster)
samureye-reset-postgres

# OU usando o caminho completo
/opt/samureye/scripts/reset-postgres.sh
```

### Reset Completo do Servidor vlxsam03

Para um reset completo do servidor (equivalente a reinstalação):

```bash
# Re-executar script de instalação (funciona como reset automático)
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam03/install.sh | bash
```

O script de instalação foi projetado para funcionar como um **"reset" confiável** do servidor:

- ✅ **Detecta automaticamente** problemas de cluster PostgreSQL
- ✅ **Reinstala PostgreSQL** se necessário (limpeza completa)
- ✅ **Recria usuários e banco** do zero
- ✅ **Configura todas as permissões** automaticamente
- ✅ **Testa conectividade** com múltiplos métodos
- ✅ **Cria scripts de recuperação** automática

### Detecção Automática de Conexão

O sistema detecta automaticamente a melhor forma de conectar no PostgreSQL:

1. **Conexão local via postgres user** (padrão vlxsam03)
2. **Conexão via localhost** (127.0.0.1)
3. **Conexão via IP vlxsam03** (172.24.1.153)

Isso garante compatibilidade entre ambientes de desenvolvimento e produção.

### Scripts de Emergência

```bash
# Scripts disponíveis em /opt/samureye/scripts/
test-postgres-connection.sh      # Teste de conectividade
reset-postgres.sh               # Reset completo PostgreSQL
health-check.sh                 # Verificação geral do sistema
daily-backup.sh                 # Backup manual

# Links simbólicos para facilitar acesso
samureye-reset-postgres         # Link para reset-postgres.sh
```

### Logs para Diagnóstico

```bash
# Logs PostgreSQL
journalctl -u postgresql -f

# Logs do script de instalação
/var/log/samureye/install.log

# Logs gerais do sistema
/var/log/samureye/
```