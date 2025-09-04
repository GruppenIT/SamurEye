# vlxsam03 - Database Server

Servidor de banco de dados PostgreSQL com Redis, MinIO e Grafana para ambiente on-premise SamurEye.

## 📋 Informações do Servidor

- **IP**: 192.168.100.153
- **Função**: Database Cluster
- **OS**: Ubuntu 24.04 LTS
- **Serviços**: PostgreSQL 16, Redis, MinIO, Grafana

## 🎯 Cenários de Instalação

### ✅ Instalação Padrão
```bash
ssh root@192.168.100.153
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam03/install.sh | bash
```

### 🔥 **HARD RESET (Recomendado para ambiente corrompido)**
```bash
ssh root@192.168.100.153
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam03/install-hard-reset.sh | bash
```

**⚠️ O hard reset apaga TODOS OS DADOS do banco!**

## 🏗️ Arquitetura

```
┌─────────────────────────────────────┐
│            vlxsam02                 │
│         (192.168.100.152)          │
│        SamurEye Application         │
└─────────────┬───────────────────────┘
              │ Database Connection
              ↓
┌─────────────────────────────────────┐
│            vlxsam03                 │
│         (192.168.100.153)          │
│                                     │
│  ┌──────────┐  ┌─────────────────┐  │
│  │PostgreSQL│  │     Redis       │  │
│  │   :5432  │  │     :6379       │  │
│  └──────────┘  └─────────────────┘  │
│                                     │
│  ┌──────────┐  ┌─────────────────┐  │
│  │  MinIO   │  │    Grafana      │  │
│  │ :9000/01 │  │     :3000       │  │
│  └──────────┘  └─────────────────┘  │
└─────────────────────────────────────┘
```

## 🗃️ Serviços de Banco de Dados

### PostgreSQL 16 (Port 5432)
- **Database**: `samureye`
- **User**: `samureye` / `samureye123`
- **Configuração**: Multi-tenant, backup automático
- **Conexões**: 200 max, configurado para rede 192.168.100.0/24
- **Logs**: Português brasileiro, timezone America/Sao_Paulo

### Redis (Port 6379)
- **Função**: Cache e sessões
- **Password**: `redis123`
- **Configuração**: 512MB max memory, persistence habilitada
- **Security**: Comandos perigosos desabilitados

### MinIO Object Storage (Ports 9000/9001)
- **API**: Port 9000
- **Console**: Port 9001
- **Credentials**: `minio` / `minio123`
- **Storage**: `/opt/minio/data`

## 🗂️ Schema de Jornadas de Segurança

### Tabelas Principais

**journeys:**
- Configuração e agendamento de jornadas
- Suporte a scheduleType: on_demand, one_shot, recurring
- Configurações JSON flexíveis (scheduleConfig)

**journey_executions:**
- Histórico completo de execuções
- Status tracking: queued → running → completed/failed
- Armazenamento de resultados detalhados
- Métricas de performance (duração, timestamps)

### Auto-Criação

O schema é criado automaticamente durante o install-hard-reset.sh:
```sql
-- Executado automaticamente:
npm run db:push --force
```

### Grafana (Port 3000)
- **Dashboard**: Monitoramento e métricas
- **Database**: PostgreSQL (próprio)
- **Credentials**: `admin` / `grafana123`
- **Datasource**: PostgreSQL SamurEye

## 🔧 Configurações de Rede

### PostgreSQL pg_hba.conf
```
# SamurEye On-Premise Access
host    samureye        samureye        192.168.100.151/32      md5  # Gateway
host    samureye        samureye        192.168.100.152/32      md5  # Application
host    samureye        samureye        192.168.100.153/32      md5  # Database (local)
host    samureye        samureye        192.168.100.154/32      md5  # Collector
host    samureye        samureye        192.168.100.0/24        md5  # Rede backup
```

### UFW Firewall
- **SSH (22)**: Administração
- **PostgreSQL (5432)**: Rede interna apenas
- **Redis (6379)**: Rede interna apenas
- **MinIO (9000/9001)**: Rede interna apenas
- **Grafana (3000)**: Rede interna apenas

## 📊 Monitoramento e Logs

### Script de Teste Integrado
```bash
# Testar todos os serviços de uma vez
/usr/local/bin/test-samureye-db.sh
```

### Status Individual
```bash
# Status de todos os serviços
systemctl status postgresql redis-server minio grafana-server

# Verificar portas abertas
netstat -tlnp | grep -E ':5432|:6379|:9000|:3000'

# Processos ativos
ps aux | grep -E 'postgres|redis|minio|grafana'
```

### Logs Principais
```bash
# PostgreSQL
tail -f /var/log/postgresql/postgresql-*.log

# Redis
tail -f /var/log/redis/redis-server.log

# MinIO
journalctl -u minio -f

# Grafana
journalctl -u grafana-server -f
```

### Testes de Conectividade
```bash
# PostgreSQL
PGPASSWORD=samureye123 psql -h localhost -U samureye -d samureye -c "SELECT version();"

# Redis
redis-cli -a redis123 ping

# MinIO
curl http://localhost:9000/minio/health/live

# Grafana
curl http://localhost:3000/api/health
```

## 🔧 Comandos de Manutenção

### Controle de Serviços
```bash
# Iniciar todos
systemctl start postgresql redis-server minio grafana-server

# Parar todos
systemctl stop postgresql redis-server minio grafana-server

# Reiniciar todos
systemctl restart postgresql redis-server minio grafana-server

# Status de todos
systemctl is-active postgresql redis-server minio grafana-server
```

### PostgreSQL Específico
```bash
# Conectar como administrador
sudo -u postgres psql

# Conectar no banco SamurEye
PGPASSWORD=samureye123 psql -h localhost -U samureye -d samureye

# Backup do banco
pg_dump -h localhost -U samureye -d samureye > /tmp/samureye-backup-$(date +%Y%m%d).sql

# Restore do banco
PGPASSWORD=samureye123 psql -h localhost -U samureye -d samureye < backup.sql

# Verificar conexões ativas
PGPASSWORD=samureye123 psql -h localhost -U samureye -d samureye -c "SELECT * FROM pg_stat_activity;"
```

### Redis Específico
```bash
# Informações do servidor
redis-cli -a redis123 INFO

# Limpar cache (cuidado!)
redis-cli -a redis123 FLUSHALL

# Monitorar comandos
redis-cli -a redis123 MONITOR

# Backup Redis
redis-cli -a redis123 BGSAVE
```

### MinIO Específico
```bash
# Status via client
mc alias set local http://localhost:9000 minio minio123
mc admin info local

# Listar buckets
mc ls local

# Criar bucket para SamurEye
mc mb local/samureye-uploads
```

## 🚨 Resolução de Problemas

### Problema: PostgreSQL não aceita conexões
```bash
# Verificar se está rodando
systemctl status postgresql

# Verificar configuração
sudo -u postgres psql -c "SHOW listen_addresses;"

# Verificar arquivo pg_hba.conf
cat /etc/postgresql/16/main/pg_hba.conf | grep samureye

# Testar conectividade local
nc -zv localhost 5432

# Verificar logs
tail -50 /var/log/postgresql/postgresql-*.log
```

### Problema: Redis não conecta
```bash
# Verificar status
systemctl status redis-server

# Testar conexão local
redis-cli -a redis123 ping

# Verificar configuração
cat /etc/redis/redis.conf | grep -E 'bind|port|requireauth'

# Logs de erro
tail -50 /var/log/redis/redis-server.log
```

### Problema: MinIO não inicia
```bash
# Status do serviço
systemctl status minio

# Verificar configuração
cat /etc/minio/minio.conf

# Verificar permissões
ls -la /opt/minio/data

# Logs detalhados
journalctl -u minio -f
```

### Problema: Grafana não acessa
```bash
# Status do serviço
systemctl status grafana-server

# Verificar porta
netstat -tlnp | grep :3000

# Verificar configuração
cat /etc/grafana/grafana.ini | grep -E 'http_port|database'

# Reset senha admin
grafana-cli admin reset-admin-password grafana123
```

## 📋 Checklist Pós-Instalação

### ✅ Validação PostgreSQL
- [ ] Serviço ativo: `systemctl is-active postgresql`
- [ ] Porta aberta: `netstat -tlnp | grep :5432`
- [ ] Banco criado: `PGPASSWORD=samureye123 psql -h localhost -U samureye -l | grep samureye`
- [ ] Conexão externa: `PGPASSWORD=samureye123 psql -h 192.168.100.153 -U samureye -d samureye`

### ✅ Validação Redis
- [ ] Serviço ativo: `systemctl is-active redis-server`
- [ ] Porta aberta: `netstat -tlnp | grep :6379`
- [ ] Conexão: `redis-cli -a redis123 ping`

### ✅ Validação MinIO
- [ ] Serviço ativo: `systemctl is-active minio`
- [ ] Portas abertas: `netstat -tlnp | grep -E ':9000|:9001'`
- [ ] Health check: `curl http://localhost:9000/minio/health/live`

### ✅ Validação Grafana
- [ ] Serviço ativo: `systemctl is-active grafana-server`
- [ ] Porta aberta: `netstat -tlnp | grep :3000`
- [ ] Interface: `curl http://localhost:3000/api/health`

### ✅ Testes Integrados
- [ ] Script de teste: `/usr/local/bin/test-samureye-db.sh`
- [ ] Conectividade rede: De vlxsam02 para todas as portas

## 🔐 Credenciais de Acesso

### PostgreSQL
- **Host**: 192.168.100.153:5432
- **Database**: samureye
- **User**: samureye
- **Password**: samureye123

### Redis
- **Host**: 192.168.100.153:6379
- **Password**: redis123

### MinIO
- **API**: http://192.168.100.153:9000
- **Console**: http://192.168.100.153:9001
- **Access Key**: minio
- **Secret Key**: minio123

### Grafana
- **URL**: http://192.168.100.153:3000
- **User**: admin
- **Password**: grafana123

## 📁 Estrutura de Arquivos

```
/var/lib/postgresql/16/main/    # PostgreSQL data
/etc/postgresql/16/main/        # PostgreSQL config
├── postgresql.conf             # Configuração principal
└── pg_hba.conf                # Autenticação

/var/lib/redis/                 # Redis data
/etc/redis/                     # Redis config
└── redis.conf                 # Configuração Redis

/opt/minio/                     # MinIO installation
├── data/                       # Object storage
└── /etc/minio/minio.conf      # Configuration

/var/lib/grafana/               # Grafana data
/etc/grafana/                   # Grafana config
└── grafana.ini                # Configuração principal

/var/log/
├── postgresql/                 # PostgreSQL logs
├── redis/                      # Redis logs
└── syslog                      # System logs (MinIO, Grafana)
```

## 🔧 Scripts Personalizados

### /usr/local/bin/test-samureye-db.sh
Script completo de teste criado automaticamente pelo install-hard-reset.sh:
- Testa PostgreSQL, Redis, MinIO e Grafana
- Verifica status dos serviços
- Lista portas abertas
- Formato de saída padronizado

### Backup Automatizado
```bash
# Criar script de backup diário
cat > /usr/local/bin/backup-samureye-db.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# PostgreSQL
pg_dump -h localhost -U samureye -d samureye > "$BACKUP_DIR/samureye-db.sql"

# Redis
redis-cli -a redis123 BGSAVE
cp /var/lib/redis/dump.rdb "$BACKUP_DIR/"

# MinIO (se necessário)
# mc mirror local/samureye-uploads "$BACKUP_DIR/minio/"

echo "Backup completo em: $BACKUP_DIR"
EOF

chmod +x /usr/local/bin/backup-samureye-db.sh
```

## 🔗 Links Relacionados

- **Gateway**: [vlxsam01/README.md](../vlxsam01/README.md)
- **Aplicação**: [vlxsam02/README.md](../vlxsam02/README.md)
- **Collector**: [vlxsam04/README.md](../vlxsam04/README.md)
- **Arquitetura**: [../NETWORK-ARCHITECTURE.md](../NETWORK-ARCHITECTURE.md)