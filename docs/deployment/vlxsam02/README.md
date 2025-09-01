# vlxsam02 - Application Server

Servidor de aplicação SamurEye com Node.js, API, WebSocket e integração com banco de dados PostgreSQL.

## 📋 Informações do Servidor

- **IP**: 192.168.100.152
- **Função**: Application Server
- **OS**: Ubuntu 24.04 LTS
- **Serviços**: Node.js 20, SamurEye App, systemd

## 🎯 Cenários de Instalação

### ✅ Instalação Padrão
```bash
ssh root@192.168.100.152
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/install.sh | bash
```

### 🔥 **HARD RESET (Recomendado para ambiente corrompido)**
```bash
ssh root@192.168.100.152
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/install-hard-reset.sh | bash
```

**⚠️ O hard reset limpa completamente o banco de dados!**

## 🏗️ Arquitetura

```
┌─────────────────────────────────────┐
│            vlxsam01                 │
│         (192.168.100.151)          │
│            NGINX Proxy              │
└─────────────┬───────────────────────┘
              │ Proxy :80/:443
              ↓
┌─────────────────────────────────────┐
│            vlxsam02                 │
│         (192.168.100.152)          │
│                                     │
│  ┌─────────────────────────────────┐ │
│  │        SamurEye App             │ │
│  │        Node.js 20               │ │
│  │        Port 5000                │ │
│  │                                 │ │
│  │  ┌─────────┐  ┌─────────────┐   │ │
│  │  │   API   │  │   WebUI     │   │ │
│  │  │         │  │   React     │   │ │
│  │  └─────────┘  └─────────────┘   │ │
│  └─────────────────────────────────┘ │
│                │                     │
└────────────────┼─────────────────────┘
                 │ Database Connection
                 ↓
┌─────────────────────────────────────┐
│            vlxsam03                 │
│         (192.168.100.153)          │
│         PostgreSQL 16               │
└─────────────────────────────────────┘
```

## 🚀 Aplicação SamurEye

### Tecnologias
- **Runtime**: Node.js 20.x
- **Framework**: Express.js
- **Frontend**: React + Vite
- **Database**: PostgreSQL (vlxsam03)
- **WebSocket**: ws library
- **Authentication**: On-premise bypass

### Estrutura do Projeto
```
/opt/samureye/SamurEye/
├── package.json           # Dependências Node.js
├── server/               # Backend Express
│   ├── index.ts         # Entry point
│   ├── routes.ts        # API routes
│   └── storage.ts       # Database layer
├── client/              # Frontend React
│   ├── src/            # Source code
│   └── dist/           # Build output
├── shared/             # Shared types/schemas
│   └── schema.ts       # Database schema
├── .env                # Environment variables
└── logs/               # Application logs
```

## 🔧 Serviços Configurados

### SamurEye Application (Port 5000)
- **API REST**: Endpoints para collectors e admin
- **WebSocket**: Real-time communication
- **Admin Interface**: Gestão de tenants e collectors
- **Collector Management**: Registro e telemetria

### Environment Variables (.env)
```bash
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://samureye:samureye123@192.168.100.153:5432/samureye
SESSION_SECRET=samureye-onpremise-[random]
DISABLE_AUTH=true
ADMIN_EMAIL=admin@samureye.local
ADMIN_PASSWORD=SamurEye2024!
```

### Systemd Service (samureye-app)
- **Auto-start**: Inicia automaticamente com o sistema
- **Restart**: Reinicialização automática em caso de falha
- **Logs**: Centralizados no systemd journal
- **Security**: Rodando como usuário não-root

## 📊 Monitoramento e Logs

### Status da Aplicação
```bash
# Status do serviço
systemctl status samureye-app

# Logs em tempo real
journalctl -u samureye-app -f

# Verificar porta
netstat -tlnp | grep :5000

# Verificar processos
ps aux | grep node
```

### Teste de API
```bash
# Health check
curl http://localhost:5000/api/health

# System settings
curl http://localhost:5000/api/system/settings

# Admin tenants (se configurado)
curl http://localhost:5000/api/admin/tenants

# Collector heartbeat endpoint
curl -X POST http://localhost:5000/collector-api/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"collector_id":"test","status":"online"}'
```

### Logs da Aplicação
```bash
# Logs systemd
journalctl -u samureye-app -f

# Logs de arquivo (se configurado)
tail -f /var/log/samureye/app.log
tail -f /var/log/samureye/error.log

# Logs Node.js diretos
pm2 logs samureye  # Se usar PM2
```

## 🗃️ Integração com Banco de Dados

### Conectividade PostgreSQL
```bash
# Teste de conexão
nc -zv 192.168.100.153 5432

# Conexão direta ao banco
PGPASSWORD=samureye123 psql -h 192.168.100.153 -U samureye -d samureye

# Verificar tabelas
PGPASSWORD=samureye123 psql -h 192.168.100.153 -U samureye -d samureye -c "\dt"
```

### Migrations e Schema
```bash
# Executar migrations (Drizzle)
cd /opt/samureye/SamurEye
npm run db:push

# Verificar schema
npm run db:studio  # Se disponível
```

## 🔧 Comandos de Manutenção

### Controle do Serviço
```bash
# Iniciar
systemctl start samureye-app

# Parar
systemctl stop samureye-app

# Reiniciar
systemctl restart samureye-app

# Recarregar (graceful)
systemctl reload samureye-app

# Status
systemctl status samureye-app
```

### Atualização da Aplicação
```bash
cd /opt/samureye/SamurEye

# Backup atual
cp -r . ../backup-$(date +%Y%m%d)

# Update from GitHub
git pull origin main

# Instalar dependências
npm install --production

# Build da aplicação
npm run build

# Reiniciar serviço
systemctl restart samureye-app
```

### Backup de Configuração
```bash
# Backup completo
tar -czf /tmp/vlxsam02-backup-$(date +%Y%m%d).tar.gz \
    /opt/samureye \
    /var/log/samureye \
    /etc/systemd/system/samureye-app.service
```

## 🚨 Resolução de Problemas

### Problema: Aplicação não inicia
```bash
# Verificar logs
journalctl -u samureye-app -f

# Verificar dependências
cd /opt/samureye/SamurEye
npm list

# Verificar Node.js
node --version
npm --version

# Testar manualmente
cd /opt/samureye/SamurEye
npm run start
```

### Problema: Banco de dados não conecta
```bash
# Testar conectividade
nc -zv 192.168.100.153 5432

# Verificar .env
cat /opt/samureye/SamurEye/.env | grep DATABASE_URL

# Testar conexão manual
PGPASSWORD=samureye123 psql -h 192.168.100.153 -U samureye -d samureye -c "SELECT version();"
```

### Problema: API retorna 500
```bash
# Logs detalhados
journalctl -u samureye-app -f

# Verificar permissões
ls -la /opt/samureye/SamurEye/

# Verificar processo
ps aux | grep node

# Memory/CPU usage
top -p $(pgrep -f samureye)
```

### Problema: WebSocket não funciona
```bash
# Verificar proxy (vlxsam01)
curl -H "Connection: Upgrade" -H "Upgrade: websocket" http://192.168.100.151

# Testar direto
wscat -c ws://localhost:5000/ws  # Se wscat instalado

# Logs de conexão
grep -i websocket /var/log/samureye/app.log
```

## 📋 Checklist Pós-Instalação

### ✅ Validação Básica
- [ ] Node.js 20: `node --version`
- [ ] Aplicação ativa: `systemctl is-active samureye-app`
- [ ] Porta 5000: `netstat -tlnp | grep :5000`
- [ ] Processo rodando: `ps aux | grep node`

### ✅ Testes de API
- [ ] Health: `curl http://localhost:5000/api/health`
- [ ] Settings: `curl http://localhost:5000/api/system/settings`
- [ ] Collector endpoint: `curl -X POST http://localhost:5000/collector-api/heartbeat`

### ✅ Conectividade
- [ ] PostgreSQL: `nc -zv 192.168.100.153 5432`
- [ ] Gateway proxy: `curl -I http://192.168.100.151`

### ✅ Logs e Monitoramento
- [ ] Logs sem erros: `journalctl -u samureye-app --since "5 minutes ago"`
- [ ] Sem memory leaks: `top -p $(pgrep -f samureye)`

## 🔐 Credenciais Padrão

### Admin SamurEye
- **Email**: admin@samureye.local
- **Senha**: SamurEye2024!

### Banco de Dados
- **Host**: 192.168.100.153:5432
- **Database**: samureye
- **User**: samureye
- **Password**: samureye123

## 📁 Estrutura de Arquivos

```
/opt/samureye/
├── SamurEye/                    # Aplicação principal
│   ├── package.json
│   ├── .env                     # Configurações
│   ├── server/                  # Backend
│   ├── client/                  # Frontend
│   ├── shared/                  # Shared code
│   └── node_modules/            # Dependencies
├── logs/                        # Application logs
├── config/                      # Configuration files
└── backups/                     # Backup files

/var/log/samureye/
├── app.log                      # Application logs
├── error.log                    # Error logs
└── access.log                   # Access logs

/etc/systemd/system/
└── samureye-app.service         # Systemd service
```

## 🔗 Links Relacionados

- **Gateway**: [vlxsam01/README.md](../vlxsam01/README.md)
- **Banco de Dados**: [vlxsam03/README.md](../vlxsam03/README.md)
- **Collector**: [vlxsam04/README.md](../vlxsam04/README.md)
- **Arquitetura**: [../NETWORK-ARCHITECTURE.md](../NETWORK-ARCHITECTURE.md)