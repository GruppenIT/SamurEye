# vlxsam01 - Gateway Server

## Visão Geral

O servidor vlxsam01 atua como gateway da plataforma SamurEye, fornecendo:
- **Proxy reverso NGINX** para roteamento de requisições
- **Terminação SSL/TLS** com certificados wildcard
- **Rate limiting** e proteção contra ataques
- **Load balancing** para alta disponibilidade
- **Redirecionamento HTTPS** obrigatório

## Especificações

- **IP:** 172.24.1.151
- **OS:** Ubuntu 22.04 LTS
- **Domínio:** *.samureye.com.br
- **Portas:** 80 (HTTP→HTTPS), 443 (HTTPS)

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
# Frontend da aplicação
https://app.samureye.com.br → http://172.24.1.152:3000

# API backend
https://api.samureye.com.br/api → http://172.24.1.152:3000/api

# WebSocket para tempo real
https://app.samureye.com.br/ws → ws://172.24.1.152:3000/ws

# Admin dashboard
https://admin.samureye.com.br → http://172.24.1.152:3000/admin
```

### Rate Limits

```nginx
# API endpoints
/api/* → 100 req/min por IP
/auth/* → 20 req/min por IP
/upload/* → 10 req/min por IP

# Frontend assets
Static files → 1000 req/min por IP
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
curl -I http://172.24.1.152:3000/api/health
```

### Problemas de Conectividade

```bash
# Verificar conectividade com vlxsam02
nc -zv 172.24.1.152 3000

# Testar DNS
dig app.samureye.com.br
dig api.samureye.com.br

# Verificar firewall
ufw status verbose
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

### Rate Limiting

- Proteção contra DDoS básico
- Limits por IP e por endpoint
- Blacklist automático para IPs abusivos

### Firewall

```bash
# Portas abertas
ufw status
# 22/tcp (SSH)
# 80/tcp (HTTP - redirect)
# 443/tcp (HTTPS)
```