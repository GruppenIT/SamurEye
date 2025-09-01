# vlxsam02 - Otimização da Instalação Node.js

## Problema Identificado
O script vlxsam02 estava gerando conflitos durante a instalação do Node.js devido a:
- Conflitos entre pacotes node-* do Ubuntu
- Instalação de dependências recomendadas desnecessárias
- Método de instalação NodeSource desatualizado

## Soluções Implementadas

### 1. Limpeza Completa Prévia
```bash
# Remove Node.js antigo completamente
apt-get remove -y nodejs npm node 2>/dev/null || true
apt-get purge -y nodejs npm node 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
```

### 2. Repositório NodeSource Atualizado
```bash
# Método mais direto com GPG key específica
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/nodesource.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
```

### 3. Instalação Limpa
```bash
# Apenas pacotes essenciais, sem recomendados
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs
```

### 4. Dependências Básicas Otimizadas
- Removidos: `systemd`, `software-properties-common`
- Mantidos apenas pacotes essenciais
- Flag `--no-install-recommends` para evitar conflitos

## Resultados Esperados
✅ Instalação mais rápida e limpa
✅ Evita conflitos com pacotes Ubuntu
✅ Node.js 20 + npm funcionais
✅ Ferramentas globais essenciais (pm2, tsx)

## Status
**OTIMIZADO**: Script vlxsam02 pronto para instalação sem conflitos
**IP CORRIGIDO**: Conecta ao PostgreSQL em 172.24.1.153