# RESTAURAR APLICAÇÃO COMPLETA COM MELHORIAS

## SITUAÇÃO ATUAL
- Interface React foi perdida durante correções
- Backend funcionando apenas com JSON
- Precisa restaurar interface completa + melhorias

## EXECUÇÃO SEQUENCIAL

### 1. RESTAURAR APLICAÇÃO COMPLETA (vlxsam02)

```bash
ssh root@192.168.100.152
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/restore-full-app.sh | sudo bash
```

**Resultado**: Interface React completa + Backend integrado + Melhorias

### 2. RESTAURAR NGINX PROXY (vlxsam01)

```bash
ssh root@192.168.100.151
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/restore-nginx-proxy.sh | sudo bash
```

**Resultado**: Proxy correto para aplicação completa

### 3. CONECTAR COLLECTOR COM TELEMETRIA REAL (vlxsam04)

```bash
ssh root@192.168.100.154
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/connect-with-improvements.sh | sudo bash
```

**Resultado**: Telemetria real (CPU, RAM, Disk) + Detecção offline

## MELHORIAS IMPLEMENTADAS

✅ **Detecção offline automática** (timeout 5min)  
✅ **Telemetria real** de CPU, memória, disco do collector  
✅ **Botão "Update Packages"** funcional com alertas  
✅ **Comando Deploy** unificado copy-paste  

## URLS FINAIS

- **Interface completa**: http://app.samureye.com.br
- **Gestão collectors**: http://app.samureye.com.br/collectors  
- **APIs**: http://app.samureye.com.br/api/*

## ORDEM DE EXECUÇÃO

1. vlxsam02 (restaurar app completa)
2. vlxsam01 (restaurar proxy)  
3. vlxsam04 (conectar com telemetria)

**Tempo total**: ~10-15 minutos