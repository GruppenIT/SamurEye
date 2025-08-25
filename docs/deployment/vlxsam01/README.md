# vlxsam01 - Gateway Server

## Visão Geral

O servidor vlxsam01 atua como gateway da plataforma SamurEye, fornecendo:
- **Proxy reverso NGINX** para roteamento de requisições
- **Terminação SSL/TLS** com certificados wildcard
- **Rate limiting** e proteção contra ataques
- **Load balancing** para alta disponibilidade
- **Redirecionamento HTTPS** obrigatório
- **Roteamento inteligente** para sistema multi-tenant
- **Support para WebSocket** em tempo real

## Especificações

- **IP:** 172.24.1.151
- **OS:** Ubuntu 22.04 LTS
- **Domínio:** *.samureye.com.br
- **Portas:** 80 (HTTP→HTTPS), 443 (HTTPS)
- **Backend Target:** vlxsam02:5000 (Vite dev server)
- **SSL:** Let's Encrypt wildcard certificates
- **Features:** Multi-tenant routing, WebSocket support

## Instalação

### Executar Script de Instalação

```bash
# Conectar no servidor como root
ssh root@172.24.1.151

# Baixar e executar instalação
curl -fsSL https://raw.githubusercontent.com/SamurEye/deploy/main/vlxsam01/install.sh | bash

# OU clonar repositório e executar localmente
git clone https://github.com/SamurEye/SamurEye.git
cd SamurEye/docs/deployment/vlxsam01/
chmod +x install.sh
./install.sh
```

### O que o Script Instala

1. **Sistema Base**
   - Atualização do sistema Ubuntu
   - Instalação do NGINX
   - Configuração de firewall UFW
   - Configuração de timezone

2. **SSL/TLS**
   - Certbot para Let's Encrypt
   - Configuração DNS-01 challenge
   - Certificados wildcard (*.samureye.com.br)
   - Renovação automática via cron

3. **NGINX**
   - Configuração proxy reverso
   - Rate limiting avançado
   - Headers de segurança
   - Compressão gzip
   - Cache otimizado

4. **Monitoramento**
   - Scripts de health check
   - Logs estruturados
   - Alertas automáticos

## Configuração Pós-Instalação

### 1. Verificar Certificados SSL

```bash
# Verificar status dos certificados
./scripts/check-ssl.sh

# Testar renovação
certbot renew --dry-run
```

### 2. Configurar DNS (se necessário)

```bash
# Editar configuração DNS para certificados
nano /etc/letsencrypt/renewal-hooks/deploy/dns-config.sh
```

### 3. Ajustar Rate Limiting (opcional)

```bash
# Editar limites de requisições
nano /etc/nginx/conf.d/rate-limits.conf
nginx -t && systemctl reload nginx
```

## Verificação da Instalação

### Testar Conectividade

```bash
# Testar HTTPS
curl -I https://app.samureye.com.br

# Verificar redirecionamento HTTP→HTTPS
curl -I http://app.samureye.com.br

# Testar rate limiting
./scripts/test-rate-limits.sh
```

### Verificar Serviços

```bash
# Status do NGINX
systemctl status nginx

# Logs em tempo real
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# Logs específicos SamurEye
tail -f /var/log/nginx/samureye-access.log
tail -f /var/log/nginx/samureye-error.log
```

## Rotas Configuradas

### Principais Endpoints

```nginx
# Frontend da aplicação (React 18 + Vite)
https://app.samureye.com.br → http://172.24.1.152:5000

# API backend (Node.js + Express)
https://api.samureye.com.br/api → http://172.24.1.152:5000/api

# WebSocket para tempo real
https://app.samureye.com.br/ws → ws://172.24.1.152:5000/ws

# Admin dashboard (local authentication)
https://app.samureye.com.br/admin → http://172.24.1.152:5000/admin

# Object storage assets
https://app.samureye.com.br/public-objects/* → Object Storage
```

### Rate Limits

```nginx
# API endpoints
/api/* → 100 req/min por IP
/api/admin/login → 10 req/min por IP (admin protection)
/api/objects/upload → 20 req/min por IP (object storage)

# Frontend assets
Static files → 1000 req/min por IP
/public-objects/* → 500 req/min por IP (asset serving)

# Multi-tenant specific
/api/admin/* → 30 req/min por IP (admin operations)
/api/dashboard/* → 200 req/min por IP (dashboard data)
```

## Troubleshooting

### Problemas SSL

```bash
# Verificar certificados
openssl x509 -in /etc/letsencrypt/live/samureye.com.br/fullchain.pem -text -noout

# Renovar manualmente
certbot renew --force-renewal

# Logs de certificados
tail -f /var/log/letsencrypt/letsencrypt.log
```

### Problemas NGINX

```bash
# Testar configuração
nginx -t

# Recarregar sem interrupção
systemctl reload nginx

# Verificar upstreams
curl -I http://172.24.1.152:5000/api/admin/stats

# Testar autenticação dual
curl -X POST http://172.24.1.152:5000/api/admin/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@samureye.com.br", "password": "SamurEye2024!"}'

# Testar object storage
curl -I http://172.24.1.152:5000/api/system/settings
```

### Problemas de Conectividade

```bash
# Verificar conectividade com vlxsam02
nc -zv 172.24.1.152 5000

# Testar DNS
dig app.samureye.com.br
dig api.samureye.com.br

# Verificar firewall
ufw status verbose

# Testar multi-tenant routing
curl -H "Host: app.samureye.com.br" https://app.samureye.com.br/api/admin/stats

# Testar WebSocket
wscat -c wss://app.samureye.com.br/ws

# Testar object storage routing
curl -I https://app.samureye.com.br/public-objects/test
```

## Monitoramento

### Scripts de Verificação

```bash
# Verificação completa
./scripts/health-check.sh

# Apenas SSL
./scripts/check-ssl.sh

# Apenas conectividade
./scripts/check-connectivity.sh
```

### Logs Importantes

```bash
# Acesso geral
tail -f /var/log/nginx/access.log

# Erros NGINX
tail -f /var/log/nginx/error.log

# SamurEye específico
tail -f /var/log/nginx/samureye-*.log

# Sistema
journalctl -u nginx -f
```

## Manutenção

### Updates Regulares

```bash
# Update sistema
apt update && apt upgrade -y

# Restart NGINX (se necessário)
systemctl restart nginx
```

### Backup Configurações

```bash
# Backup automático (diário via cron)
./scripts/backup-config.sh

# Backup manual
tar -czf /opt/backup/nginx-$(date +%Y%m%d).tar.gz /etc/nginx/
```

## Segurança

### Headers Configurados

- HSTS (HTTP Strict Transport Security)
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- Referrer-Policy: strict-origin-when-cross-origin
- Content-Security-Policy headers
- X-XSS-Protection: 1; mode=block

### Rate Limiting

- Proteção contra DDoS básico
- Limits por IP e por endpoint
- Blacklist automático para IPs abusivos
- Proteção especial para endpoints admin
- Rate limiting diferenciado para object storage

### Firewall

```bash
# Portas abertas
ufw status
# 22/tcp (SSH)
# 80/tcp (HTTP - redirect)
# 443/tcp (HTTPS)
```

### Funcionalidades Específicas

- **Multi-tenant Support**: Roteamento baseado em cabeçalhos
- **Object Storage**: Proxy para assets estáticos e uploads
- **WebSocket**: Suporte nativo para comunicação real-time
- **Admin Protection**: Rate limiting especial para endpoints administrativos
- **Session Management**: Suporte para autenticação dual (admin + tenant)

## Arquivos de Configuração Principais

```bash
# NGINX principal
/etc/nginx/nginx.conf

# Configuração SamurEye
/etc/nginx/sites-available/samureye
/etc/nginx/sites-enabled/samureye

# Rate limiting
/etc/nginx/conf.d/rate-limits.conf

# SSL certificates
/etc/letsencrypt/live/samureye.com.br/

# Scripts de monitoramento
/opt/samureye/scripts/
```