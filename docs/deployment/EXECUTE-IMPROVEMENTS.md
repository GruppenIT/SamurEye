# SamurEye Collectors - Comandos CORRIGIDOS de Implementação

## Scripts Corrigidos baseado na Situação Real dos Servidores

Execute os comandos abaixo na sequência para implementar todas as melhorias dos collectors:

### 🔐 PASSO 1: vlxsam01 - SSL/NGINX Corrigido

```bash
# Conectar na VM vlxsam01
ssh root@192.168.100.151

# Baixar e executar script corrigido
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/fix-ssl-nginx.sh | sudo bash
```

**Correções**: Detecta certificados em qualquer local, configura NGINX do zero, suporte HTTP/HTTPS

---

### 🗄️ PASSO 2: vlxsam03 - Banco Corrigido

```bash
# Conectar na VM vlxsam03
ssh root@192.168.100.153

# Baixar e executar script corrigido
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam03/fix-database-collectors.sh | sudo bash
```

**Correções**: Cria tabela collector_telemetry, detecta PostgreSQL corretamente, manutenção automática

---

### 🚀 PASSO 3: vlxsam02 - Aplicação Corrigida

```bash
# Conectar na VM vlxsam02
ssh root@192.168.100.152

# Baixar e executar script corrigido
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/fix-collector-improvements.sh | sudo bash
```

**Correções**: Adiciona endpoints de telemetria, storage atualizado, testes funcionais

---

### 🧪 PASSO 4: vlxsam04 - Collector Corrigido

```bash
# Conectar na VM vlxsam04
ssh root@192.168.100.154

# Baixar e executar script corrigido
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/fix-collector-config.sh | sudo bash
```

**Correções**: Recria configuração, agent atualizado, telemetria real, serviço systemd

---

## 🎯 Comando Deploy Unificado (Resultado Final)

Após implementar as melhorias, use este comando para instalar novos collectors:

```bash
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/install-collector.sh | sudo bash -s -- --tenant-slug="NOME-TENANT" --collector-name="NOME-COLLECTOR" --server-url="https://app.samureye.com.br"
```

### Exemplo prático:
```bash
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/install-collector.sh | sudo bash -s -- --tenant-slug="empresa-teste" --collector-name="servidor-web-01" --server-url="https://app.samureye.com.br"
```

---

## ✅ Verificação das Melhorias

Após executar todos os scripts, verifique:

1. **Interface Web**: https://app.samureye.com.br/collectors
   - Status 'online' do collector vlxsam04
   - Telemetria real (CPU, memória, disco)

2. **Teste Offline**:
   ```bash
   # No vlxsam04
   systemctl stop samureye-collector
   # Aguardar 5-6 minutos, interface deve mostrar 'offline'
   systemctl start samureye-collector
   ```

3. **Botões Funcionais**:
   - "Update Packages" com alerta
   - "Copiar Comando Deploy" funcional

---

## 📋 Funcionalidades Implementadas

✓ **Detecção Offline Automática**: Timeout de 5 minutos baseado em heartbeat  
✓ **Telemetria Real**: CPU, memória, disco vindos do collector  
✓ **Update Packages**: Botão funcional com alertas sobre jobs  
✓ **Deploy Unificado**: Comando copy-paste para instalar + registrar  
✓ **Interface Atualizada**: Dados reais do collector vlxsam04  

---

## 🔧 Resolução de Problemas

### Se a interface não carrega collectors:
```bash
# No vlxsam02
journalctl -u samureye-app -f
curl http://localhost:5000/api/collectors
```

### Se collector não aparece online:
```bash
# No vlxsam04
journalctl -u samureye-collector -f
curl https://app.samureye.com.br/api/system/settings
```

### Se telemetria não aparece:
```bash
# No vlxsam03
sudo -u postgres psql samureye -c "SELECT * FROM collector_telemetry ORDER BY timestamp DESC LIMIT 5;"
```