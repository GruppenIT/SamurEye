# Guia DNS Challenge para Certificado Wildcard

## Visão Geral

O certificado wildcard (*.samureye.com.br) permite cobrir todos os subdomínios com um único certificado. Ele usa DNS challenge, onde você precisa adicionar registros TXT temporários no DNS.

## Processo Passo a Passo

### 1. Executar o Script SSL

```bash
/opt/request-ssl.sh
```

### 2. Quando Solicitado, Adicionar Registros TXT

⚠️ **IMPORTANTE**: Certificados wildcard requerem **DOIS** registros TXT com o mesmo nome!

O Certbot irá pausar **DUAS VEZES** e solicitar registros diferentes:

**Primeira pausa:**
```
Please deploy a DNS TXT record under the name:
_acme-challenge.samureye.com.br.
with the following value:
z4LV2dfOV2DQmn3NIVex9hODoQpYha622okDAUXbtq0
Press Enter to Continue
```

**Segunda pausa:**
```
Please deploy a DNS TXT record under the name:
_acme-challenge.samureye.com.br.
with the following value:
vzNQ6MJBrUrKEqeEAJE_MXNfJX-MLn9wOkP97vXWafg
(This must be set up in addition to the previous challenges; do not remove...)
Press Enter to Continue
```

### 3. Configurar AMBOS os Registros DNS TXT

No seu provedor de DNS, você deve ter **DOIS** registros TXT com o MESMO nome:

**Registro 1:**
- **Nome**: `_acme-challenge.samureye.com.br`
- **Tipo**: `TXT`
- **Valor**: `z4LV2dfOV2DQmn3NIVex9hODoQpYha622okDAUXbtq0`

**Registro 2:**
- **Nome**: `_acme-challenge.samureye.com.br`
- **Tipo**: `TXT`
- **Valor**: `vzNQ6MJBrUrKEqeEAJE_MXNfJX-MLn9wOkP97vXWafg`

🔴 **CRUCIAL**: NÃO remova o primeiro registro quando adicionar o segundo!

### 4. Verificar AMBOS os DNS TXT

Antes de pressionar Enter no Certbot, verifique se AMBOS os registros estão propagados:

```bash
# Verificar TXT records - deve mostrar AMBOS os valores
dig TXT _acme-challenge.samureye.com.br

# Resposta esperada (exemplo):
# _acme-challenge.samureye.com.br. 60 IN TXT "z4LV2dfOV2DQmn3NIVex9hODoQpYha622okDAUXbtq0"
# _acme-challenge.samureye.com.br. 60 IN TXT "vzNQ6MJBrUrKEqeEAJE_MXNfJX-MLn9wOkP97vXWafg"

# Ou usar nslookup
nslookup -type=TXT _acme-challenge.samureye.com.br
```

⚠️ **IMPORTANTE**: Se você ver apenas UM registro TXT, aguarde a propagação DNS antes de continuar no Certbot!

### 5. Continuar o Processo

Depois de verificar que os registros TXT estão ativos, pressione Enter no Certbot.

## Exemplos por Provedor DNS

### Cloudflare - DOIS Registros TXT

**Para o primeiro registro:**
1. Login no Cloudflare Dashboard
2. Selecionar domínio `samureye.com.br`
3. Ir em **DNS > Records**
4. Clicar **Add record**
5. **Type**: `TXT`
6. **Name**: `_acme-challenge`
7. **Content**: `z4LV2dfOV2DQmn3NIVex9hODoQpYha622okDAUXbtq0`
8. **TTL**: `Auto`
9. Salvar

**Para o segundo registro:**
1. Clicar **Add record** novamente
2. **Type**: `TXT`
3. **Name**: `_acme-challenge` (mesmo nome!)
4. **Content**: `vzNQ6MJBrUrKEqeEAJE_MXNfJX-MLn9wOkP97vXWafg`
5. **TTL**: `Auto`
6. Salvar

**Resultado final:** Dois registros TXT com mesmo nome mas valores diferentes

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

### Erro: Apenas um registro TXT encontrado
Se o erro mostrar "Incorrect TXT record", provavelmente você não adicionou AMBOS os registros:

```bash
# Verificar quantos registros existem
dig TXT _acme-challenge.samureye.com.br | grep -c "TXT"

# Deve retornar "2" - se retornar "1", adicione o segundo registro!
```

**Solução:**
1. Verificar se ambos os registros TXT estão no DNS
2. Aguardar propagação de ambos (pode levar 5-10 minutos)
3. Executar `/opt/request-ssl.sh` novamente

### Erro de verificação
- Verificar se AMBOS os registros TXT estão corretos e ativos
- Aguardar propagação DNS completa de ambos os registros
- Limpar cache DNS local: `sudo systemctl flush-dns` ou `sudo resolvectl flush-caches`
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