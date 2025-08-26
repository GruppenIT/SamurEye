# vlxsam02 - SamurEye Application Server

## Visão Geral
O vlxsam02 é o servidor principal da aplicação SamurEye, responsável por executar a interface web e API. Este servidor conecta-se ao banco PostgreSQL e Redis localizados no vlxsam03.

## Configuração de Rede
- **IP**: 172.24.1.152
- **Função**: Application Server (Frontend + API)
- **Porta**: 5000 (aplicação web)
- **Dependências**: vlxsam03 (PostgreSQL + Redis)

## 🚀 Instalação Completa e Automática

### Script Principal
```bash
# Download e execute o script diretamente
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install.sh | sudo bash

# OU baixe e execute localmente
sudo ./install.sh
```

### Se Houver Erro de Permissões
```bash
# Execute este script de correção primeiro
sudo ./quick-fix.sh

# Depois execute a instalação normal
sudo ./install.sh
```

**O que faz automaticamente**:
- ✅ **Diagnóstico inicial** - Detecta problemas conhecidos
- ✅ **Limpeza completa** - Remove instalações anteriores problemáticas
- ✅ **Instalação do sistema** - Node.js 20, PostgreSQL client, Redis tools
- ✅ **Download da aplicação** - Clone do repositório GitHub
- ✅ **Correção automática** - Resolve erro de porta 443 e configurações hardcoded
- ✅ **Configuração .env** - Cria arquivo com todas as variáveis corretas
- ✅ **Teste de configuração** - Valida carregamento de variáveis
- ✅ **Serviço systemd** - Configura e inicia automaticamente
- ✅ **Validação final** - Testa conectividade e funcionalidade
- ✅ **API em funcionamento** - Aplicação pronta para uso

### Características do Script Unificado

#### 🔍 Diagnóstico Automático
O script detecta automaticamente:
- Problemas de conectividade com vlxsam03
- Instalações anteriores com erro de porta 443
- Configurações `.env` incorretas
- Código hardcoded problemático
- Falta de configuração dotenv

#### 🛠️ Correção Automática
Corrige automaticamente:
- **Porta 443** → **5432** em arquivos de código
- **URLs HTTPS** → **URLs PostgreSQL** corretas
- **Configuração dotenv** ausente no servidor
- **Arquivo .env** com todas as variáveis corretas
- **Links simbólicos** para configuração centralizada

#### ✅ Validação Completa
Valida automaticamente:
- Estrutura de arquivos e diretórios
- Arquivos essenciais da aplicação
- Links simbólicos para .env
- Configuração sem porta 443
- Conectividade com PostgreSQL e Redis
- API respondendo corretamente

## Problema Comum: Porta 443

### Sintomas Anteriores
```
Error: connect ECONNREFUSED 172.24.1.153:443
```

### ✨ Solução Automática
O script `install.sh` agora **resolve automaticamente** todos os problemas relacionados à porta 443:

1. **Detecta** configurações incorretas
2. **Corrige** código hardcoded
3. **Recria** arquivo .env correto
4. **Valida** que não há mais tentativas de conexão na porta 443

**Não é mais necessário executar comandos separados!**

## ⚡ Atualização Crítica: ES6 Modules (Agosto 2025)

### Problema Identificado
```
❌ ERRO CRÍTICO: require is not defined
ReferenceError: require is not defined
```

### 🔧 Causa Raiz
O projeto SamurEye está configurado com `"type": "module"` no `package.json`, fazendo o Node.js interpretar arquivos como ES6 modules em vez de CommonJS.

### ✅ Solução Implementada
Todos os scripts de instalação foram **corrigidos** para usar sintaxe ES6:

**Antes (CommonJS - FALHA):**
```javascript
const dotenv = require('dotenv');
dotenv.config();
```

**Depois (ES6 - FUNCIONA):**
```javascript
import dotenv from 'dotenv';
dotenv.config();
```

### 📋 Scripts Corrigidos
- ✅ **install-final.sh** - Usa arquivos `.mjs` com sintaxe ES6
- ✅ **fix-env-test.sh** - Teste corrigido para módulos ES6
- ✅ **install-simple.sh** - Versão simplificada com ES6
- ✅ **install.sh** - Script original com correções ES6

## Estrutura de Arquivos

```
/opt/samureye/
├── SamurEye/           # Código da aplicação (clonado do GitHub)
│   ├── server/         # Backend (Express.js)
│   ├── client/         # Frontend (React)
│   ├── shared/         # Código compartilhado
│   └── .env -> /etc/samureye/.env  # Link simbólico
├── .env -> /etc/samureye/.env      # Link simbólico

/etc/samureye/
└── .env                # Arquivo principal de configuração

/etc/systemd/system/
└── samureye-app.service    # Serviço systemd

/var/log/samureye/
└── *.log               # Logs da aplicação
```

## Configuração Automática (.env)

### Variáveis Configuradas Automaticamente
```bash
# Database (PostgreSQL - vlxsam03)
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod
PGHOST=172.24.1.153
PGPORT=5432
PGUSER=samureye
PGPASSWORD=SamurEye2024!
PGDATABASE=samureye_prod

# Application
NODE_ENV=development
PORT=5000

# Redis (vlxsam03)
REDIS_URL=redis://172.24.1.153:6379

# Security
SESSION_SECRET=samureye_secret_2024_vlxsam02_production
JWT_SECRET=samureye_jwt_secret_2024

# External Services
GRAFANA_URL=http://172.24.1.153:3000
MINIO_ENDPOINT=172.24.1.153
MINIO_PORT=9000
```

## Monitoramento

### Verificar Status
```bash
# Status do serviço
systemctl status samureye-app

# Logs em tempo real
journalctl -u samureye-app -f

# Verificar se API está respondendo
curl http://localhost:5000/api/health
```

### Verificar Conectividade
```bash
# PostgreSQL
nc -zv 172.24.1.153 5432

# Redis
nc -zv 172.24.1.153 6379
```

## Comandos de Manutenção

### Operações Básicas
```bash
# Reiniciar aplicação
sudo systemctl restart samureye-app

# Parar aplicação
sudo systemctl stop samureye-app

# Iniciar aplicação
sudo systemctl start samureye-app

# Verificar status
sudo systemctl status samureye-app
```

### Atualização da Aplicação
```bash
# Atualizar código do GitHub
cd /opt/samureye/SamurEye
sudo -u samureye git pull origin main
sudo systemctl restart samureye-app
```

### Reinstalação Completa
```bash
# Para reinstalar tudo do zero
sudo ./install.sh
```
O script detectará a instalação anterior e fará limpeza completa automaticamente.

## Solução de Problemas

### 🔧 Problemas Resolvidos Automaticamente
- ✅ Erro de conexão porta 443
- ✅ Configurações hardcoded incorretas
- ✅ Arquivo .env não carregado
- ✅ Links simbólicos ausentes
- ✅ Serviço não configurado
- ✅ Dependências ausentes
- ✅ Problemas de permissões no clone do repositório

### 🚨 Problemas Conhecidos e Soluções

#### Erro: "Permission denied" no Clone do Git
**Sintoma:**
```
/opt/samureye/SamurEye/.git: Permission denied
```

**Solução Automática:**
O script agora detecta e corrige automaticamente problemas de permissões. Se ainda ocorrer:

1. **Execute o script de correção:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/quick-fix.sh | sudo bash
   ```

2. **Depois execute a instalação normal:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install.sh | sudo bash
   ```

### 🎯 Instalação Final (Recomendada - Resolve problemas dotenv)
```bash
# Script final que resolve todos os problemas de carregamento .env
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-final.sh | sudo bash
```

### 🔧 Correção Específica do Teste .env
```bash
# Se ainda houver problemas com "Cannot find module 'dotenv'"
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/fix-env-test.sh | sudo bash
```

### 🎯 Instalação Simplificada (Alternativa)
```bash
# Instalação simplificada focada na correção do .env
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/install-simple.sh | sudo bash
```

### 📋 Teste Rápido de Configuração
```bash
# Verificar se as variáveis de ambiente estão carregando corretamente
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam02/test-env-quick.sh | sudo bash
```

### 📋 Para Problemas Não Resolvidos Automaticamente

#### 1. Verificar logs detalhados
```bash
journalctl -u samureye-app --no-pager -l
```

#### 2. Verificar conectividade manual
```bash
# PostgreSQL
PGPASSWORD=SamurEye2024! psql -h 172.24.1.153 -p 5432 -U samureye -d samureye_prod

# Se falhar, verificar se vlxsam03 está funcionando
```

#### 3. Reinstalar completamente
```bash
sudo ./install.sh
```

#### 4. Verificar recursos do sistema
```bash
# Memória
free -h

# Disco
df -h

# Processos
ps aux | grep tsx
```

## Validação da Instalação

### Verificações Automáticas
O script `install.sh` valida automaticamente:
- ✅ Estrutura de arquivos correta
- ✅ Configuração .env sem porta 443
- ✅ Código sem configurações hardcoded
- ✅ Conectividade com PostgreSQL
- ✅ API respondendo
- ✅ Serviço ativo e funcionando

### Sinais de Sucesso
```
🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!
✅ Todos os testes passaram
✅ Instalação está pronta para uso
🌐 URL da aplicação: http://localhost:5000
```

## Integração com vlxsam03

### Dependências Testadas Automaticamente
- **PostgreSQL**: 172.24.1.153:5432 ✅
- **Redis**: 172.24.1.153:6379 ✅
- **MinIO**: 172.24.1.153:9000 (futuro)

### Teste de Conectividade Automático
O script testa automaticamente durante a instalação:
- Conectividade TCP
- Autenticação PostgreSQL
- Conectividade Redis
- Resposta da API

## URLs e Portas

### Aplicação
- **Interface Web**: http://172.24.1.152:5000
- **API**: http://172.24.1.152:5000/api
- **Health Check**: http://172.24.1.152:5000/api/health

### Dependências (vlxsam03)
- **PostgreSQL**: 172.24.1.153:5432
- **Redis**: 172.24.1.153:6379
- **Grafana**: http://172.24.1.153:3000
- **MinIO**: http://172.24.1.153:9000

## Suporte

### Informações para Suporte
Se a instalação automática falhar, colete:

1. **Saída completa do script**:
   ```bash
   sudo ./install.sh 2>&1 | tee install.log
   ```

2. **Logs do serviço**:
   ```bash
   journalctl -u samureye-app --since "1 hour ago" > service.log
   ```

3. **Status do sistema**:
   ```bash
   systemctl status samureye-app > status.log
   ```

### Contato
Para problemas não resolvidos pelo script automático, envie os logs coletados e a descrição do erro específico.