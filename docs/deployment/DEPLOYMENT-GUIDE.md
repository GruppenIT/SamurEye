# SamurEye - Guia Completo de Implantação

## 🚀 Visão Geral

Este guia fornece instruções completas para implantar a plataforma SamurEye em ambiente de produção, incluindo todos os scripts de automação, configurações e procedimentos necessários.

## 🏗️ Arquitetura da Infraestrutura

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    vlxsam01     │    │    vlxsam02     │    │    vlxsam03     │    │    vlxsam04     │
│     Gateway     │────│  Frontend +     │────│   Database +    │    │   Collector     │
│                 │    │    Backend      │    │     Redis       │    │                 │
│                 │    │                 │    │                 │    │                 │
│ • NGINX         │    │ • Node.js       │    │ • PostgreSQL    │    │ • Python        │
│ • Let's Encrypt │    │ • React         │    │ • Redis         │    │ • Nmap          │
│ • SSL/TLS       │    │ • PM2           │    │ • MinIO         │    │ • Nuclei        │
│ • Rate Limiting │    │ • Scanner       │    │ • Backup        │    │ • Telemetry     │
│ • Fail2Ban      │    │ • WebSocket     │    │ • Monitoring    │    │ • Real-time     │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📋 Pré-requisitos

### DNS e Domínios
- `app.samureye.com.br` → vlxsam01 (Interface web)
- `api.samureye.com.br` → vlxsam01 (API backend)
- `scanner.samureye.com.br` → vlxsam01 (Scanner externo)
- `ca.samureye.com.br` → vlxsam01 (CA interna - opcional)

### Servidores
- **vlxsam01**: 2 vCPU, 4GB RAM, 50GB SSD (Gateway)
- **vlxsam02**: 4 vCPU, 8GB RAM, 100GB SSD (Aplicação)
- **vlxsam03**: 4 vCPU, 8GB RAM, 200GB SSD (Banco de dados)
- **vlxsam04**: 2 vCPU, 4GB RAM, 50GB SSD (Collector)

### Rede
- Conectividade entre todos os servidores
- Acesso à internet para updates e certificados
- Portas:
  - 80/443 (HTTP/HTTPS) - vlxsam01
  - 3000/3001 (App/Scanner) - vlxsam02
  - 5432/6379/9000 (PostgreSQL/Redis/MinIO) - vlxsam03
  - SSH para administração - todos

## 🔧 Processo de Instalação

### 1. VLXSAM01 - Gateway (NGINX + SSL)

```bash
# Conectar ao servidor
ssh root@vlxsam01

# Baixar e executar script de instalação
wget https://github.com/samureye/deployment/raw/main/vlxsam01-gateway/install.sh
chmod +x install.sh
sudo bash install.sh

# Configurar NGINX
wget https://github.com/samureye/deployment/raw/main/vlxsam01-gateway/nginx-samureye.conf
sudo cp nginx-samureye.conf /etc/nginx/sites-available/samureye
sudo ln -sf /etc/nginx/sites-available/samureye /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/temp-cert

# Obter certificados SSL
sudo certbot --nginx -d app.samureye.com.br -d api.samureye.com.br -d scanner.samureye.com.br

# Testar configuração
sudo nginx -t && sudo systemctl reload nginx
```

### 2. VLXSAM03 - Database + Redis

```bash
# Conectar ao servidor
ssh root@vlxsam03

# Baixar e executar script de instalação
wget https://github.com/samureye/deployment/raw/main/vlxsam03-database/install.sh
chmod +x install.sh
sudo bash install.sh

# Verificar serviços
systemctl status postgresql redis-server minio
sudo -u postgres psql -l
redis-cli ping

# Salvar credenciais (arquivo criado automaticamente em /root/samureye-credentials.txt)
cat /root/samureye-credentials.txt
```

### 3. VLXSAM02 - Frontend + Backend

```bash
# Conectar ao servidor
ssh root@vlxsam02

# Baixar e executar script de instalação
wget https://github.com/samureye/deployment/raw/main/vlxsam02-app/install.sh
chmod +x install.sh
sudo bash install.sh

# Configurar variáveis de ambiente
sudo cp /etc/samureye/.env.template /etc/samureye/.env
sudo nano /etc/samureye/.env
# Preencher com dados do banco de dados de vlxsam03

# Deploy da aplicação
cd /opt/samureye
# Copiar código da aplicação para este diretório
# git clone <repository> . (se usando Git)

# Instalar dependências e fazer build
npm ci --production
npm run build
npm run db:push

# Configurar PM2
sudo -u samureye pm2 start ecosystem.config.js
sudo -u samureye pm2 save

# Verificar status
pm2 status
curl http://localhost:3000/api/health
curl http://localhost:3001/health
```

### 4. VLXSAM04 - Collector

```bash
# Conectar ao servidor
ssh root@vlxsam04

# Baixar e executar script de instalação
wget https://github.com/samureye/deployment/raw/main/vlxsam04-collector/install.sh
chmod +x install.sh
sudo bash install.sh

# Configurar collector
sudo cp /etc/collector/config.json.template /etc/collector/config.json
sudo nano /etc/collector/config.json
# Adicionar enrollment_token obtido da plataforma web

# Iniciar collector
sudo systemctl start samureye-collector
sudo systemctl status samureye-collector

# Verificar logs
journalctl -u samureye-collector -f
```

## 🔒 Configuração de Certificados SSL

### Opção 1: Let's Encrypt (Produção)

```bash
# No servidor vlxsam01
wget https://github.com/samureye/deployment/raw/main/ssl-certificates/setup-certificates.sh
chmod +x setup-certificates.sh
sudo bash setup-certificates.sh
# Escolher opção 1 (Let's Encrypt)
```

### Opção 2: Certificados Auto-assinados (Desenvolvimento)

```bash
# No servidor vlxsam01
sudo bash setup-certificates.sh
# Escolher opção 2 (Auto-assinados)
```

## 📊 Configuração de Monitoramento

### Em todos os servidores

```bash
# Baixar script de monitoramento
wget https://github.com/samureye/deployment/raw/main/monitoring/setup-monitoring.sh
chmod +x setup-monitoring.sh
sudo bash setup-monitoring.sh
# O script detectará automaticamente o tipo de servidor
```

### Configurar FortiSIEM (Opcional)

```bash
# No servidor vlxsam03 (receptor de logs)
# Editar /etc/rsyslog.conf e adicionar FortiSIEM endpoint
echo "*.* @@fortisiem-server.company.com:514" >> /etc/rsyslog.conf
systemctl restart rsyslog
```

## 🔧 Configurações Adicionais

### Integração com Delinea Secret Server

1. Obter API key do Delinea Secret Server
2. Configurar no arquivo `/etc/samureye/.env` em vlxsam02:
   ```
   DELINEA_API_KEY=your_api_key_here
   DELINEA_BASE_URL=https://gruppenztna.secretservercloud.com
   ```

### Configuração de Backup Automático

```bash
# Em vlxsam03 (Database)
sudo crontab -e
# Adicionar: 0 2 * * * /opt/backup-database.sh

# Em vlxsam02 (Application)
sudo crontab -e
# Adicionar: 0 3 * * * /opt/backup-app.sh
```

## 🧪 Testes de Verificação

### 1. Conectividade Básica

```bash
# Testar URLs principais
curl -I https://app.samureye.com.br
curl -I https://api.samureye.com.br/health
curl -I https://scanner.samureye.com.br/health

# Testar conectividade entre servidores
# De vlxsam02 para vlxsam03
nc -zv vlxsam03 5432  # PostgreSQL
nc -zv vlxsam03 6379  # Redis

# De vlxsam04 para vlxsam02
nc -zv vlxsam02 3000  # API
```

### 2. Funcionalidade da Aplicação

```bash
# Login na plataforma
curl -X POST https://api.samureye.com.br/api/login

# Verificar WebSocket
wscat -c wss://app.samureye.com.br/ws

# Testar scanner externo
curl -X POST https://scanner.samureye.com.br/api/scan/attack-surface \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{"targets": ["127.0.0.1"], "journeyId": "test"}'
```

### 3. Verificação de Serviços

```bash
# Em cada servidor, executar:
/opt/health-check.sh        # vlxsam02
/opt/monitor-nginx.sh       # vlxsam01
/opt/monitor-database.sh    # vlxsam03
/opt/collector-status.sh    # vlxsam04
```

## 🔍 Troubleshooting

### Problemas Comuns

#### 1. Erro "No active tenant selected"
```bash
# Verificar logs da aplicação
journalctl -u samureye -f

# Verificar banco de dados
sudo -u postgres psql -d samureye -c "SELECT * FROM users LIMIT 1;"
sudo -u postgres psql -d samureye -c "SELECT * FROM tenants LIMIT 1;"
```

#### 2. Certificados SSL inválidos
```bash
# Verificar certificados
/opt/check-certificates.sh

# Renovar certificados
certbot renew --dry-run
```

#### 3. Collector não conecta
```bash
# Verificar conectividade
curl -I https://api.samureye.com.br

# Verificar logs
journalctl -u samureye-collector -f

# Verificar configuração
cat /etc/collector/config.json
```

#### 4. Alta utilização de recursos
```bash
# Verificar processos
htop
iotop
nethogs

# Verificar logs de aplicação
tail -f /var/log/samureye/app.log
```

## 📝 Logs Importantes

### Localização dos Logs

- **vlxsam01**: `/var/log/nginx/`, `/var/log/samureye/`
- **vlxsam02**: `/var/log/samureye/`, PM2 logs
- **vlxsam03**: `/var/log/postgresql/`, `/var/log/redis/`, `/var/log/samureye/`
- **vlxsam04**: `/var/log/collector/`, journalctl

### Comandos Úteis

```bash
# Logs em tempo real
tail -f /var/log/samureye/*.log

# Logs de sistema
journalctl -u samureye -f
journalctl -u nginx -f
journalctl -u postgresql -f

# Análise de logs
grep ERROR /var/log/samureye/app.log
grep "HTTP/1.1\" 5" /var/log/nginx/access.log
```

## 🔄 Manutenção

### Atualizações Regulares

```bash
# Atualizar sistema (todos os servidores)
sudo apt update && sudo apt upgrade

# Atualizar aplicação (vlxsam02)
/opt/deploy-samureye.sh

# Atualizar templates Nuclei (vlxsam04)
nuclei -update-templates
```

### Backup e Restore

```bash
# Backup manual
/opt/backup-database.sh    # vlxsam03
/opt/backup-app.sh         # vlxsam02

# Restore de banco de dados
gunzip -c backup.sql.gz | sudo -u postgres psql samureye
```

## 📞 Suporte

### Contatos
- **Suporte Técnico**: suporte@samureye.com.br
- **Documentação**: https://docs.samureye.com.br
- **Status da Plataforma**: https://status.samureye.com.br

### Informações de Suporte
- Logs relevantes
- Versão da aplicação
- Configuração do ambiente
- Passos para reproduzir o problema

---

**⚠️ Importante**: Mantenha sempre backups atualizados e teste o processo de restore regularmente. Este guia deve ser revisado e atualizado conforme a evolução da plataforma.

**✅ Sucesso**: Após seguir este guia, você terá uma instalação completa e funcional da plataforma SamurEye pronta para uso em produção.