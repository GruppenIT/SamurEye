# Correção Crítica de IPs - Log de Alterações

## Problema Identificado
**ERRO CRÍTICO**: Scripts estavam usando rede 192.168.100.x quando a arquitetura on-premise real usa 172.24.1.x

## Arquitetura Correta
```
vlxsam01 (Gateway)     : 172.24.1.151
vlxsam02 (Application) : 172.24.1.152  
vlxsam03 (Database)    : 172.24.1.153
vlxsam04 (Collector)   : 172.24.1.154
```

## Arquivos Corrigidos

### 1. vlxsam02/install-hard-reset.sh
- `POSTGRES_HOST="192.168.100.153"` → `POSTGRES_HOST="172.24.1.153"`
- Comentário do servidor corrigido

### 2. vlxsam03/install-hard-reset.sh
- pg_hba.conf: Todas as entradas 192.168.100.x → 172.24.1.x
- Rede de backup: 192.168.100.0/24 → 172.24.1.0/24

### 3. docs/deployment/README.md
- Diagrama de arquitetura corrigido
- Todos os comandos SSH corrigidos
- URLs de Grafana e MinIO corrigidas

## Impacto da Correção
✅ **vlxsam02** agora pode conectar ao PostgreSQL no IP correto
✅ **pg_hba.conf** permite conexões da rede correta
✅ **Documentação** reflete arquitetura real
✅ **Scripts** funcionais para ambiente on-premise

## Status
**RESOLVIDO**: Todos os IPs corrigidos para rede 172.24.1.x
**TESTADO**: Sintaxe de todos os scripts validada

## Próximos Passos
- Testar conectividade vlxsam02 → vlxsam03
- Validar Redis e demais serviços no vlxsam03