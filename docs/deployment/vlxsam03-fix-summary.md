# vlxsam03 Hard Reset - Correção Definitiva

## Problema Identificado
**Erro**: `Error: Invalid data directory for cluster 16 main`

## Causa Raiz
O script estava removendo o conteúdo do diretório de dados do PostgreSQL (`/var/lib/postgresql/16/main/*`) durante o reset, mas depois tentava iniciar o serviço sem verificar se o cluster precisava ser recriado.

## Solução Implementada

### 1. Detecção Automática do Cluster
```bash
DATA_DIR="/var/lib/postgresql/$POSTGRES_VERSION/main"
if [ ! -f "$DATA_DIR/PG_VERSION" ]; then
    # Cluster precisa ser recriado
fi
```

### 2. Recriação Automática do Cluster
```bash
# Garantir que o diretório existe com permissões corretas
mkdir -p "$DATA_DIR"
chown postgres:postgres "$DATA_DIR"
chmod 700 "$DATA_DIR"

# Inicializar cluster PostgreSQL
sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/initdb -D "$DATA_DIR" --locale=en_US.UTF-8
```

### 3. Ordem de Execução Corrigida
1. **Instalar PostgreSQL** (se necessário)
2. **Verificar e recriar cluster** (se dados foram removidos)
3. **Iniciar PostgreSQL**
4. **Configurar** (postgresql.conf e pg_hba.conf)  
5. **Reiniciar** para aplicar configurações
6. **Criar usuários e bancos**

## Melhorias Mantidas
- ✅ Reparo ultra-agressivo do dpkg (kill + configure 5x)
- ✅ Detecção automática de modo não-interativo (curl | bash)
- ✅ Sistema de múltiplas tentativas com fallbacks
- ✅ Senhas alinhadas com install.sh original (SamurEye2024!)
- ✅ Configuração completa PostgreSQL 16 + extensões

## Resultado Esperado
O script agora deve executar completamente sem erros, recriando automaticamente o cluster PostgreSQL quando necessário e configurando todos os serviços corretamente.

## Comando de Teste
```bash
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam03/install-hard-reset.sh | bash
```