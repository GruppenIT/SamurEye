# Troubleshooting - Certificados SSL/TLS SamurEye

## Problemas Comuns e Soluções

### ❌ Erro: "Service busy; retry later"

**Causa**: Rate limiting do Let's Encrypt (mais de 5 tentativas por semana)

**Solução**:
```bash
# Verificar certificados existentes
sudo certbot certificates

# Limpar certificados de teste se necessário
sudo certbot delete --cert-name samureye.com.br

# Aguardar 1-24 horas e tentar novamente
# OU usar opção 7 (DNS Manual Assistido) do script
```

### ❌ Múltiplos Desafios DNS com Mesmo Nome

**Situação**: Let's Encrypt pede dois registros TXT com mesmo nome

**Como configurar no DNS**:

#### Cloudflare:
1. Adicione o primeiro registro TXT
2. **NÃO remova** o primeiro ao adicionar o segundo
3. Cloudflare suporta múltiplos registros com mesmo nome automaticamente

#### Outros Provedores:
```
Registro 1:
Nome: _acme-challenge.samureye.com.br
Tipo: TXT  
Valor: UQERuNT2MAr3ZibDKN8u4mhlXZTR0EyMG1tPS4svPa0

Registro 2 (mesmo nome!):
Nome: _acme-challenge.samureye.com.br
Tipo: TXT
Valor: ri7DS3EW0vrtgyhKQzKHJymNCuV34fAdMoV-6QOIGSY
```

**Verificação**:
```bash
# Deve mostrar AMBOS os valores
dig TXT _acme-challenge.samureye.com.br @8.8.8.8
```

### ❌ DNS Não Propaga

**Verificação**:
```bash
# Testar diferentes servidores DNS
dig TXT _acme-challenge.samureye.com.br @8.8.8.8
dig TXT _acme-challenge.samureye.com.br @1.1.1.1
dig TXT _acme-challenge.samureye.com.br @208.67.222.222

# Verificar com nslookup
nslookup -type=TXT _acme-challenge.samureye.com.br
```

**Solução**:
- Aguardar 10-60 minutos para propagação
- Alguns provedores DNS levam mais tempo
- Usar ferramentas online: whatsmydns.net

### ❌ Certificado Não Reconhecido pelo NGINX

**Verificação**:
```bash
# Testar configuração NGINX
sudo nginx -t

# Verificar caminhos dos certificados
sudo ls -la /etc/letsencrypt/live/samureye.com.br/

# Verificar permissões
sudo chown root:root /etc/letsencrypt/live/samureye.com.br/*
sudo chmod 644 /etc/letsencrypt/live/samureye.com.br/fullchain.pem
sudo chmod 600 /etc/letsencrypt/live/samureye.com.br/privkey.pem
```

**Configuração NGINX Correta**:
```nginx
# Para certificado wildcard
ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;
```

### ❌ Renovação Automática Não Funciona

**Verificação**:
```bash
# Testar renovação
sudo certbot renew --dry-run

# Verificar cron
sudo crontab -l
sudo ls /etc/cron.d/certbot*

# Verificar logs
sudo journalctl -u cron -f
```

**Solução**:
```bash
# Recriar cron de renovação
sudo rm /etc/cron.d/certbot*
sudo crontab -e
# Adicionar: 0 12 * * * /usr/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx"
```

### ❌ Certificado Expirado

**Verificação**:
```bash
# Verificar status dos certificados
sudo certbot certificates

# Verificar online
openssl s_client -connect app.samureye.com.br:443 -servername app.samureye.com.br 2>/dev/null | openssl x509 -noout -dates
```

**Solução**:
```bash
# Forçar renovação
sudo certbot renew --force-renewal

# Se falhar, recriar certificado
sudo ./setup-certificates.sh
# Escolha opção 7 (DNS Manual Assistido)
```

## Comandos de Diagnóstico Úteis

```bash
# Status geral dos certificados
sudo /opt/check-certificates.sh

# Logs do certbot
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Testar conectividade SSL
curl -I https://app.samureye.com.br
openssl s_client -connect app.samureye.com.br:443

# Verificar configuração NGINX
sudo nginx -t && sudo nginx -s reload

# Status dos serviços
sudo systemctl status nginx
sudo systemctl status cron

# Verificar portas abertas
sudo netstat -tlnp | grep :443
```

## Script de Verificação Rápida

```bash
#!/bin/bash
# Diagnóstico rápido de certificados

echo "=== DIAGNÓSTICO CERTIFICADOS SAMUREYE ==="
echo ""

echo "1. Status dos certificados:"
certbot certificates 2>/dev/null || echo "Nenhum certificado encontrado"

echo ""
echo "2. Arquivos de certificado:"
ls -la /etc/letsencrypt/live/ 2>/dev/null || echo "Diretório não encontrado"

echo ""
echo "3. Teste NGINX:"
nginx -t 2>/dev/null && echo "✅ Configuração OK" || echo "❌ Erro na configuração"

echo ""
echo "4. Conectividade HTTPS:"
curl -s -o /dev/null -w "%{http_code}" https://app.samureye.com.br 2>/dev/null || echo "❌ Falha na conexão"

echo ""
echo "5. DNS Challenge records:"
dig +short TXT _acme-challenge.samureye.com.br @8.8.8.8 2>/dev/null || echo "Nenhum registro encontrado"
```

## Processo Recomendado para Resolver Problemas

1. **Identifique o erro específico** nos logs
2. **Verifique rate limits** com `certbot certificates`
3. **Use DNS Manual Assistido** (opção 7) se hit rate limit
4. **Teste com staging** primeiro antes do certificado real
5. **Verifique propagação DNS** antes de prosseguir
6. **Configure NGINX** adequadamente para wildcard
7. **Teste renovação** com `--dry-run`

## Contatos de Suporte

- **Let's Encrypt Community**: https://community.letsencrypt.org
- **Documentação Certbot**: https://certbot.eff.org/docs/
- **Verificador DNS**: https://toolbox.googleapps.com/apps/dig/