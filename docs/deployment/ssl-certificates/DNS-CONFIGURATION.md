# Configuração DNS para SamurEye - Let's Encrypt DNS Challenge

Este documento detalha como configurar diferentes provedores DNS para usar com Let's Encrypt DNS-01 Challenge.

## Índice

- [Cloudflare](#cloudflare)
- [AWS Route53](#aws-route53)
- [Google Cloud DNS](#google-cloud-dns)
- [Configuração Manual](#configuração-manual)
- [Troubleshooting](#troubleshooting)

---

## Cloudflare

### Pré-requisitos

1. Domínio `samureye.com.br` configurado no Cloudflare
2. Acesso à dashboard do Cloudflare

### Configuração

#### 1. Criar API Token

1. Acesse [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Clique em "Create Token"
3. Use o template "Custom token" com as seguintes permissões:

```
Permissions:
- Zone:Zone:Read
- Zone:DNS:Edit

Zone Resources:
- Include: Specific zone: samureye.com.br
```

4. Clique "Continue to summary" e depois "Create Token"
5. **Importante**: Copie o token e guarde com segurança

#### 2. Configurar Credenciais

```bash
sudo mkdir -p /etc/letsencrypt
sudo nano /etc/letsencrypt/cloudflare.ini
```

Adicione o conteúdo:
```ini
dns_cloudflare_api_token = seu_token_aqui
```

Defina permissões seguras:
```bash
sudo chmod 600 /etc/letsencrypt/cloudflare.ini
```

#### 3. Instalar Plugin

```bash
sudo apt install -y python3-certbot-dns-cloudflare
```

#### 4. Obter Certificado

```bash
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --email admin@samureye.com.br \
  --agree-tos \
  --no-eff-email \
  -d "*.samureye.com.br" \
  -d "samureye.com.br"
```

---

## AWS Route53

### Pré-requisitos

1. Domínio `samureye.com.br` hospedado no Route53
2. Credenciais AWS configuradas

### Configuração

#### 1. Configurar IAM Policy

Crie uma policy com as seguintes permissões:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets",
                "route53:ListResourceRecordSets"
            ],
            "Resource": "arn:aws:route53:::hostedzone/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:GetHostedZone"
            ],
            "Resource": "*"
        }
    ]
}
```

#### 2. Configurar Credenciais AWS

**Opção 1: AWS CLI**
```bash
aws configure
# Insira AWS Access Key ID
# Insira AWS Secret Access Key
# Insira região (ex: us-east-1)
```

**Opção 2: IAM Role (recomendado para EC2)**
```bash
# Anexe a policy IAM à instância EC2 via IAM Role
# Não são necessárias credenciais explícitas
```

#### 3. Instalar Plugin

```bash
sudo apt install -y python3-certbot-dns-route53
```

#### 4. Obter Certificado

```bash
sudo certbot certonly \
  --dns-route53 \
  --email admin@samureye.com.br \
  --agree-tos \
  --no-eff-email \
  -d "*.samureye.com.br" \
  -d "samureye.com.br"
```

---

## Google Cloud DNS

### Pré-requisitos

1. Projeto Google Cloud com Cloud DNS habilitado
2. Zona DNS criada para `samureye.com.br`

### Configuração

#### 1. Criar Service Account

1. Acesse [Google Cloud Console](https://console.cloud.google.com/)
2. Navegue para "IAM & Admin" > "Service Accounts"
3. Clique "Create Service Account"
4. Nomeie: `samureye-dns-admin`
5. Atribua a role: `DNS Administrator`
6. Clique "Create Key" > "JSON"
7. Baixe o arquivo JSON

#### 2. Configurar Credenciais

```bash
sudo mkdir -p /etc/letsencrypt
sudo cp caminho/para/service-account.json /etc/letsencrypt/google.json
sudo chmod 600 /etc/letsencrypt/google.json
```

#### 3. Instalar Plugin

```bash
sudo apt install -y python3-certbot-dns-google
```

#### 4. Obter Certificado

```bash
sudo certbot certonly \
  --dns-google \
  --dns-google-credentials /etc/letsencrypt/google.json \
  --email admin@samureye.com.br \
  --agree-tos \
  --no-eff-email \
  -d "*.samureye.com.br" \
  -d "samureye.com.br"
```

---

## Configuração Manual

Para provedores DNS não suportados automaticamente.

### Processo

1. Execute o comando certbot:

```bash
sudo certbot certonly \
  --manual \
  --preferred-challenges dns \
  --email admin@samureye.com.br \
  --agree-tos \
  --no-eff-email \
  -d "*.samureye.com.br" \
  -d "samureye.com.br"
```

2. O certbot irá solicitar que você crie registros TXT no DNS:

```
Please deploy a DNS TXT record under the name
_acme-challenge.samureye.com.br with the following value:

abc123def456...

Before continuing, verify the record is deployed.
```

3. **No seu provedor DNS**, crie o registro:
   - **Tipo**: TXT
   - **Nome**: `_acme-challenge.samureye.com.br`
   - **Valor**: `abc123def456...` (valor fornecido pelo certbot)
   - **TTL**: 300 (5 minutos)

4. Verifique a propagação:

```bash
dig TXT _acme-challenge.samureye.com.br
# ou
nslookup -type=TXT _acme-challenge.samureye.com.br
```

5. Pressione ENTER no certbot para continuar

### Providers Testados Manualmente

- **Registro.br**: Suporte completo
- **GoDaddy**: Suporte completo
- **Namecheap**: Suporte completo
- **HUAWEI Cloud**: Suporte completo

---

## Troubleshooting

### Problemas Comuns

#### 1. Erro: "DNS problem: NXDOMAIN"

**Causa**: Registro DNS não existe ou não propagou
**Solução**:
```bash
# Verificar propagação DNS
dig TXT _acme-challenge.samureye.com.br @8.8.8.8
# Aguardar propagação (pode demorar até 60 min)
```

#### 2. Erro: "The client lacks sufficient authorization"

**Causa**: Credenciais insuficientes
**Solução**:
- Cloudflare: Verificar permissões do token
- AWS: Verificar policy IAM
- GCP: Verificar roles da service account

#### 3. Erro: "Timeout during connect"

**Causa**: Problemas de rede ou firewall
**Solução**:
```bash
# Testar conectividade
curl -I https://acme-v02.api.letsencrypt.org/
# Verificar DNS público
systemd-resolve --status
```

#### 4. Certificado não renovando automaticamente

**Causa**: Credenciais expiraram ou configuração mudou
**Solução**:
```bash
# Testar renovação
sudo certbot renew --dry-run
# Verificar logs
sudo journalctl -u certbot.timer
```

### Logs Importantes

```bash
# Logs do Certbot
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Logs de sistema
sudo journalctl -u certbot.timer -f

# Verificar certificados
sudo certbot certificates
```

### Comandos de Diagnóstico

```bash
# Verificar domínios e certificados
/opt/check-certificates.sh

# Testar NGINX com novos certificados
sudo nginx -t && sudo systemctl reload nginx

# Verificar status SSL online
curl -I https://app.samureye.com.br
```

### Migração de HTTP para DNS Challenge

Se você já tem certificados obtidos via HTTP-01:

```bash
# Use o script de migração
sudo ./ssl-certificates/setup-certificates.sh
# Escolha opção 6 (Migrar para wildcard)

# OU faça manualmente:
sudo certbot delete --cert-name app.samureye.com.br
sudo certbot delete --cert-name api.samureye.com.br
sudo certbot delete --cert-name scanner.samureye.com.br

# Depois obtenha novo certificado wildcard
```

---

## Referências

- [Certbot DNS Plugins](https://certbot.eff.org/docs/using.html#dns-plugins)
- [Let's Encrypt DNS-01 Challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge)
- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [AWS Route53 API Reference](https://docs.aws.amazon.com/route53/latest/APIReference/)