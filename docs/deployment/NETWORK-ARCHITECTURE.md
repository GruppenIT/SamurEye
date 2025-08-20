# SamurEye - Arquitetura de Rede

## Mapeamento de IPs e Conectividade

### Servidores e IPs

| Servidor | IP | Função | Conectividade |
|----------|----|---------|--------------| 
| vlxsam01 | 172.24.1.151 | Gateway/Proxy | Recebe tráfego externo, encaminha para vlxsam02 |
| vlxsam02 | 172.24.1.152 | App/API/Scanner | Conecta com vlxsam03 para banco de dados |
| vlxsam03 | 172.24.1.153 | Database/Redis/MinIO | Recebe conexões de vlxsam02 |
| vlxsam04 | 192.168.100.151 | Collector | **Apenas outbound** para vlxsam02 |

### Fluxo de Comunicação

```
Internet
    ↓
vlxsam01 (172.24.1.151) - Gateway NGINX
    ↓ (proxy_pass)
vlxsam02 (172.24.1.152) - Application Server
    ↓ (database connections)
vlxsam03 (172.24.1.153) - Database Server

vlxsam04 (192.168.100.151) - Collector
    ↗ (outbound HTTPS only)
vlxsam02 (172.24.1.152)
```

### Portas e Protocolos

#### vlxsam01 (Gateway)
- **80/tcp**: HTTP (redireciona para HTTPS)
- **443/tcp**: HTTPS (público)
- **22/tcp**: SSH (admin)

#### vlxsam02 (Application)
- **3000/tcp**: App principal (interno)
- **3001/tcp**: Scanner service (interno)
- **22/tcp**: SSH (admin)

#### vlxsam03 (Database)
- **5432/tcp**: PostgreSQL (interno)
- **6379/tcp**: Redis (interno)
- **9000/tcp**: MinIO API (interno)
- **9001/tcp**: MinIO Console (interno)
- **514/udp**: Syslog centralizado (interno)
- **22/tcp**: SSH (admin)

#### vlxsam04 (Collector)
- **22/tcp**: SSH (admin)
- **443/tcp**: HTTPS outbound para vlxsam02

### Regras de Firewall

#### vlxsam01 (Gateway)
```bash
# Entrada
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS

# Saída
ufw allow out 3000,3001/tcp to 172.24.1.152  # Para vlxsam02
```

#### vlxsam02 (Application)
```bash
# Entrada
ufw allow 22/tcp                              # SSH
ufw allow from 172.24.1.151 to any port 3000 # Do Gateway
ufw allow from 172.24.1.151 to any port 3001 # Do Gateway
ufw allow 443/tcp                             # Para collectors

# Saída
ufw allow out 5432/tcp to 172.24.1.153       # PostgreSQL
ufw allow out 6379/tcp to 172.24.1.153       # Redis
ufw allow out 9000/tcp to 172.24.1.153       # MinIO
```

#### vlxsam03 (Database)
```bash
# Entrada
ufw allow 22/tcp                              # SSH
ufw allow from 172.24.1.152 to any port 5432 # PostgreSQL
ufw allow from 172.24.1.152 to any port 6379 # Redis
ufw allow from 172.24.1.152 to any port 9000 # MinIO
ufw allow 514/udp                             # Syslog
```

#### vlxsam04 (Collector)
```bash
# Entrada
ufw allow 22/tcp    # SSH apenas

# Saída
ufw allow out 443/tcp to 172.24.1.152  # API outbound
ufw allow out 53                       # DNS
ufw allow out 80,443                   # Updates
```

### Importante: Comunicação do Collector

**⚠️ ATENÇÃO**: O vlxsam04 (Collector) **NÃO recebe** conexões da aplicação. A comunicação é sempre **outbound**:

1. **Enrollment**: Collector faz POST para `/api/collectors/enroll`
2. **Heartbeat**: Collector faz POST para `/api/collectors/{id}/heartbeat`
3. **Telemetria**: Collector faz POST para `/api/collectors/{id}/telemetry`
4. **WebSocket**: Collector conecta em `wss://app.samureye.com.br/ws`
5. **Resultados**: Collector faz POST para `/api/journeys/{id}/result`

### Configuração de Domínios

```
app.samureye.com.br      → 172.24.1.151 (Gateway)
api.samureye.com.br      → 172.24.1.151 (Gateway → vlxsam02)
scanner.samureye.com.br  → 172.24.1.151 (Gateway → vlxsam02:3001)
```

### Monitoramento de Conectividade

#### Scripts de Teste
```bash
# Em vlxsam02: Testar conexão com banco
nc -zv 172.24.1.153 5432
nc -zv 172.24.1.153 6379

# Em vlxsam04: Testar API
curl -I https://api.samureye.com.br/health

# Em vlxsam01: Testar proxy
curl -I http://172.24.1.152:3000/api/health
```

### Load Balancing (Futuro)

Para alta disponibilidade, pode-se configurar:

```
               Internet
                  ↓
            Load Balancer
           ↓              ↓
    vlxsam01a        vlxsam01b
           ↓              ↓
            vlxsam02 (shared)
                  ↓
      vlxsam03 (master/replica)
```

### Backup e DR

- **vlxsam03**: Backups automáticos para storage remoto
- **Collectors**: Auto-rebuild capability
- **Gateway**: Configuração versionada
- **Application**: Blue/green deployment ready

---

**Nota**: Esta arquitetura foi projetada para segurança máxima, com o collector operando apenas em modo outbound e todas as comunicações criptografadas via HTTPS/WSS.