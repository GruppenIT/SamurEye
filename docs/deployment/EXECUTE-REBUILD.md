# EXECUÇÃO IMEDIATA - CONECTAR COLLECTOR

## SITUAÇÃO ATUAL: Backend vlxsam02 funcionando

✅ vlxsam02: Backend funcionando corretamente em http://localhost:5000  
✅ vlxsam01: NGINX proxy funcionando  
✅ vlxsam03: Banco funcionando  
🔄 vlxsam04: AGORA conectar collector via HTTP

## PRÓXIMO COMANDO

Execute no vlxsam04 para conectar collector:

```bash
ssh root@192.168.100.154  
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/fix-http-connection.sh | sudo bash
```

## APIs FUNCIONAIS

- http://192.168.100.152:5000/collector-api/health
- http://192.168.100.152:5000/collector-api/heartbeat
- http://192.168.100.152:5000/api/admin/collectors

Sistema pronto para receber collectors!