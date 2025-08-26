# vlxsam02 - SamurEye Application Server

## Visão Geral
O vlxsam02 é o servidor principal da aplicação SamurEye, responsável por executar a interface web e API. Este servidor conecta-se ao banco PostgreSQL e Redis localizados no vlxsam03.

## Configuração de Rede
- **IP**: 172.24.1.152
- **Função**: Application Server (Frontend + API)
- **Porta**: 5000 (aplicação web)
- **Dependências**: vlxsam03 (PostgreSQL + Redis)

## Scripts Disponíveis

### 📦 Instalação Principal
```bash
sudo ./install.sh
```
**Descrição**: Script principal de instalação que configura toda a infraestrutura da aplicação.
**Características**:
- Instala Node.js 20 e dependências
- Baixa código fonte do GitHub
- Configura banco de dados
- Cria arquivo `.env` com configurações corretas
- Configura serviço systemd
- Detecta e corrige automaticamente problemas de porta 443

### 🔧 Scripts de Correção

#### Correção de Carregamento do .env
```bash
sudo ./fix-env-loading.sh
```
**Quando usar**: Quando a aplicação não está carregando as variáveis de ambiente corretamente.
**O que faz**:
- Recria arquivo `.env` com configuração correta
- Recria links simbólicos
- Verifica configuração dotenv no código
- Testa carregamento de variáveis
- Reinicia serviço

#### Correção de Porta 443
```bash
sudo ./fix-port-443-issue.sh
```
**Quando usar**: Quando aparecem erros de conexão `ECONNREFUSED 172.24.1.153:443` nos logs.
**O que faz**:
- Procura e corrige configurações hardcoded incorretas
- Substitui `:443` por `:5432` em arquivos de código
- Corrige URLs HTTPS que deveriam ser PostgreSQL
- Verifica configuração dotenv
- Testa e valida correções

### 🔍 Scripts de Diagnóstico

#### Diagnóstico de Conexão
```bash
sudo ./diagnose-connection.sh
```
**Descrição**: Análise detalhada para identificar problemas de conectividade.
**Verifica**:
- Estrutura de arquivos e diretórios
- Configuração do arquivo `.env`
- Links simbólicos
- Configurações hardcoded no código
- Configuração do servidor
- Status do serviço e logs

#### Teste de Instalação
```bash
sudo ./test-installation.sh
```
**Descrição**: Teste completo da instalação e funcionalidade.
**Testa**:
- Conectividade com PostgreSQL (vlxsam03:5432)
- Conectividade com Redis (vlxsam03:6379)
- Estrutura da aplicação
- Configuração `.env`
- Serviço systemd
- API endpoints
- Análise de logs

## Problema Comum: Porta 443

### Sintomas
```
Error: connect ECONNREFUSED 172.24.1.153:443
```

### Causa
A aplicação está tentando conectar via HTTPS (porta 443) em vez de PostgreSQL (porta 5432) devido a:
1. Configurações hardcoded incorretas no código
2. Arquivo `.env` não sendo carregado corretamente
3. Variáveis de ambiente incorretas

### Solução Rápida
```bash
# 1. Diagnosticar problema
sudo ./diagnose-connection.sh

# 2. Corrigir carregamento do .env
sudo ./fix-env-loading.sh

# 3. Corrigir configurações hardcoded (se necessário)
sudo ./fix-port-443-issue.sh

# 4. Verificar se foi resolvido
sudo ./test-installation.sh
```

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
```

## Configuração Principal (.env)

### Variáveis Críticas
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
```

### ⚠️ Configuração Incorreta (Evitar)
```bash
# NUNCA usar porta 443 para PostgreSQL:
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:443/samureye_prod  # ❌ ERRADO
```

## Monitoramento

### Verificar Status do Serviço
```bash
systemctl status samureye-app
```

### Logs em Tempo Real
```bash
journalctl -u samureye-app -f
```

### Verificar Conectividade
```bash
# PostgreSQL
nc -zv 172.24.1.153 5432

# Redis
nc -zv 172.24.1.153 6379

# API Local
curl http://localhost:5000/api/health
```

### Verificar Processos
```bash
ps aux | grep tsx
```

## Solução de Problemas Comuns

### 1. Serviço não inicia
```bash
# Verificar logs de erro
journalctl -u samureye-app --no-pager -l

# Executar correção
sudo ./fix-env-loading.sh
```

### 2. Erro de conexão banco
```bash
# Testar conectividade manual
PGPASSWORD=SamurEye2024! psql -h 172.24.1.153 -p 5432 -U samureye -d samureye_prod

# Se falhar, verificar se PostgreSQL está rodando em vlxsam03
```

### 3. Erro porta 443
```bash
# Diagnóstico específico
sudo ./diagnose-connection.sh

# Correção específica
sudo ./fix-port-443-issue.sh
```

### 4. API não responde
```bash
# Verificar se serviço está ativo
systemctl is-active samureye-app

# Verificar se porta está em uso
netstat -tlnp | grep :5000

# Testar endpoint
curl -v http://localhost:5000/api/health
```

## Comandos de Manutenção

### Reiniciar Aplicação
```bash
sudo systemctl restart samureye-app
```

### Atualizar Código (Git Pull)
```bash
cd /opt/samureye/SamurEye
sudo -u samureye git pull origin main
sudo systemctl restart samureye-app
```

### Limpar Logs
```bash
sudo journalctl --vacuum-time=7d
```

### Verificar Recursos
```bash
# Memória
free -h

# Disco
df -h

# CPU
top
```

## Integração com vlxsam03

### Dependências
- **PostgreSQL**: 172.24.1.153:5432
- **Redis**: 172.24.1.153:6379
- **MinIO**: 172.24.1.153:9000

### Teste de Conectividade
```bash
# Teste automático completo
sudo ./test-installation.sh

# Teste manual específico
timeout 5 bash -c "</dev/tcp/172.24.1.153/5432" && echo "PostgreSQL OK"
timeout 5 bash -c "</dev/tcp/172.24.1.153/6379" && echo "Redis OK"
```

## Contato e Suporte

Para problemas não resolvidos pelos scripts automáticos:
1. Execute `./diagnose-connection.sh` e envie a saída
2. Colete logs com `journalctl -u samureye-app --since "1 hour ago"`
3. Verifique conectividade de rede com vlxsam03