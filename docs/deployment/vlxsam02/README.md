# vlxsam02 - Application Server

## Visão Geral

O servidor vlxsam02 executa a aplicação principal do SamurEye, fornecendo:
- **Frontend React** com interface multi-tenant
- **Backend Node.js/Express** com APIs REST
- **WebSocket** para comunicação em tempo real
- **Scanner Service** para execução de ferramentas de segurança
- **Integração Delinea** para gerenciamento de credenciais

## Especificações

- **IP:** 172.24.1.152
- **OS:** Ubuntu 22.04 LTS
- **Portas:** 3000 (App principal), 3001 (Scanner)
- **Usuário:** samureye
- **Diretório:** /opt/samureye

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
   - PM2 para gerenciamento de processos
   - Usuário samureye com permissões
   - Estrutura de diretórios

2. **Aplicação SamurEye**
   - Clonagem do código fonte
   - Instalação de dependências npm
   - Build do frontend
   - Configuração de variáveis de ambiente

3. **Serviços**
   - samureye-app (aplicação principal)
   - samureye-scanner (serviço de scanning)
   - Configuração systemd
   - Scripts de health check

4. **Ferramentas de Segurança**
   - Nmap para descoberta de rede
   - Nuclei para teste de vulnerabilidades
   - Scripts auxiliares de scanning

## Configuração Pós-Instalação

### 1. Configurar Variáveis de Ambiente

```bash
# Editar arquivo de configuração
sudo nano /etc/samureye/.env

# Configurações principais que devem ser editadas:
DATABASE_URL=postgresql://samureye:password@172.24.1.153:5432/samureye
DELINEA_API_KEY=sua_api_key_aqui
SESSION_SECRET=sua_chave_secreta_segura_aqui
```

### 2. Configurar Banco de Dados

```bash
# Executar migrações
sudo -u samureye npm run db:push

# Verificar conexão
./scripts/test-database.sh
```

### 3. Configurar Delinea Secret Server

```bash
# Configurar integração
./scripts/configure-delinea.sh

# Testar conectividade
./scripts/test-delinea.sh
```

## Verificação da Instalação

### Testar Aplicação

```bash
# Verificar serviços
systemctl status samureye-app
systemctl status samureye-scanner

# Testar endpoints
curl http://localhost:3000/api/health
curl http://localhost:3001/health

# Logs em tempo real
tail -f /var/log/samureye/app.log
tail -f /var/log/samureye/scanner.log
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

### Processos PM2

```bash
# Verificar status
pm2 status

# Aplicação principal
samureye-app    # Frontend + Backend (porta 3000)

# Serviço de scanning
samureye-scanner # Scanner Service (porta 3001)
```

## Endpoints da Aplicação

### Frontend (SPA)
- **/** - Interface principal
- **/dashboard** - Dashboard multi-tenant
- **/collectors** - Gerenciamento de coletores
- **/journeys** - Jornadas de teste
- **/credentials** - Integração Delinea

### API Backend
- **/api/health** - Health check
- **/api/auth/** - Autenticação
- **/api/tenants/** - Multi-tenancy
- **/api/collectors/** - Coletores
- **/api/journeys/** - Jornadas
- **/api/credentials/** - Credenciais

### WebSocket
- **/ws** - Comunicação em tempo real

### Scanner Service
- **/health** - Health check scanner
- **/scan/nmap** - Execução Nmap
- **/scan/nuclei** - Execução Nuclei

## Integração com Outros Servidores

### vlxsam01 (Gateway)
- Recebe requisições via proxy reverso
- Rate limiting e SSL termination

### vlxsam03 (Database)
- PostgreSQL para dados da aplicação
- Redis para cache e sessões
- MinIO para armazenamento de arquivos

### vlxsam04 (Collector)
- Comunicação outbound-only
- Recebimento de telemetria
- Envio de comandos de execução

## Troubleshooting

### Problemas de Aplicação

```bash
# Verificar logs detalhados
tail -f /var/log/samureye/app.log
tail -f /var/log/samureye/scanner.log

# Restart da aplicação
sudo systemctl restart samureye-app

# Verificar dependências
cd /opt/samureye/SamurEye
npm audit
```

### Problemas de Banco

```bash
# Testar conexão
./scripts/test-database.sh

# Verificar migrações
npm run db:push --verbose
```

### Problemas Scanner

```bash
# Testar scanner manualmente
nmap --version
nuclei --version

# Verificar logs do scanner
tail -f /var/log/samureye/scanner.log

# Restart scanner
pm2 restart samureye-scanner
```

## Monitoramento

### Métricas Principais

```bash
# Health check automatizado
./scripts/health-check.sh

# Status dos processos
pm2 monit

# Recursos do sistema
htop
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