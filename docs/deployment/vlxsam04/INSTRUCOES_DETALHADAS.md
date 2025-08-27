# vlxsam04 - Instruções Detalhadas de Instalação e Configuração

## 🚨 PROBLEMA IDENTIFICADO: Script GitHub Desatualizado

O erro que você está enfrentando:
```
E: Unable to locate package python3.11
E: Package 'netcat' has no installation candidate
```

**CAUSA**: O script no GitHub ainda tem as versões antigas (Python 3.11, netcat).
**SOLUÇÃO**: Use o script local que já foi corrigido para Ubuntu 24.04.

## ✅ SOLUÇÃO IMEDIATA

### 1. NÃO USE o comando GitHub:
```bash
# ❌ NÃO FUNCIONA - Script desatualizado
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/install.sh | bash
```

### 2. USE o script local corrigido:
```bash
# ✅ FUNCIONA - Script atualizado para Ubuntu 24.04
cd /path/to/SamurEye
sudo bash docs/deployment/vlxsam04/install.sh
```

## 📋 Passo a Passo Completo

### Preparação
```bash
# 1. Fazer login no vlxsam04
ssh root@vlxsam04

# 2. Verificar Ubuntu
lsb_release -a
# Deve ser Ubuntu 24.04 LTS (Noble)

# 3. Baixar projeto SamurEye
git clone https://github.com/GruppenIT/SamurEye.git
cd SamurEye
```

### Instalação
```bash
# 4. Executar script local atualizado
sudo bash docs/deployment/vlxsam04/install.sh
```

**O script irá automaticamente:**
- ✅ Instalar Python 3.12 (não 3.11)
- ✅ Instalar netcat-openbsd (não netcat)
- ✅ Configurar todas as dependências
- ✅ Criar estrutura de diretórios
- ✅ Instalar ferramentas de segurança
- ✅ Criar scripts auxiliares
- ✅ Validar compatibilidade Ubuntu 24.04
- ✅ Gerar log de compatibilidade
- ✅ Configurar automaticamente .env base

## 🤖 Automação Incluída

### Configuração Automática (.env)
O script cria automaticamente `/etc/samureye-collector/.env` com:
```bash
COLLECTOR_ID=vlxsam04
COLLECTOR_HOST=192.168.100.151
STEP_CA_URL=https://ca.samureye.com.br
SAMUREYE_API_URL=https://api.samureye.com.br
```

### Scripts Auxiliares Criados
- `/opt/samureye-collector/scripts/auto-configure.sh` - Configuração automática
- `/opt/samureye-collector/scripts/setup-step-ca.sh` - Configuração certificados
- `/opt/samureye-collector/scripts/health-check.sh` - Verificação de saúde
- `/opt/samureye-collector/scripts/test-mtls-connection.sh` - Teste conexão

### Validações Automáticas
- ✅ Teste de importações Python críticas
- ✅ Verificação de ferramentas de segurança
- ✅ Teste de conectividade com CA
- ✅ Validação de versões Ubuntu 24.04

## 🎯 Próximos Passos Após Instalação

### 1. Obter CA Fingerprint
```bash
# No servidor vlxsam01 (Certificate Authority):
step ca fingerprint https://ca.samureye.com.br

# Resultado será algo como:
# SHA256:abc123def456... (use este valor)
```

### 2. Atualizar Configuração
```bash
# No vlxsam04:
sudo nano /etc/samureye-collector/.env

# Adicionar o fingerprint:
STEP_CA_FINGERPRINT=abc123def456...
```

### 3. Registrar Collector na Interface Web
```bash
# 1. Acessar: https://app.samureye.com.br/admin
# 2. Login como admin
# 3. Menu: Collectors → Add New Collector
# 4. Preencher:
#    - Name: vlxsam04
#    - Host: 192.168.100.151  
#    - Type: Security Collector
# 5. Copiar o registration token gerado
```

### 4. Atualizar Token no Collector
```bash
sudo nano /etc/samureye-collector/.env

# Adicionar token:
REGISTRATION_TOKEN=eyJ0eXAiOiJKV1QiLCJhbGc...
```

### 5. Configurar Certificados step-ca
```bash
sudo /opt/samureye-collector/scripts/setup-step-ca.sh
```

### 6. Ativar Serviços
```bash
sudo systemctl enable samureye-collector samureye-telemetry
sudo systemctl start samureye-collector samureye-telemetry
```

### 7. Verificar Status
```bash
sudo systemctl status samureye-collector
sudo /opt/samureye-collector/scripts/health-check.sh
```

## 🔍 Verificações de Funcionamento

### Logs em Tempo Real
```bash
sudo tail -f /var/log/samureye-collector/collector.log
```

### Status dos Serviços
```bash
sudo systemctl status samureye-collector samureye-telemetry
```

### Teste de Conectividade
```bash
sudo /opt/samureye-collector/scripts/test-mtls-connection.sh
```

### Teste das Ferramentas
```bash
# Nmap
sudo -u samureye-collector nmap -sV localhost

# Nuclei  
sudo -u samureye-collector nuclei -version

# Masscan
sudo -u samureye-collector masscan --version
```

## 📊 Monitoramento Contínuo

### Health Check Automático
```bash
# Executar a cada 5 minutos via cron
echo "*/5 * * * * root /opt/samureye-collector/scripts/health-check.sh" >> /etc/crontab
```

### Logs de Compatibilidade
```bash
# Verificar se Ubuntu 24.04 está funcionando corretamente
cat /var/log/samureye-collector/ubuntu-24-04-compatibility.log
```

### Métricas de Sistema
```bash
# CPU e RAM do collector
sudo ps aux | grep samureye

# Espaço em disco
sudo df -h /opt/samureye-collector
```

## 🚨 Troubleshooting Comum

### Problema: Falha na Instalação
```bash
# Verifique se está usando script local:
sudo bash docs/deployment/vlxsam04/install.sh  # ✅ Correto
```

### Problema: Certificados step-ca
```bash
# Reconfigurar certificados
sudo rm -rf /opt/samureye-collector/certs/*
sudo /opt/samureye-collector/scripts/setup-step-ca.sh --force
```

### Problema: Conectividade
```bash
# Testar conectividade básica
curl -k https://ca.samureye.com.br/health
curl -k https://api.samureye.com.br/health
```

### Problema: Permissões
```bash
# Corrigir permissões
sudo chown -R samureye-collector:samureye-collector /opt/samureye-collector
sudo chmod 700 /opt/samureye-collector/certs
```

## 📋 Checklist de Finalização

- [ ] ✅ Script instalado sem erros (Python 3.12, netcat-openbsd)
- [ ] ✅ CA fingerprint configurado no .env
- [ ] ✅ Collector registrado na interface web  
- [ ] ✅ Registration token atualizado no .env
- [ ] ✅ Certificados step-ca configurados
- [ ] ✅ Serviços iniciados e funcionando
- [ ] ✅ Health check passing
- [ ] ✅ Conectividade mTLS funcionando
- [ ] ✅ Ferramentas de segurança testadas

## 🎉 Resultado Final Esperado

Quando tudo estiver funcionando, você deve ver:

```bash
$ sudo systemctl status samureye-collector
● samureye-collector.service - SamurEye Collector Agent
   Loaded: loaded (/etc/systemd/system/samureye-collector.service; enabled)
   Active: active (running) since ...
   
$ sudo /opt/samureye-collector/scripts/health-check.sh
✅ Collector Agent: Running
✅ mTLS Connection: OK  
✅ Step-CA: Connected
✅ Tools: All Available
✅ Multi-tenant: Ready
```

**Sistema totalmente operacional e pronto para receber comandos de security testing!**