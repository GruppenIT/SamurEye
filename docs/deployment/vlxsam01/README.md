# vlxsam01 - Gateway Server

Gateway NGINX com SSL termination, proxy reverso e step-ca Certificate Authority para ambiente on-premise SamurEye.

## 📋 Informações do Servidor

- **IP**: 192.168.100.151
- **Função**: Gateway/Proxy SSL
- **OS**: Ubuntu 24.04 LTS
- **Serviços**: NGINX, step-ca, Fail2ban, UFW

## 🎯 Cenários de Instalação

### ✅ Instalação Padrão
```bash
ssh root@192.168.100.151
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/install.sh | bash
```

### 🔥 **HARD RESET (Recomendado para ambiente corrompido)**
```bash
ssh root@192.168.100.151
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/install-hard-reset.sh | bash
```

**⚠️ O hard reset preserva certificados SSL válidos automaticamente!**

## 🏗️ Arquitetura

```
Internet
    ↓
┌─────────────────────────────────────┐
│            vlxsam01                 │
│         (192.168.100.151)          │
│                                     │
│  ┌─────────┐    ┌─────────────────┐ │
│  │  NGINX  │────│    step-ca      │ │
│  │  :80    │    │    :8443        │ │
│  │  :443   │    │                 │ │
│  └─────────┘    └─────────────────┘ │
│      │                              │
└──────┼──────────────────────────────┘
       │
       ↓ Proxy to
┌─────────────────────────────────────┐
│            vlxsam02                 │
│         (192.168.100.152:5000)     │
│        SamurEye Application         │
└─────────────────────────────────────┘
```

## 🔧 Serviços Configurados

### NGINX (Port 80/443)
- **Proxy reverso** para vlxsam02:5000
- **SSL termination** com certificados Let's Encrypt
- **Rate limiting** para proteção contra DDoS
- **Security headers** (HSTS, CSP, etc.)

### step-ca (Port 8443)
- **Certificate Authority** interno
- **mTLS certificates** para collectors
- **Integração com SamurEye** para autenticação

### UFW Firewall
- **SSH (22)**: Acesso de administração
- **HTTP/HTTPS (80/443)**: Tráfego web público
- **step-ca (8443)**: Certificate Authority
- **Rede interna**: 192.168.100.0/24

### Fail2ban
- **Proteção SSH**: Bloqueio após tentativas falhas
- **Proteção NGINX**: Rate limiting avançado
- **Logs centralizados**: Monitoramento de ataques

## 🌐 Domínios Configurados

### Produção
- **app.samureye.com.br** → vlxsam02:5000 (Frontend)
- **api.samureye.com.br** → vlxsam02:5000 (API)
- **ca.samureye.com.br** → localhost:8443 (step-ca)

### Configuração DNS Necessária
```
Type    Name                Value
A       app.samureye.com.br 192.168.100.151
A       api.samureye.com.br 192.168.100.151
A       ca.samureye.com.br  192.168.100.151
```

## 🔐 Certificados SSL

### Backup Automático (Hard Reset)
O script de hard reset cria backup automático em:
```
/etc/nginx/ssl-backup-YYYYMMDD-HHMMSS/
├── letsencrypt/     # Certificados Let's Encrypt
├── ssl/             # Certificados NGINX
├── step-ca/         # Certificações step-ca
└── sites-available/ # Configurações NGINX
```

### Renovação Manual (se necessário)
```bash
# Certificado wildcard com DNS-01 challenge
certbot --nginx -d samureye.com.br -d *.samureye.com.br

# Verificar renovação automática
certbot renew --dry-run
```

## 📊 Monitoramento e Logs

### Status dos Serviços
```bash
# Verificar todos os serviços
systemctl status nginx step-ca fail2ban ufw

# Verificar portas abertas
netstat -tlnp | grep -E ':80|:443|:8443'
```

### Logs Principais
```bash
# NGINX Access/Error
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# step-ca
journalctl -u step-ca -f

# Fail2ban
tail -f /var/log/fail2ban.log

# UFW
tail -f /var/log/ufw.log
```

### Testes de Conectividade
```bash
# Teste local
curl -I http://localhost
curl -I https://localhost

# Teste externo (do vlxsam02)
curl -I http://192.168.100.151
curl -I https://app.samureye.com.br

# Teste step-ca
curl -k https://localhost:8443/health
```

## 🔧 Comandos de Manutenção

### Reiniciar Serviços
```bash
systemctl restart nginx
systemctl restart step-ca
systemctl restart fail2ban
```

### Recarregar Configurações
```bash
# NGINX (sem parar o serviço)
nginx -t && nginx -s reload

# Fail2ban
fail2ban-client reload
```

### Backup Manual
```bash
# Backup completo de configurações
tar -czf /tmp/vlxsam01-backup-$(date +%Y%m%d).tar.gz \
    /etc/nginx \
    /etc/letsencrypt \
    /etc/step-ca \
    /etc/fail2ban
```

## 🚨 Resolução de Problemas

### Problema: NGINX não inicia
```bash
# Verificar configuração
nginx -t

# Verificar conflitos de porta
netstat -tlnp | grep :80
netstat -tlnp | grep :443

# Logs de erro
tail -50 /var/log/nginx/error.log
```

### Problema: Certificados SSL expirados
```bash
# Verificar validade
openssl x509 -in /etc/letsencrypt/live/samureye.com.br/fullchain.pem -enddate -noout

# Forçar renovação
certbot renew --force-renewal

# Recarregar NGINX
nginx -s reload
```

### Problema: step-ca não responde
```bash
# Verificar status
systemctl status step-ca

# Verificar configuração
step ca health --ca-url https://localhost:8443

# Logs detalhados
journalctl -u step-ca -f
```

### Problema: Conectividade com vlxsam02
```bash
# Testar conectividade
nc -zv 192.168.100.152 5000

# Verificar roteamento
ip route show

# Testar proxy NGINX
curl -H "Host: app.samureye.com.br" http://192.168.100.152:5000
```

## 📋 Checklist Pós-Instalação

### ✅ Validação Básica
- [ ] NGINX ativo: `systemctl is-active nginx`
- [ ] step-ca ativo: `systemctl is-active step-ca`
- [ ] Portas abertas: `netstat -tlnp | grep -E ':80|:443|:8443'`
- [ ] Firewall ativo: `ufw status`

### ✅ Testes de Conectividade
- [ ] HTTP local: `curl -I http://localhost`
- [ ] HTTPS local: `curl -I https://localhost`
- [ ] Proxy para vlxsam02: `curl -I http://192.168.100.152:5000`

### ✅ Certificados SSL
- [ ] Certificados válidos: `openssl x509 -in /path/cert -enddate -noout`
- [ ] Renovação automática: `certbot renew --dry-run`

### ✅ Segurança
- [ ] Fail2ban ativo: `systemctl is-active fail2ban`
- [ ] UFW configurado: `ufw status numbered`
- [ ] Headers de segurança: `curl -I https://app.samureye.com.br`

## 📁 Estrutura de Arquivos

```
/etc/nginx/
├── nginx.conf              # Configuração principal
├── sites-available/
│   └── samureye            # Configuração SamurEye
├── sites-enabled/
│   └── samureye -> ../sites-available/samureye
└── ssl/                    # Certificados personalizados

/etc/step-ca/
├── config/
│   ├── ca.json            # Configuração step-ca
│   ├── password.txt       # Senha do CA
│   └── defaults.json      # Configurações padrão
├── certs/                 # Certificados emitidos
├── secrets/               # Chaves privadas
└── db/                    # Database step-ca

/etc/letsencrypt/
├── live/samureye.com.br/  # Certificados ativos
├── archive/               # Histórico de certificados
└── renewal/               # Configurações de renovação

/var/log/
├── nginx/                 # Logs NGINX
├── fail2ban.log          # Logs Fail2ban
└── ufw.log               # Logs UFW
```

## 🔗 Links Relacionados

- **Aplicação**: [vlxsam02/README.md](../vlxsam02/README.md)
- **Banco de Dados**: [vlxsam03/README.md](../vlxsam03/README.md)  
- **Collector**: [vlxsam04/README.md](../vlxsam04/README.md)
- **Arquitetura**: [../NETWORK-ARCHITECTURE.md](../NETWORK-ARCHITECTURE.md)