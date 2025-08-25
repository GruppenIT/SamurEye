# SamurEye - Guia Completo de Implantação

## 🚀 Visão Geral

Este guia fornece instruções completas para implantar a plataforma SamurEye em ambiente de produção, incluindo todos os scripts de automação, configurações e procedimentos necessários.

A SamurEye é uma plataforma abrangente de Breach & Attack Simulation (BAS) com arquitetura multi-tenant, oferecendo validação de superfície de ataque, inteligência de ameaças e capacidades de teste de segurança através de frontend baseado em nuvem e coletores de edge.

## 🏗️ Arquitetura da Infraestrutura

```
┌────────────────────┐    ┌────────────────────┐    ┌────────────────────┐    ┌────────────────────┐
│     vlxsam01       │    │     vlxsam02       │    │     vlxsam03       │    │     vlxsam04       │
│   (172.24.1.151)   │    │   (172.24.1.152)   │    │   (172.24.1.153)   │    │  (192.168.100.151) │
│      Gateway       │────│   Application +    │────│   Database +       │    │     Collector      │
│                    │    │     Scanner        │    │    Storage         │    │   (outbound only)   │
│                    │    │                    │    │                    │    │                    │
│ • NGINX            │    │ • React 18         │    │ • PostgreSQL 15    │    │ • Python 3.10+    │
│ • Let's Encrypt    │    │ • Node.js 20.x     │    │ • Redis            │    │ • Nmap             │
│ • SSL/TLS          │    │ • Express          │    │ • MinIO (S3)       │    │ • Nuclei           │
│ • Rate Limiting    │    │ • TypeScript       │    │ • Object Storage   │    │ • Masscan          │
│ • Fail2Ban         │    │ • WebSocket        │    │ • Grafana          │    │ • Telemetria       │
│ • Proxy Reverso   │    │ • Multi-tenant     │    │ • Backup Auto      │    │ • Jornadas         │
└────────────────────┘    └────────────────────┘    └────────────────────┘    └────────────────────┘
```

### Stack Tecnológico

**Frontend:**
- React 18 com TypeScript
- Vite como build tool
- shadcn/ui + Radix UI para componentes
- TailwindCSS para styling
- Wouter para roteamento
- TanStack Query para gerenciamento de estado

**Backend:**
- Node.js 20.x LTS
- Express.js com TypeScript
- Drizzle ORM + Neon Database
- WebSocket para comunicação real-time
- Autenticação dual (Admin local + Replit Auth)
- Object Storage (Google Cloud Storage)

**Banco de Dados:**
- PostgreSQL 16 (local no vlxsam03)
- Redis para cache e sessões
- MinIO para object storage
- Arquitetura multi-tenant completa

**Segurança:**
- mTLS para comunicação collector-cloud
- step-ca como CA interna
- Let's Encrypt para certificados públicos
- Session-based authentication

## 📋 Pré-requisitos

### DNS e Domínios
- `app.samureye.com.br` → 172.24.1.151 (vlxsam01 - Interface web)
- `api.samureye.com.br` → 172.24.1.151 (vlxsam01 - API backend)
- `scanner.samureye.com.br` → 172.24.1.151 (vlxsam01 - Scanner externo)
- `ca.samureye.com.br` → 172.24.1.151 (vlxsam01 - CA interna - opcional)

### Funcionalidades Principais
- **Dashboard Multi-tenant**: Métricas isoladas por organização
- **Sistema de Autenticação Dual**: Admin global + usuários por tenant
- **Object Storage**: Upload de logos e documentos
- **WebSocket**: Comunicação real-time para status de collectors
- **Sistema SOC**: Usuários com acesso a múltiplos tenants
- **Gestão de Credenciais**: Integração com Delinea Secret Server
- **Threat Intelligence**: Correlação de CVEs e indicadores
- **Telemetria**: Coleta de métricas de collectors em tempo real

### Servidores
- **vlxsam01 (172.24.1.151)**: 2 vCPU, 4GB RAM, 50GB SSD (Gateway)
- **vlxsam02 (172.24.1.152)**: 4 vCPU, 8GB RAM, 100GB SSD (Aplicação)
- **vlxsam03 (172.24.1.153)**: 4 vCPU, 8GB RAM, 200GB SSD (Banco de dados)
- **vlxsam04 (192.168.100.151)**: 2 vCPU, 4GB RAM, 50GB SSD (Collector)

### Rede
- Conectividade entre todos os servidores
- Acesso à internet para updates e certificados
- vlxsam04 (collector) conecta apenas outbound para vlxsam02 via HTTPS
- Portas:
  - 80/443 (HTTP/HTTPS) - vlxsam01 (172.24.1.151)
  - 5000 (App Vite dev server) - vlxsam02 (172.24.1.152)
  - 5432/6379/9000 (PostgreSQL/Redis/MinIO) - vlxsam03 (172.24.1.153)
  - SSH para administração - todos
  - vlxsam04 (192.168.100.151) - apenas outbound HTTPS

### Variáveis de Ambiente Principais
- `DATABASE_URL`: Conexão PostgreSQL local (172.24.1.153:5432)
- `SESSION_SECRET`: Chave para sessões
- `DEFAULT_OBJECT_STORAGE_BUCKET_ID`: Bucket para object storage
- `PUBLIC_OBJECT_SEARCH_PATHS`: Caminhos para assets públicos
- `PRIVATE_OBJECT_DIR`: Diretório para uploads privados
- `DELINEA_API_KEY`: Integração com Secret Server

## 🔧 Processo de Instalação

**⚠️ IMPORTANTE**: Execute os servidores na seguinte ordem para resolver dependências:
1. vlxsam03 (Database) - PRIMEIRO
2. vlxsam01 (Gateway)
3. vlxsam02 (Application) 
4. vlxsam04 (Collector) - ÚLTIMO

### 1. VLXSAM03 - Database + Storage (PRIMEIRO)

```bash
# Conectar ao servidor
ssh root@172.24.1.153

# Executar script de instalação
cd /opt
git clone https://github.com/GruppenIT/SamurEye.git
cd SamurEye/docs/deployment/vlxsam03/
chmod +x install.sh
sudo ./install.sh

# Verificar serviços instalados
systemctl status postgresql redis-server grafana-server

# Testar conectividade PostgreSQL
PGPASSWORD='SamurEye2024DB!' psql -h 127.0.0.1 -U samureye -d samureye_db -c "SELECT version();"
redis-cli ping

# Testar MinIO (se instalado)
curl http://localhost:9000/minio/health/live

# SALVAR credenciais mostradas pelo script
# As credenciais são salvas em /root/samureye-credentials.txt
cat /root/samureye-credentials.txt
```

### 2. VLXSAM01 - Gateway (NGINX + SSL)

```bash
# Conectar ao servidor
ssh root@172.24.1.151

# Executar script de instalação
cd /opt
git clone https://github.com/GruppenIT/SamurEye.git
cd SamurEye/docs/deployment/vlxsam01/
chmod +x install.sh
sudo ./install.sh

# Configurar certificados SSL
cd ../ssl-certificates/
sudo ./setup-certificates.sh
# Escolher opção de certificados (Let's Encrypt ou auto-assinados)

# Testar configuração
sudo nginx -t && sudo systemctl reload nginx
curl -I https://app.samureye.com.br
```

### 3. VLXSAM02 - Application Server

```bash
# Conectar ao servidor
ssh root@172.24.1.152

# Executar script de instalação
cd /opt
git clone https://github.com/GruppenIT/SamurEye.git
cd SamurEye/docs/deployment/vlxsam02/
chmod +x install.sh
sudo ./install.sh

# Configurar variáveis de ambiente
sudo nano /etc/samureye/.env
# Configurar variáveis principais:
# DATABASE_URL=postgresql://samureye:SamurEye2024DB!@172.24.1.153:5432/samureye_db
# SESSION_SECRET=sua_chave_secreta_segura_aqui
# DELINEA_API_KEY=sua_api_key_aqui (opcional)

# Deploy da aplicação SamurEye
cd /opt/samureye
git clone https://github.com/GruppenIT/SamurEye.git .

# Instalar dependências
npm ci

# Configurar banco de dados
npm run db:push

# Build da aplicação
npm run build

# Configurar e iniciar serviços
sudo systemctl start samureye-app
sudo systemctl enable samureye-app

# Verificar status
sudo systemctl status samureye-app
curl http://localhost:5000/api/admin/stats
```

### 4. VLXSAM04 - Collector (ÚLTIMO)

```bash
# Conectar ao servidor
ssh root@192.168.100.151

# Executar script de instalação
cd /opt
git clone https://github.com/GruppenIT/SamurEye.git
cd SamurEye/docs/deployment/vlxsam04/
chmod +x install.sh
sudo ./install.sh

# Configurar collector
sudo nano /etc/samureye-collector/.env
# Configurar:
# SAMUREYE_API_URL=https://api.samureye.com.br
# COLLECTOR_NAME=Collector-Principal
# TENANT_ID=seu_tenant_id

# IMPORTANTE: Obter enrollment token da interface web
# 1. Acesse https://app.samureye.com.br
# 2. Vá em Collectors > Adicionar Collector
# 3. Copie o token de enrollment

# Configurar token de enrollment
sudo nano /etc/samureye-collector/enrollment.json
# {"enrollmentToken": "token_obtido_da_interface_web"}

# Iniciar collector
sudo systemctl start samureye-collector
sudo systemctl enable samureye-collector
sudo systemctl status samureye-collector

# Verificar logs
journalctl -u samureye-collector -f

# Testar conectividade
curl -I https://api.samureye.com.br
```

## 🔒 Configuração de Certificados SSL

### Configuração Automática (Recomendada)

```bash
# No servidor vlxsam01
cd /opt/SamurEye/docs/deployment/ssl-certificates/
sudo ./setup-certificates.sh

# Opções disponíveis:
# 1. Let's Encrypt DNS Challenge (Produção)
# 2. Let's Encrypt HTTP Challenge (Produção simples)
# 3. Certificados Auto-assinados (Desenvolvimento)
# 4. DNS Manual Assistido (Para rate limits)
```

### DNS Challenge (Recomendado para Produção)

```bash
# Configurar credenciais do provedor DNS
sudo nano /etc/letsencrypt/dns-credentials.ini

# Para Cloudflare:
# dns_cloudflare_api_token = seu_token_aqui

# Para Route53:
# dns_route53_access_key_id = seu_access_key
# dns_route53_secret_access_key = sua_secret_key

# Executar configuração
sudo ./setup-certificates.sh
# Escolher opção 1 (DNS Challenge)
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

### Configuração do Admin Global

```bash
# O sistema já vem com usuário admin pré-configurado:
# Email: admin@samureye.com.br
# Senha: SamurEye2024!

# Acesse: https://app.samureye.com.br/admin
# IMPORTANTE: Altere a senha padrão após primeiro login
```

### Configuração de Object Storage

```bash
# Object Storage já configurado automaticamente
# Variáveis de ambiente geradas:
# DEFAULT_OBJECT_STORAGE_BUCKET_ID=bucket_id
# PUBLIC_OBJECT_SEARCH_PATHS=/bucket/public
# PRIVATE_OBJECT_DIR=/bucket/.private

# Verificar configuração:
curl https://api.samureye.com.br/api/admin/settings
```

### Integração com Delinea Secret Server (Opcional)

```bash
# Configurar no arquivo /etc/samureye/.env em vlxsam02:
DELINEA_API_KEY=your_api_key_here
DELINEA_BASE_URL=https://gruppenztna.secretservercloud.com

# Reiniciar aplicação
sudo systemctl restart samureye-app
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

### Script de Verificação Completa

```bash
# Executar verificação automática
cd /opt/SamurEye/docs/deployment/scripts/
sudo ./verify-full-installation.sh

# Este script verifica:
# - Conectividade entre servidores
# - Status de todos os serviços
# - Funcionalidade das APIs
# - Certificados SSL
# - Banco de dados
# - Object storage
```

### 1. Conectividade Básica

```bash
# Testar URLs principais
curl -I https://app.samureye.com.br
curl -I https://api.samureye.com.br/api/admin/stats

# Testar conectividade entre servidores
# De vlxsam02 para vlxsam03
nc -zv 172.24.1.153 5432  # PostgreSQL
nc -zv 172.24.1.153 6379  # Redis
nc -zv 172.24.1.153 9000  # MinIO

# De vlxsam04 para vlxsam02 (outbound only)
nc -zv 172.24.1.152 5000  # App
```

### 2. Funcionalidade da Aplicação

```bash
# Testar login admin
curl -X POST https://api.samureye.com.br/api/admin/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@samureye.com.br", "password": "SamurEye2024!"}'

# Verificar WebSocket
wscat -c wss://app.samureye.com.br/ws

# Testar APIs principais
curl https://api.samureye.com.br/api/admin/stats
curl https://api.samureye.com.br/api/admin/tenants
curl https://api.samureye.com.br/api/admin/users

# Testar object storage
curl https://api.samureye.com.br/api/system/settings
```

### 3. Verificação de Serviços

```bash
# vlxsam01 (Gateway)
sudo systemctl status nginx
sudo nginx -t
curl -I https://app.samureye.com.br

# vlxsam02 (Application)
sudo systemctl status samureye-app
curl http://localhost:5000/api/admin/stats

# vlxsam03 (Database)
sudo systemctl status postgresql redis-server minio
sudo -u postgres psql -c "SELECT count(*) FROM users;"
redis-cli ping

# vlxsam04 (Collector)
sudo systemctl status samureye-collector
journalctl -u samureye-collector --no-pager -l
```

## 🔍 Troubleshooting

### Problemas Comuns

#### 1. Erro "No active tenant selected"
```bash
# Verificar logs da aplicação
journalctl -u samureye-app -f

# Verificar banco de dados
# Conectar usando DATABASE_URL do arquivo .env
export DATABASE_URL=$(grep DATABASE_URL /etc/samureye/.env | cut -d'=' -f2)
psql $DATABASE_URL -c "SELECT id, email, currentTenantId FROM users LIMIT 5;"
psql $DATABASE_URL -c "SELECT id, name, slug FROM tenants LIMIT 5;"

# Corrigir tenant para usuário
psql $DATABASE_URL -c "UPDATE users SET currentTenantId = (SELECT id FROM tenants LIMIT 1) WHERE currentTenantId IS NULL;"
```

#### 2. Certificados SSL inválidos
```bash
# Verificar certificados
cd /opt/SamurEye/docs/deployment/ssl-certificates/
sudo ./check-ssl-status.sh

# Diagnosticar problemas NGINX
sudo ./diagnose-nginx.sh

# Renovar certificados
sudo certbot renew --dry-run

# Para rate limit issues
sudo ./setup-certificates.sh
# Escolha opção 4 (DNS Manual Assistido)
```

#### 3. Collector não conecta
```bash
# Verificar conectividade
curl -I https://api.samureye.com.br

# Verificar logs
journalctl -u samureye-collector -f

# Verificar configuração
cat /etc/samureye-collector/.env
cat /etc/samureye-collector/enrollment.json

# Testar registro manual
curl -X POST https://api.samureye.com.br/api/collectors \
  -H "Content-Type: application/json" \
  -d '{"name": "Test-Collector", "hostname": "vlxsam04"}'

# Verificar se collector aparece na interface web
# https://app.samureye.com.br/collectors
```

#### 4. Alta utilização de recursos
```bash
# Verificar processos
htop
iotop
nethogs

# Verificar logs de aplicação
journalctl -u samureye-app -f
tail -f /var/log/samureye/*.log

# Verificar métricas do sistema
df -h  # Espaço em disco
free -h  # Memória
uptime  # Load average
```

#### 5. Problemas de Autenticação
```bash
# Verificar sessões
redis-cli
> KEYS "sess:*"
> TTL "sess:session_id_aqui"

# Limpar sessões
redis-cli FLUSHDB

# Testar login admin
curl -X POST https://api.samureye.com.br/api/admin/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@samureye.com.br", "password": "SamurEye2024!"}'
```

#### 6. Object Storage não funciona
```bash
# Verificar environment variables
grep OBJECT /etc/samureye/.env

# Testar object storage
curl https://api.samureye.com.br/api/admin/settings

# Verificar logs de upload
journalctl -u samureye-app | grep -i "object\|storage\|upload"
```

## 📝 Logs Importantes

### Localização dos Logs

- **vlxsam01**: `/var/log/nginx/`, `/var/log/letsencrypt/`
- **vlxsam02**: `journalctl -u samureye-app`, `/var/log/samureye/`
- **vlxsam03**: `/var/log/postgresql/`, `/var/log/redis/`, `/var/log/minio/`
- **vlxsam04**: `journalctl -u samureye-collector`, `/var/log/samureye-collector/`

### Comandos Úteis

```bash
# Logs em tempo real
journalctl -u samureye-app -f
journalctl -u samureye-collector -f
tail -f /var/log/nginx/*.log

# Logs de sistema
journalctl -u nginx -f
journalctl -u postgresql -f
journalctl -u redis-server -f
journalctl -u minio -f

# Análise de logs
journalctl -u samureye-app | grep -i error
grep "HTTP/1.1\" 5" /var/log/nginx/access.log
grep -i "admin\|login\|auth" /var/log/nginx/access.log

# Logs específicos por funcionalidade
journalctl -u samureye-app | grep -i "tenant\|multi-tenant"
journalctl -u samureye-app | grep -i "object\|storage\|upload"
journalctl -u samureye-collector | grep -i "connect\|enroll\|register"
```

## 🔄 Manutenção

### Atualizações Regulares

```bash
# Atualizar sistema (todos os servidores)
sudo apt update && sudo apt upgrade

# Atualizar aplicação (vlxsam02)
cd /opt/samureye
git pull origin main
npm ci
npm run build
npm run db:push
sudo systemctl restart samureye-app

# Atualizar templates Nuclei (vlxsam04)
nuclei -update-templates

# Verificar certificados SSL (vlxsam01)
certbot certificates
sudo certbot renew --dry-run
```

### Backup e Restore

```bash
# Backup manual do banco de dados (vlxsam03)
DATABASE_URL=$(grep DATABASE_URL /etc/samureye/.env | cut -d'=' -f2)
pg_dump $DATABASE_URL > samureye_backup_$(date +%Y%m%d_%H%M%S).sql

# Backup de configurações (vlxsam02)
tar -czf samureye_config_$(date +%Y%m%d_%H%M%S).tar.gz \
  /etc/samureye/ \
  /opt/samureye/.env \
  /etc/systemd/system/samureye-app.service

# Backup do object storage
# (Automático via Google Cloud Storage)

# Restore de banco de dados
psql $DATABASE_URL < samureye_backup_YYYYMMDD_HHMMSS.sql

# Scripts automáticos de backup
# Configurar cron jobs:
# 0 2 * * * /opt/scripts/backup-database.sh
# 0 3 * * * /opt/scripts/backup-configs.sh
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