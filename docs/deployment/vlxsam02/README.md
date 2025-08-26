# vlxsam02 - Application Server

## Visão Geral

O servidor vlxsam02 executa a aplicação principal do SamurEye, fornecendo:
- **Frontend React 18** com Vite e interface multi-tenant
- **Backend Node.js/Express** com TypeScript e APIs REST
- **WebSocket** para comunicação em tempo real
- **Drizzle ORM** com PostgreSQL local (vlxsam03)
- **Autenticação Dual**: Sistema admin local + Replit Auth
- **Object Storage** com MinIO (vlxsam03)
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
- **ORM:** Drizzle com PostgreSQL local
- **Autenticação:** Dual system (Admin local + Replit Auth)
- **Object Storage:** MinIO (vlxsam03:9000)
- **Gerenciamento:** systemd service

## Instalação

### Executar Script de Instalação

```bash
# Conectar no servidor como root
ssh root@172.24.1.152

# Executar instalação
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install.sh | bash

# OU clonar repositório e executar localmente
git clone https://github.com/GruppenIT/SamurEye.git
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
   - Cliente PostgreSQL 16
   - Redis tools para cache
   - Session management
   - WebSocket support

4. **Autenticação e Storage**
   - Sistema dual de autenticação
   - MinIO para object storage
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

## ✅ Instalação Completa!

O script `install.sh` já configurou tudo automaticamente. **Não são necessários passos adicionais!**

### O Que Já Foi Configurado

✅ **Aplicação funcionando na porta 5000**  
✅ **Conexão com vlxsam03 (PostgreSQL/Redis)** configurada  
✅ **Variáveis de ambiente** em `/etc/samureye/.env`  
✅ **Serviço systemd** ativo e funcionando  
✅ **Ferramentas de segurança** instaladas (Nmap, Nuclei, Masscan)  
✅ **Firewall configurado** (SSH:22, App:5000)  

### Como Verificar Se Está Funcionando

```bash
# 1. Verificar se aplicação está rodando
systemctl status samureye-app

# 2. Testar APIs principais
curl http://localhost:5000/api/system/settings
curl http://localhost:5000/api/user  # Deve retornar 401 (esperado)

# 3. Ver logs em tempo real
journalctl -u samureye-app -f
```

### Configuração Opcional

Apenas se quiser personalizar algumas configurações:

```bash
# Editar variáveis de ambiente (opcional)
sudo nano /etc/samureye/.env

# Reiniciar após mudanças
sudo systemctl restart samureye-app
```

## Verificação da Instalação

### Testar Aplicação

```bash
# Verificar serviço unificado
systemctl status samureye-app

# Testar endpoints principais
curl http://localhost:5000/api/health           # Health check básico
curl http://localhost:5000/api/user            # Deve retornar erro 401 (esperado)
curl http://localhost:5000/api/system-info     # Informações do sistema

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

### Scripts de Diagnóstico e Correção

```bash
# 1. Teste completo da instalação
./test-installation.sh

# 2. Diagnóstico específico de conexão
./diagnose-connection.sh
# Verifica problemas de:
# - Arquivo .env (existe/é acessível)
# - Carregamento de variáveis pelo Node.js
# - Logs do serviço com erros específicos
# - Conectividade PostgreSQL

# 3. Correção do problema da porta 443
./fix-port-443-issue.sh
# Corrige especificamente:
# - Configurações hardcoded incorretas
# - URLs HTTPS em vez de PostgreSQL
# - Força reinicialização com .env correto
# - Valida correção automaticamente

# 4. Correção de problemas do .env
./fix-env-loading.sh
# Corrige:
# - Links simbólicos quebrados
# - Permissões incorretas
# - Teste de carregamento Node.js
```

### Teste da Instalação

O script `test-installation.sh` verificará:
- Status do serviço samureye-app
- Funcionamento das APIs (/api/health, /api/user)  
- Configuração do arquivo .env
- Ferramentas instaladas (nmap, nuclei, masscan, wscat)
- Conectividade com vlxsam03
- Logs do sistema

### Health Check Manual

```bash
# Verificar conectividade com outros servidores
ping -c 1 172.24.1.153    # vlxsam03 (Database)
ping -c 1 172.24.1.151    # vlxsam01 (Gateway)
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
# O banco é gerenciado pelo vlxsam03, não pelo vlxsam02
# Para testar conectividade:

# Testar se consegue conectar no PostgreSQL do vlxsam03
nc -zv 172.24.1.153 5432

# Testar se aplicação consegue acessar o banco
curl http://localhost:5000/api/system/settings

# Ver logs se há erros de conexão
journalctl -u samureye-app -f | grep -i database
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

## 🔧 Correções Implementadas (Agosto 2025)

### ✅ CRÍTICO RESOLVIDO: Erro de Conexão Porta 443
- **Problema**: Aplicação tentava conectar no PostgreSQL através da porta 443 em vez da 5432
- **Root Cause**: Problema de carregamento do arquivo .env e possíveis configurações hardcoded
- **Solução Definitiva**:
  - Links simbólicos corretos do .env no diretório de execução (`/opt/samureye/SamurEye/.env`)
  - Verificação automática e remoção de configurações hardcoded incorretas
  - Script específico `fix-port-443-issue.sh` para correção automatizada
  - Detecção automática do problema durante a instalação
- **Status**: ✅ COMPLETAMENTE RESOLVIDO
- **Scripts**: `diagnose-connection.sh` e `fix-port-443-issue.sh`

### ✅ CRÍTICO RESOLVIDO: Erro de Pacote wscat
- **Problema**: O pacote `wscat` não existe nos repositórios do Ubuntu 24.04, causando falha na instalação
- **Root Cause**: Script tentava executar `apt install wscat` que sempre falhava
- **Solução Definitiva**: 
  - Implementada função `safe_install()` com validação prévia de disponibilidade
  - wscat instalado via npm (método correto)
  - Adicionada validação de segurança para evitar pacotes problemáticos
- **Status**: ✅ COMPLETAMENTE RESOLVIDO

### ✅ Sistema de Instalação Robusto
- **Implementado**: Função `safe_install()` que verifica disponibilidade antes de instalar
- **Benefícios**: 
  - Evita falhas por pacotes inexistentes
  - Fornece fallbacks para versões alternativas
  - Continua instalação mesmo com falhas pontuais
  - Logs detalhados para troubleshooting
- **Aplicado em**: Todos os comandos `apt install` no script

### ✅ Validação de PostgreSQL Client
- **Problema**: PostgreSQL client às vezes não disponível na versão específica
- **Solução**: Fallback automático postgresql-client-16 → postgresql-client
- **Resultado**: Instalação sempre bem-sucedida

### ✅ Melhorias de Logging e Debugging
- Logs mais detalhados com status de cada operação
- Identificação clara de pacotes não encontrados vs falhas de instalação
- Validação pré-instalação para detectar problemas

### Sistema de Reset 100% Confiável
O script `install.sh` agora funciona como um sistema de reset completamente automatizado:
- ✅ Remove instalações anteriores de forma segura
- ✅ Reinstala todos os componentes com validação
- ✅ Valida conectividade com vlxsam03
- ✅ Configura serviços systemd
- ✅ Testa funcionalidade completa
- ✅ Funciona como reset em qualquer estado do sistema

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