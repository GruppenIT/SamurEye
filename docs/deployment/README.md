# SamurEye - Documentação de Instalação e Configuração

## Visão Geral da Infraestrutura

A plataforma SamurEye é distribuída em quatro servidores principais:

- **vlxsam01 (172.24.1.151)**: Gateway/Proxy (NGINX + Let's Encrypt)
- **vlxsam02 (172.24.1.152)**: Frontend + Backend (Node.js + React)
- **vlxsam03 (172.24.1.153)**: Banco de Dados + Redis (PostgreSQL + Redis)
- **vlxsam04 (192.168.100.151)**: Collector (Agente de coleta de dados)

## Domínios e Certificados

A plataforma utiliza os seguintes subdomínios:
- `app.samureye.com.br` - Interface web principal
- `api.samureye.com.br` - API backend
- `scanner.samureye.com.br` - Scanner externo para Attack Surface
- `ca.samureye.com.br` - Autoridade Certificadora interna (se necessário)

## Índice

1. [VLXSAM01 - Gateway](#vlxsam01---gateway)
2. [VLXSAM02 - Frontend + Backend](#vlxsam02---frontend--backend)
3. [VLXSAM03 - Banco de Dados + Redis](#vlxsam03---banco-de-dados--redis)
4. [VLXSAM04 - Collector](#vlxsam04---collector)
5. [Configuração SSL/TLS](#configuração-ssltls)
6. [Monitoramento e Logs](#monitoramento-e-logs)

---

## VLXSAM01 - Gateway

### Pré-requisitos

```bash
# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar pacotes essenciais
sudo apt install -y nginx certbot python3-certbot-nginx ufw fail2ban htop curl wget git
```

### Configuração do Firewall

```bash
# Configurar UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
```

### Configuração do NGINX

Criar arquivo de configuração principal:

```bash
sudo nano /etc/nginx/sites-available/samureye
```

### Certificados Let's Encrypt

```bash
# Obter certificados para todos os domínios
sudo certbot --nginx -d app.samureye.com.br -d api.samureye.com.br -d scanner.samureye.com.br

# Configurar renovação automática
sudo crontab -e
# Adicionar linha:
0 12 * * * /usr/bin/certbot renew --quiet
```

### Configuração do Fail2Ban

```bash
sudo nano /etc/fail2ban/jail.local
```

---

## VLXSAM02 - Frontend + Backend

### Pré-requisitos do Sistema

```bash
# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependências essenciais
sudo apt install -y curl wget git build-essential python3 python3-pip nginx supervisor
```

### Instalação do Node.js

```bash
# Instalar Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verificar instalação
node --version
npm --version
```

### Configuração do Projeto

```bash
# Criar usuário para aplicação
sudo useradd -m -s /bin/bash samureye
sudo usermod -aG sudo samureye

# Configurar diretório da aplicação
sudo mkdir -p /opt/samureye
sudo chown samureye:samureye /opt/samureye

# Trocar para usuário samureye
sudo su - samureye

# Clonar projeto (ou transferir arquivos)
cd /opt/samureye
git clone <repository-url> .

# Instalar dependências
npm ci --production
```

### Configuração do Environment

```bash
# Criar arquivo de variáveis de ambiente
sudo nano /opt/samureye/.env
```

### Configuração do Supervisor

```bash
sudo nano /etc/supervisor/conf.d/samureye.conf
```

### Build da Aplicação

```bash
# Build do frontend
cd /opt/samureye
npm run build

# Configurar NGINX para servir arquivos estáticos
sudo nano /etc/nginx/sites-available/samureye-local
```

---

## VLXSAM03 - Banco de Dados + Redis

### Pré-requisitos

```bash
# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar pacotes necessários
sudo apt install -y postgresql postgresql-contrib redis-server ufw fail2ban
```

### Configuração do PostgreSQL

```bash
# Configurar PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Criar usuário e banco de dados
sudo -u postgres psql
```

### Configuração do Redis

```bash
# Configurar Redis
sudo nano /etc/redis/redis.conf
```

### Backup e Monitoramento

```bash
# Script de backup automático
sudo nano /opt/backup-db.sh
```

---

## VLXSAM04 - Collector

### Pré-requisitos

```bash
# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependências
sudo apt install -y python3 python3-pip curl wget git nmap nuclei
```

### Instalação do Collector

```bash
# Criar usuário para collector
sudo useradd -m -s /bin/bash collector
sudo usermod -aG sudo collector

# Instalar Python packages
sudo pip3 install requests psutil schedule
```

### Configuração do Collector

```bash
# Criar diretório do collector
sudo mkdir -p /opt/collector
sudo chown collector:collector /opt/collector

# Criar script principal
sudo nano /opt/collector/collector.py
```

### Service do Systemd

```bash
sudo nano /etc/systemd/system/samureye-collector.service
```

---

## Configuração SSL/TLS

### Certificados Let's Encrypt

```bash
# Script de renovação
sudo nano /opt/renew-certificates.sh
```

### Certificados Internos (mTLS)

```bash
# Configuração step-ca (se necessário)
curl -LO https://github.com/smallstep/certificates/releases/download/v0.24.2/step-ca_linux_0.24.2_amd64.deb
sudo dpkg -i step-ca_linux_0.24.2_amd64.deb
```

---

## Monitoramento e Logs

### Configuração de Logs

```bash
# Configurar logrotate
sudo nano /etc/logrotate.d/samureye
```

### Scripts de Monitoramento

```bash
# Script de saúde do sistema
sudo nano /opt/health-check.sh
```

### Integração com FortiSIEM

```bash
# Configuração de envio de logs CEF
sudo nano /opt/send-logs-fortisiem.sh
```

---

## Scripts de Automação

### Deploy Automatizado

```bash
# Script de deploy
sudo nano /opt/deploy-samureye.sh
```

### Backup Automatizado

```bash
# Script de backup completo
sudo nano /opt/backup-complete.sh
```

### Restart de Serviços

```bash
# Script de restart coordenado
sudo nano /opt/restart-services.sh
```

---

## Troubleshooting

### Logs Importantes

```bash
# Logs da aplicação
tail -f /var/log/samureye/app.log

# Logs do NGINX
tail -f /var/log/nginx/error.log

# Logs do PostgreSQL
tail -f /var/log/postgresql/postgresql-14-main.log

# Logs do Collector
journalctl -u samureye-collector -f
```

### Comandos de Diagnóstico

```bash
# Verificar status dos serviços
systemctl status nginx postgresql redis-server samureye-collector

# Verificar conectividade
curl -I https://api.samureye.com.br/health

# Verificar banco de dados
sudo -u postgres psql -d samureye -c "SELECT version();"
```

---

## Contato e Suporte

Para dúvidas ou problemas na instalação:
- Email: suporte@samureye.com.br
- Documentação técnica: https://docs.samureye.com.br