# SamurEye - Guia Rápido

## Como começar a usar o sistema

Você está logado como **Global Admin** e precisa criar um tenant para acessar as funcionalidades.

### Passo 1: Criar um Tenant
1. Vá para a página **Global Admin** (no menu lateral)
2. Clique em **"Criar Tenant"**
3. Preencha:
   - **Nome**: ex: "Minha Empresa"
   - **Slug**: ex: "minha-empresa" (só letras minúsculas, números e hífens)
   - **Descrição**: ex: "Tenant principal para testes"
4. Clique em **"Criar"**

### Passo 2: Adicionar Dados de Exemplo
1. No card do tenant criado, clique em **"Dados Exemplo"**
2. Isso criará automaticamente:
   - 2 collectors de exemplo (um online, um offline)
   - Dados de telemetria
   - Credenciais de exemplo
   - Journeys de teste

### Passo 3: Selecionar o Tenant
1. Vá para **"Configurações"** ou **"Tenant Users"**
2. Selecione o tenant criado como ativo
3. Agora você pode navegar para todas as outras páginas:
   - **Dashboard**: métricas e visão geral
   - **Collectors**: gerenciar collectors
   - **Journeys**: testes de segurança
   - **Credentials**: credenciais
   - **Threat Intelligence**: inteligência de ameaças

## Estado Atual
- ✅ Object Storage configurado
- ✅ Sistema de upload de logos implementado
- ✅ Endpoint de dados de exemplo funcionando
- ✅ Multi-tenant funcionando

## Problemas?
Se continuar vendo "No active tenant selected", verifique se:
1. Criou pelo menos um tenant
2. Selecionou o tenant como ativo nas configurações
3. Fez logout e login novamente se necessário