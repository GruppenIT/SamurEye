# Guia DNS Challenge para Certificado Wildcard

## Visão Geral

O certificado wildcard (*.samureye.com.br) permite cobrir todos os subdomínios com um único certificado. Ele usa DNS challenge, onde você precisa adicionar registros TXT temporários no DNS.

## Processo Passo a Passo

### 1. Executar o Script SSL

```bash
/opt/request-ssl.sh
```

### 2. Quando Solicitado, Adicionar Registros TXT

O Certbot irá parar e mostrar algo como:

```
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Please deploy a DNS TXT record under the name
_acme-challenge.samureye.com.br with the following value:

XYZ123ABC456...

Before continuing, verify the record is deployed.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Press Enter to Continue
```

### 3. Configurar DNS TXT Records

No seu provedor de DNS (Cloudflare, Route53, etc.), adicione:

**Primeiro registro:**
- **Nome**: `_acme-challenge.samureye.com.br`
- **Tipo**: `TXT`
- **Valor**: `XYZ123ABC456...` (valor mostrado pelo Certbot)

**Segundo registro** (será solicitado):
- **Nome**: `_acme-challenge.samureye.com.br`
- **Tipo**: `TXT`
- **Valor**: `DEF789GHI012...` (segundo valor)

### 4. Verificar DNS TXT

Antes de pressionar Enter, verifique se os registros estão propagados:

```bash
# Verificar TXT records
dig TXT _acme-challenge.samureye.com.br

# Ou usar nslookup
nslookup -type=TXT _acme-challenge.samureye.com.br
```

### 5. Continuar o Processo

Depois de verificar que os registros TXT estão ativos, pressione Enter no Certbot.

## Exemplos por Provedor DNS

### Cloudflare
1. Login no Cloudflare Dashboard
2. Selecionar domínio `samureye.com.br`
3. Ir em **DNS > Records**
4. Clicar **Add record**
5. **Type**: `TXT`
6. **Name**: `_acme-challenge`
7. **Content**: `[valor do certbot]`
8. **TTL**: `Auto`
9. Salvar

### AWS Route53
```bash
aws route53 change-resource-record-sets \
    --hosted-zone-id ZXXXXXXXXXXXXX \
    --change-batch '{
        "Changes": [{
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "_acme-challenge.samureye.com.br",
                "Type": "TXT",
                "TTL": 60,
                "ResourceRecords": [{"Value": "\"[valor do certbot]\""}]
            }
        }]
    }'
```

### Google Cloud DNS
```bash
gcloud dns record-sets create _acme-challenge.samureye.com.br \
    --zone=samureye-zone \
    --type=TXT \
    --ttl=60 \
    --rrdatas="[valor do certbot]"
```

## Verificação Final

Após obter o certificado, verificar:

```bash
# Testar certificado
/opt/samureye/scripts/check-ssl.sh

# Verificar NGINX
nginx -t

# Testar HTTPS
curl -I https://app.samureye.com.br/nginx-health
```

## Solução de Problemas

### DNS TXT não propagado
```bash
# Aguardar propagação (pode levar até 10 minutos)
watch -n 30 'dig TXT _acme-challenge.samureye.com.br'
```

### Erro de verificação
- Verificar se os registros TXT estão corretos
- Aguardar propagação DNS completa
- Tentar novamente o comando `/opt/request-ssl.sh`

### Certificado não funciona
```bash
# Verificar arquivos de certificado
ls -la /etc/letsencrypt/live/samureye.com.br/

# Verificar configuração NGINX
nginx -t

# Reiniciar NGINX se necessário
systemctl reload nginx
```

## Comandos Úteis

```bash
# Verificar certificados existentes
certbot certificates

# Renovar certificados
certbot renew --dry-run

# Status do sistema
/opt/samureye/scripts/health-check.sh

# Logs do Certbot
tail -f /var/log/letsencrypt/letsencrypt.log
```

## Limpeza DNS

Após obter o certificado, os registros TXT podem ser removidos do DNS - eles são apenas temporários para validação.