# EXECUÇÃO IMEDIATA - REBUILD STORAGE

## Comando para Resolver storage.ts Corrompido

Execute ESTE comando no vlxsam02:

```bash
ssh root@192.168.100.152
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/rebuild-storage.sh | sudo bash
```

## Depois execute no vlxsam04:

```bash
ssh root@192.168.100.154  
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/fix-http-connection.sh | sudo bash
```

## SITUAÇÃO ATUAL

❌ vlxsam02: storage.ts COMPLETAMENTE CORROMPIDO - 39 erros TypeScript
✅ vlxsam01: NGINX funcionando
✅ vlxsam03: Banco funcionando  
✅ vlxsam04: Aguardando aplicação vlxsam02

## SOLUÇÃO

O rebuild-storage.sh reconstrói o arquivo storage.ts inteiro do zero com todos os métodos necessários.