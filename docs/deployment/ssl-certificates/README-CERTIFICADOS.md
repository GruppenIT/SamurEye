# Certificados SSL/TLS - SamurEye

## Status Atual ✅

**Certificado SSL wildcard obtido com sucesso!**

- **Domínios**: `*.samureye.com.br` e `samureye.com.br`
- **Emissor**: Let's Encrypt  
- **Expiração**: 18 de Novembro de 2025 (90 dias)
- **Tipo**: Certificado manual (DNS Challenge)

## Arquivos Instalados

```
/etc/letsencrypt/live/samureye.com.br/
├── fullchain.pem     # Certificado completo (para NGINX)
├── privkey.pem       # Chave privada (para NGINX)
├── cert.pem          # Certificado apenas
└── chain.pem         # Cadeia intermediária
```

## Scripts Disponíveis

| Script | Localização | Função |
|--------|-------------|---------|
| `setup-certificates.sh` | `docs/deployment/ssl-certificates/` | Setup inicial e renovação |
| `check-ssl-status.sh` | `docs/deployment/ssl-certificates/` | Verificação completa |
| `renewal-reminder.sh` | `/opt/` | Alerta de expiração |
| `TROUBLESHOOTING-CERTIFICATES.md` | `docs/deployment/ssl-certificates/` | Guia de problemas |

## Renovação Manual 🔄

⚠️ **IMPORTANTE**: Este certificado deve ser renovado manualmente a cada 90 dias.

### Processo de Renovação

1. **30 dias antes**: Sistema envia alerta automático (cron semanal)
2. **Executar renovação**:
   ```bash
   cd /opt/samureye/docs/deployment/ssl-certificates/
   sudo ./setup-certificates.sh
   # Escolha: 7) DNS Manual Assistido
   ```
3. **Confirmar funcionamento**:
   ```bash
   sudo ./check-ssl-status.sh
   ```

### Datas Importantes

- **Criado**: 20 de Agosto de 2025
- **Expira**: 18 de Novembro de 2025  
- **Renovar até**: 28 de Outubro de 2025 (3 semanas antes)

## Configuração NGINX 🌐

O certificado wildcard funciona para todos os subdomínios:

```nginx
# Configuração no NGINX
ssl_certificate /etc/letsencrypt/live/samureye.com.br/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/samureye.com.br/privkey.pem;

# Válido para:
# ✅ app.samureye.com.br
# ✅ api.samureye.com.br  
# ✅ scanner.samureye.com.br
# ✅ qualquer.subdominio.samureye.com.br
```

## Monitoramento 📊

### Verificação Manual
```bash
# Status completo
sudo /opt/check-ssl-status.sh

# Verificar expiração
openssl x509 -in /etc/letsencrypt/live/samureye.com.br/fullchain.pem -noout -dates

# Testar conectividade
curl -I https://app.samureye.com.br
```

### Verificação Automática
- **Cron semanal**: Toda segunda-feira às 9h
- **Alerta**: 30 dias antes da expiração
- **Log**: `/var/log/messages` e `logger`

## Problemas Resolvidos ✅

### 1. Rate Limiting "Service busy"
- ✅ Verificação automática de rate limits
- ✅ Opção "DNS Manual Assistido" com staging
- ✅ Alertas preventivos

### 2. Múltiplos Desafios DNS
- ✅ Instruções claras sobre manter AMBOS registros TXT
- ✅ Processo em duas etapas (staging → produção)
- ✅ Verificação de propagação DNS

### 3. Renovação Manual
- ✅ Sistema de lembretes automático
- ✅ Scripts auxiliares instalados
- ✅ Documentação de troubleshooting

## Comandos Rápidos 🚀

```bash
# Verificar status
sudo /opt/check-ssl-status.sh

# Renovar certificado  
sudo ./setup-certificates.sh    # opção 7

# Verificar expiração
sudo /opt/renewal-reminder.sh

# Logs do Let's Encrypt
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Testar NGINX
sudo nginx -t && sudo systemctl reload nginx
```

## Próximos Passos 📋

1. **Configurar email de alertas** em `/opt/renewal-reminder.sh`
2. **Documentar processo** para equipe de operações
3. **Testar renovação** ~60 dias (meados de outubro)
4. **Considerar automação** com API DNS no futuro

## Suporte 🆘

- **Logs**: `/var/log/letsencrypt/letsencrypt.log`
- **Troubleshooting**: `TROUBLESHOOTING-CERTIFICATES.md`
- **Comunidade Let's Encrypt**: https://community.letsencrypt.org
- **Verificador DNS**: https://toolbox.googleapps.com/apps/dig/

---

**✅ Certificados SSL/TLS configurados com sucesso para SamurEye!**

*Última atualização: 20 de Agosto de 2025*