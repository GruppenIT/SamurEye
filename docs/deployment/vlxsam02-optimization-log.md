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
**FUNCIONANDO**: Script vlxsam02 executado com sucesso
- ✅ Node.js 20 instalado sem conflitos
- ✅ Dependências npm instaladas (incluindo devDependencies)
- ✅ Build funcional com npx fallback
- ✅ IP corrigido: PostgreSQL em 172.24.1.153
- ⚠️ PostgreSQL connection warning (normal - vlxsam03 deve ser executado primeiro)

## Correção do Build
**Problema**: Vite não estava disponível globalmente
**Solução**: 
- Instalar dependências completas (`npm install` sem `--production`)
- Fallback para `npx vite build` se `npm run build` falhar
- Usar script `start` correto do package.json

## Diagnóstico de Problemas na Inicialização
**Problema**: Aplicação falha ao iniciar via systemd (exit code 1)
**Ferramentas implementadas**:
- Script de diagnóstico detalhado (`debug-app.sh`)
- Verificação automática de logs de erro
- Teste de conexão PostgreSQL manual
- Teste de execução manual da aplicação
- Correção automática de permissões
- Logs detalhados do systemd

## Possíveis Causas do Erro
1. **Conexão PostgreSQL**: Embora vlxsam03 esteja funcionando
2. **Permissões de arquivos**: Proprietário incorreto dos arquivos
3. **Variáveis de ambiente**: Configuração .env pode ter problemas
4. **Dependências**: Alguma dependência pode estar faltando