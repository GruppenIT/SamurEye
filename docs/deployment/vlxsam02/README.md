# vlxsam02 - Application Server

## Visão Geral

O servidor vlxsam02 executa a aplicação principal do SamurEye, fornecendo:
- **Frontend React 18** com Vite e interface multi-tenant
- **Backend Node.js/Express** com TypeScript e APIs REST
- **WebSocket** para comunicação em tempo real
- **Drizzle ORM** com Neon Database PostgreSQL
- **Autenticação Dual**: Sistema admin local + Replit Auth
- **Object Storage** com Google Cloud Storage
- **Sistema Multi-tenant** com isolamento de dados
- **Scanner Service** para execução de ferramentas de segurança
- **Integração Delinea** para gerenciamento de credenciais

## Especificações

- **IP:** 172.24.1.152
- **OS:** Ubuntu 22.04 LTS
- **Stack:** React 18 + Vite + TypeScript + Node.js 20.x + Express
- **Porta:** 5000 (Vite dev server - unificado)
- **Usuário:** samureye
- **Diretório:** /opt/samureye
- **ORM:** Drizzle com Neon Database
- **Autenticação:** Dual system (Admin local + Replit Auth)
- **Object Storage:** Google Cloud Storage integration
- **Gerenciamento:** systemd service

## Instalação

### Executar Script de Instalação

```bash
# Conectar no servidor como root
ssh root@172.24.1.152

# Executar instalação
curl -fsSL https://raw.githubusercontent.com/SamurEye/deploy/main/vlxsam02/install.sh | bash

# OU clonar repositório e executar localmente
git clone https://github.com/SamurEye/SamurEye.git
cd SamurEye/docs/deployment/vlxsam02/
chmod +x install.sh
./install.sh
```

### O que o Script Instala

1. **Sistema Base**
   - Node.js 20.x LTS
   - systemd service para gerenciamento
   - Usuário samureye com permissões
   - Estrutura de diretórios

2. **Stack de Desenvolvimento**
   - React 18 com TypeScript
   - Vite para build e dev server
   - shadcn/ui + Radix UI components
   - TailwindCSS para styling
   - Wouter para roteamento
   - TanStack Query para estado

3. **Backend e Banco**
   - Express.js com TypeScript
   - Drizzle ORM
   - Conexão Neon Database
   - Session management
   - WebSocket support

4. **Autenticação e Storage**
   - Sistema dual de autenticação
   - Object Storage integration
   - Session-based auth
   - Multi-tenant architecture

5. **Serviços**
   - samureye-app (aplicação unificada)
   - Configuração systemd
   - Scripts de health check
   - Monitoramento de logs

6. **Ferramentas de Segurança**
   - Nmap para descoberta de rede
   - Nuclei para teste de vulnerabilidades
   - Masscan para scanning rápido
   - Scripts auxiliares de scanning

## Configuração Pós-Instalação

### 1. Configurar Variáveis de Ambiente

```bash
# Editar arquivo de configuração
sudo nano /etc/samureye/.env

# Configurações principais que devem ser editadas:
DATABASE_URL=postgresql://samureye:password@172.24.1.153:5432/samureye
SESSION_SECRET=sua_chave_secreta_segura_aqui
DEFAULT_OBJECT_STORAGE_BUCKET_ID=bucket_id_from_object_storage
PUBLIC_OBJECT_SEARCH_PATHS=/bucket/public
PRIVATE_OBJECT_DIR=/bucket/.private
DELINEA_API_KEY=sua_api_key_aqui (opcional)
DELINEA_BASE_URL=https://gruppenztna.secretservercloud.com (opcional)

# Variáveis automáticas (geradas pelo sistema)
PGDATABASE=samureye
PGHOST=172.24.1.153
PGPORT=5432
PGUSER=samureye
PGPASSWORD=password_from_vlxsam03
```

### 2. Configurar Banco de Dados

```bash
# Navegar para diretório da aplicação
cd /opt/samureye

# Executar migrações Drizzle
sudo -u samureye npm run db:push

# Forçar migração se necessário
sudo -u samureye npm run db:push --force

# Verificar conexão
./scripts/test-database.sh

# Verificar schema multi-tenant
psql $DATABASE_URL -c "SELECT id, name, slug FROM tenants LIMIT 5;"
psql $DATABASE_URL -c "SELECT id, email, currentTenantId FROM users LIMIT 5;"
```

### 3. Configurar Object Storage

```bash
# Object Storage é configurado automaticamente
# Verificar configuração
curl http://localhost:5000/api/system/settings

# Testar upload (após autenticação)
curl -X POST http://localhost:5000/api/objects/upload

# Verificar variáveis de ambiente
grep OBJECT /etc/samureye/.env
```

### 4. Configurar Delinea Secret Server (Opcional)

```bash
# Configurar integração (se necessário)
./scripts/configure-delinea.sh

# Testar conectividade
./scripts/test-delinea.sh
```

## Verificação da Instalação

### Testar Aplicação

```bash
# Verificar serviço unificado
systemctl status samureye-app

# Testar endpoints principais
curl http://localhost:5000/api/admin/stats
curl http://localhost:5000/api/system/settings

# Testar autenticação admin
curl -X POST http://localhost:5000/api/admin/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@samureye.com.br", "password": "SamurEye2024!"}'

# Testar object storage
curl http://localhost:5000/public-objects/test

# Testar WebSocket
wscat -c ws://localhost:5000/ws

# Logs em tempo real
journalctl -u samureye-app -f
tail -f /var/log/samureye/*.log
```

### Health Check Completo

```bash
# Executar verificação completa
./scripts/health-check.sh

# Verificar conectividade com outros servidores
./scripts/test-connectivity.sh
```

## Estrutura da Aplicação

### Diretórios Principais

```
/opt/samureye/
├── SamurEye/           # Código fonte da aplicação
│   ├── client/         # Frontend React
│   ├── server/         # Backend Node.js
│   ├── shared/         # Schemas compartilhados
│   └── package.json    # Dependências
├── logs/               # Logs da aplicação
├── temp/               # Arquivos temporários
├── uploads/            # Uploads de usuários
└── scripts/            # Scripts auxiliares
```

### Serviço systemd

```bash
# Verificar status
systemctl status samureye-app

# Aplicação unificada
samureye-app    # Frontend + Backend + Scanner (porta 5000)

# Controles do serviço
sudo systemctl start samureye-app
sudo systemctl stop samureye-app
sudo systemctl restart samureye-app
sudo systemctl enable samureye-app  # Auto-start

# Logs do serviço
journalctl -u samureye-app -f
journalctl -u samureye-app --since "1 hour ago"
```

## Endpoints da Aplicação

### Frontend (SPA)
- **/** - Interface principal
- **/dashboard** - Dashboard multi-tenant
- **/collectors** - Gerenciamento de coletores
- **/journeys** - Jornadas de teste
- **/credentials** - Integração Delinea

### API Backend
- **/api/admin/stats** - Estatísticas gerais (admin)
- **/api/admin/login** - Autenticação admin local
- **/api/admin/tenants** - Gerenciamento de tenants
- **/api/admin/users** - Gerenciamento de usuários
- **/api/system/settings** - Configurações do sistema
- **/api/dashboard/** - Dados do dashboard por tenant
- **/api/collectors/** - Coletores
- **/api/journeys/** - Jornadas
- **/api/credentials/** - Credenciais
- **/api/objects/upload** - Upload para object storage
- **/public-objects/*** - Serving de assets públicos
- **/objects/*** - Acesso protegido a objetos

### WebSocket
- **/ws** - Comunicação em tempo real

### Scanner Service (Integrado)
- **/api/scan/nmap** - Execução Nmap
- **/api/scan/nuclei** - Execução Nuclei
- **/api/scan/masscan** - Execução Masscan
- **/api/scan/status** - Status de scans ativos

## Integração com Outros Servidores

### vlxsam01 (Gateway)
- Recebe requisições via proxy reverso
- Rate limiting e SSL termination

### vlxsam03 (Database)
- Neon Database (PostgreSQL) para dados da aplicação
- Redis para cache e sessões
- MinIO para armazenamento local (fallback)
- Google Cloud Storage para object storage principal

### vlxsam04 (Collector)
- Comunicação outbound-only
- Recebimento de telemetria
- Envio de comandos de execução

## Troubleshooting

### Problemas de Aplicação

```bash
# Verificar logs detalhados
journalctl -u samureye-app -f
tail -f /var/log/samureye/*.log

# Restart da aplicação
sudo systemctl restart samureye-app

# Status detalhado
sudo systemctl status samureye-app -l

# Verificar dependências
cd /opt/samureye
npm audit
npm run build

# Verificar Vite dev server
curl -I http://localhost:5000

# Verificar TypeScript compilation
npm run typecheck
```

### Problemas de Banco

```bash
# Testar conexão Neon Database
./scripts/test-database.sh

# Verificar migrações Drizzle
npm run db:push --verbose
npm run db:push --force  # se necessário

# Verificar schema multi-tenant
psql $DATABASE_URL -c "\dt"
psql $DATABASE_URL -c "SELECT * FROM tenants;"
psql $DATABASE_URL -c "SELECT * FROM users LIMIT 3;"

# Verificar sessões
psql $DATABASE_URL -c "SELECT * FROM sessions LIMIT 3;"
```

### Problemas Scanner

```bash
# Testar scanner manualmente
nmap --version
nuclei --version
masscan --version

# Verificar integração de scanner
curl http://localhost:5000/api/scan/status

# Logs do scanner (integrado)
journalctl -u samureye-app -f | grep -i scan

# Restart aplicação (scanner integrado)
sudo systemctl restart samureye-app
```

## Monitoramento

### Métricas Principais

```bash
# Health check automatizado
./scripts/health-check.sh

# Status do serviço
sudo systemctl status samureye-app

# Recursos do sistema
htop
free -h
df -h

# Monitoramento em tempo real
journalctl -u samureye-app -f

# Métricas de aplicação
curl http://localhost:5000/api/admin/stats

# Verificar multi-tenant
curl -H "Cookie: sessionid=XXX" http://localhost:5000/api/dashboard/attack-surface
```

### Logs Importantes

```bash
# Aplicação principal
tail -f /var/log/samureye/app.log

# Scanner service
tail -f /var/log/samureye/scanner.log

# PM2 logs
pm2 logs

# Sistema
journalctl -u samureye-app -f
```

## Backup e Manutenção

### Backup Diário

```bash
# Executar backup manual
./scripts/backup.sh

# Configurar backup automático (via cron)
crontab -e
# 0 2 * * * /opt/samureye/scripts/backup.sh
```

### Updates da Aplicação

```bash
# Update automático
./scripts/update-app.sh

# Update manual
cd /opt/samureye/SamurEye
git pull origin main
npm ci --production
npm run build
pm2 restart all
```

### Monitoramento de Recursos

```bash
# Usar recursos do sistema
df -h    # Espaço em disco
free -h  # Memória
top      # CPU e processos

# Logs de sistema
journalctl -u samureye-app --since="1 hour ago"
```

## Segurança

### Usuário samureye
- **Senha:** SamurEye2024! (alterar após instalação)
- **Permissões:** sudo configurado
- **Home:** /home/samureye
- **Shell:** /bin/bash

### Firewall
```bash
# Portas abertas
ufw status
# 22/tcp (SSH)
# 3000/tcp (App)
# 3001/tcp (Scanner)
```

### Variáveis Sensíveis
- DATABASE_URL com credenciais do banco
- DELINEA_API_KEY para Secret Server
- SESSION_SECRET para sessões
- Armazenadas em /etc/samureye/.env (modo 600)