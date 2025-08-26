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
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam01/install.sh | bash

# OU clonar repositório e executar localmente
git clone https://github.com/GruppenIT/SamurEye.git
cd SamurEye/docs/deployment/vlxsam01/
chmod +x install.sh
./install.sh
```

### O que o Script Instala (100% Automatizado)

1. **Sistema Base**
   - Atualização completa do sistema Ubuntu
   - Instalação do NGINX, Certbot, Fail2Ban
   - Configuração de firewall UFW (portas 22, 80, 443)
   - Timezone America/Sao_Paulo

2. **NGINX Configuração Inteligente**
   - Configuração temporária HTTP (sem SSL) ativada automaticamente
   - Configuração final HTTPS preparada (será ativada após SSL)
   - Rate limiting avançado por endpoint
   - Headers de segurança obrigatórios
   - Proxy reverso para vlxsam02:5000

3. **Scripts SSL Automáticos**
   - `/opt/request-ssl.sh` - HTTP-01 challenge (simples)
   - `/opt/request-ssl-wildcard.sh` - DNS challenge (wildcard)
   - Renovação automática via cron (2x por dia)

4. **Monitoramento e Scripts**
   - `/opt/samureye/scripts/health-check.sh` - Status completo
   - `/opt/samureye/scripts/check-ssl.sh` - Verificação SSL
   - Logs estruturados e rotação automática
   - Fail2Ban configurado

## Processo de Instalação em Duas Etapas

### ✅ Etapa 1: Instalação Base (Automática)

```bash
# Script de instalação - executa tudo automaticamente
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam01/install.sh | bash
```

**Resultado:** NGINX funcionando com HTTP, ready para SSL

### ⚠️ Etapa 2: Configuração SSL (Manual - Aguarda DNS)

```bash
# PRIMEIRO: Configurar DNS (obrigatório)
# Criar registros DNS para:
# samureye.com.br -> 172.24.1.151
# app.samureye.com.br -> 172.24.1.151  
# api.samureye.com.br -> 172.24.1.151

# DEPOIS: Solicitar certificados SSL
/opt/request-ssl.sh

# OU para certificado wildcard (se suportado pelo DNS):
/opt/request-ssl-wildcard.sh
```

**Resultado:** NGINX com HTTPS funcionando, redirecionamento automático

## Verificação e Testes

### Scripts de Teste Automático

```bash
# Teste completo da instalação
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam01/test-install.sh | bash

# Health check completo
/opt/samureye/scripts/health-check.sh

# Verificação específica SSL
/opt/samureye/scripts/check-ssl.sh
```

### Testes Manuais

```bash
# Testar proxy reverso HTTP (sem SSL)
curl -I http://172.24.1.151/nginx-health

# Testar HTTPS (após configurar SSL)
curl -I https://app.samureye.com.br/nginx-health

# Verificar rate limiting
for i in {1..5}; do curl -I https://app.samureye.com.br/api/; done

# Testar WebSocket (após vlxsam02 configurado)
wscat -c wss://app.samureye.com.br/ws
```

## Troubleshooting

### Problemas Comuns

```bash
# NGINX não inicia - verificar configuração
nginx -t
systemctl status nginx

# SSL não funciona - verificar certificados
/opt/samureye/scripts/check-ssl.sh
ls -la /etc/letsencrypt/live/samureye.com.br/

# Proxy reverso falha - verificar vlxsam02
nc -z 172.24.1.152 5000
curl -I http://172.24.1.152:5000/

# Rate limiting muito restritivo - ajustar configuração
nano /etc/nginx/sites-available/samureye
nginx -t && systemctl reload nginx
```

### Reset Completo 

```bash
# Reset completo - funciona sempre (corrigido em 26/08/2025)
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam01/install.sh | bash

# Erros anteriores resolvidos:
# ✅ Directory creation error: /opt/samureye/scripts/
# ✅ NGINX SSL configuration order  
# ✅ Certificate dependency issues
```

## Arquivos Importantes

```
/opt/request-ssl.sh              # Script solicitação SSL (HTTP-01)
/opt/request-ssl-wildcard.sh     # Script SSL wildcard (DNS)
/opt/samureye/scripts/           # Scripts de manutenção
/etc/nginx/sites-available/      # Configurações NGINX
/etc/letsencrypt/live/           # Certificados SSL
/var/log/nginx/                  # Logs NGINX
/var/log/samureye/               # Logs sistema
```

## Monitoramento

### Logs em Tempo Real

```bash
# Logs de acesso
tail -f /var/log/nginx/samureye-access.log

# Logs de erro
tail -f /var/log/nginx/samureye-error.log

# Logs de API
tail -f /var/log/nginx/api-access.log

# Health check automático
tail -f /var/log/samureye/health-check.log
```

### Métricas Automáticas

- **Health check**: A cada 5 minutos via cron
- **Renovação SSL**: 2x por dia (2h e 14h)
- **Fail2Ban**: Monitoramento ativo de IPs maliciosos
- **Log rotation**: Logs rotacionados diariamente (30 dias de retenção)

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