# Configuração vlxsam01 - Proxy NGINX 

## 📋 Visão Geral

O **vlxsam01** funciona como proxy reverso NGINX, roteando tráfego HTTPS para o backend vlxsam02:5000.

**Arquitetura:**
```
Usuário (172.16.10.50) 
    ↓ DNS interno
172.24.1.151 (vlxsam01) 
    ↓ NGINX proxy
172.24.1.152:5000 (vlxsam02)
    ↓ PostgreSQL
172.24.1.153:5432 (vlxsam03)
```

## 🌐 Domínios Configurados

Todos os domínios resolvem internamente para **172.24.1.151** (vlxsam01):
- `app.samureye.com.br` - Aplicação principal
- `api.samureye.com.br` - API endpoints  
- `ca.samureye.com.br` - Certificate Authority

## 🔒 Certificados TLS

- **Let's Encrypt** com certificados válidos
- **HTTPS obrigatório** com redirect automático do HTTP
- **HSTS** habilitado para segurança

## ⚠️ PROBLEMA IDENTIFICADO: Página em Branco no HTTPS

### Sintomas:
- ✅ `https://app.samureye.com.br` - Certificado válido, mas **página em branco**
- ✅ `http://172.24.1.152:5000` - Funciona normalmente (acesso direto)
- ✅ Certificados Let's Encrypt carregando corretamente

### Causa Provável:
Configuração nginx com problemas de proxy, headers ou buffering.

## 🚀 Soluções Automatizadas

### 1. Diagnóstico Rápido
```bash
# No vlxsam01:
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam01/diagnose-nginx.sh | sudo bash
```
**Uso:** Identifica problemas de configuração nginx

### 2. Correção Completa (RECOMENDADO)
```bash
# No vlxsam01:
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam01/fix-nginx-proxy.sh | sudo bash
```
**Uso:** Corrige configuração nginx com otimizações de proxy

### 3. Correção Rápida (Mínima)
```bash
# No vlxsam01:
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam01/quick-fix-nginx.sh | sudo bash
```
**Uso:** Aplica configuração mínima funcional

## 🔧 Correção Manual

Se os scripts automáticos falharem:

### 1. Verificar Status dos Serviços
```bash
# Status nginx
systemctl status nginx

# Teste configuração
nginx -t

# Logs
tail -f /var/log/nginx/error.log
```

### 2. Verificar Conectividade Backend
```bash
# Teste direto vlxsam02
curl -I http://172.24.1.152:5000/api/system/settings

# Teste interno vlxsam01
curl -I -k https://127.0.0.1/
```

### 3. Configuração Mínima Manual
```bash
# Backup atual
cp -r /etc/nginx/sites-enabled /root/nginx-backup

# Criar configuração básica
cat > /etc/nginx/sites-available/samureye.conf << 'EOF'
upstream backend {
    server 172.24.1.152:5000;
}

server {
    listen 80;
    server_name app.samureye.com.br api.samureye.com.br ca.samureye.com.br;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name app.samureye.com.br api.samureye.com.br ca.samureye.com.br;
    
    ssl_certificate /etc/letsencrypt/live/app.samureye.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.samureye.com.br/privkey.pem;
    
    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
    }
}
EOF

# Ativar configuração
rm -f /etc/nginx/sites-enabled/*
ln -s /etc/nginx/sites-available/samureye.conf /etc/nginx/sites-enabled/

# Testar e recarregar
nginx -t && systemctl reload nginx
```

## 🧪 Testes de Validação

### 1. Teste HTTPS Externo
```bash
# Da máquina Windows (172.16.10.50):
# Navegador: https://app.samureye.com.br
```

### 2. Teste HTTPS Interno  
```bash
# No vlxsam01:
curl -I -k https://127.0.0.1/
curl -s https://127.0.0.1/api/system/settings
```

### 3. Teste Backend Direto
```bash
# Qualquer máquina da rede:
curl -I http://172.24.1.152:5000/api/system/settings
```

## 📊 Status Esperado

Após a correção:
- ✅ `https://app.samureye.com.br` - Aplicação carregando normalmente
- ✅ Proxy nginx funcionando
- ✅ Headers corretos (X-Forwarded-Proto: https)
- ✅ WebSockets funcionando se necessário

## 🔍 Troubleshooting

### Logs Úteis:
```bash
# Logs nginx
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/access.log

# Teste configuração
nginx -t

# Status serviços
systemctl status nginx
```

### Problemas Comuns:

1. **Certificado não encontrado**
   - Verificar: `ls /etc/letsencrypt/live/`
   - Ajustar path no nginx

2. **Backend não responde**
   - Verificar: `systemctl status samureye-app` no vlxsam02
   - Testar: `curl http://172.24.1.152:5000/health`

3. **Headers incorretos**
   - Adicionar `proxy_set_header X-Forwarded-Proto $scheme`
   - Verificar `proxy_buffering off` se página em branco

4. **WebSocket problemas**
   - Adicionar suporte WebSocket no nginx
   - Headers `Upgrade` e `Connection`

## 🎯 Próximos Passos

1. **Execute script de correção** no vlxsam01
2. **Teste https://app.samureye.com.br** da máquina Windows
3. **Confirme que página não está mais em branco**
4. **Execute criação de tenant** para teste final

---

**Documentação atualizada em:** 27/08/2025  
**Status:** Problema identificado, soluções implementadas