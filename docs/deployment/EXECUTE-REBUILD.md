# EXECUÇÃO IMEDIATA - CORRIGIR IMPORTS

## PROBLEMA ATUAL: Imports incorretos após rebuild

Execute ESTE comando no vlxsam02 para corrigir imports:

```bash
ssh root@192.168.100.152
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam02/fix-imports.sh | sudo bash
```

## Depois execute no vlxsam04:

```bash
ssh root@192.168.100.154  
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/fix-http-connection.sh | sudo bash
```

## SITUAÇÃO ATUAL

✅ vlxsam02: storage.ts reconstruído MAS imports incorretos  
✅ vlxsam01: NGINX funcionando  
✅ vlxsam03: Banco funcionando  
❌ vlxsam04: Aguardando aplicação vlxsam02

## PROBLEMA

Arquivos tentam `import { storage }` mas agora é `export default storage`

## SOLUÇÃO

O fix-imports.sh corrige todos os imports e cria shared/schema.ts necessário.