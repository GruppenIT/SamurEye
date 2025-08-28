# Quick Fix: ensurepip Ubuntu 24.04

## 🚨 PROBLEMA: ensurepip Falha no Ubuntu 24.04

O script parou aqui porque o GitHub ainda não foi atualizado com o fix do ensurepip.

## ✅ SOLUÇÃO RÁPIDA (Execute no vlxsam04)

### 1. Resolver pip manualmente:
```bash
# Instalar pip para Python 3.12
sudo apt install -y python3-pip python3-venv

# Atualizar pip
python3.12 -m pip install --upgrade pip setuptools wheel
```

### 2. Instalar dependências Python:
```bash
python3.12 -m pip install \
    aiohttp \
    websockets \
    cryptography \
    requests \
    certifi \
    psutil \
    asyncio \
    pyyaml \
    structlog \
    python-multipart \
    aiofiles
```

### 3. Continuar com o resto da instalação:
```bash
# Re-executar o script completo (agora vai funcionar)
curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/main/docs/deployment/vlxsam04/install.sh | bash
```

## 💡 ALTERNATIVA: Script Local Corrigido

Se quiser usar a versão já corrigida:
```bash
# Baixar repositório completo
git clone https://github.com/GruppenIT/SamurEye.git
cd SamurEye

# Executar script local (já tem fix ensurepip)
sudo bash docs/deployment/vlxsam04/install.sh
```

## 🔍 O que Esperar Após o Fix

O script continuará automaticamente com:
1. ✅ Validação Ubuntu 24.04
2. ✅ Criação do usuário samureye-collector
3. ✅ Estrutura de diretórios multi-tenant
4. ✅ Instalação Nmap, Nuclei, Masscan, Gobuster
5. ✅ Configuração step-ca
6. ✅ Scripts auxiliares (health-check, etc.)
7. ✅ Serviços systemd
8. ✅ Configuração automática .env
9. ✅ Orientações próximos passos

---

**Tempo estimado**: 5-10 minutos para completar após resolver o pip