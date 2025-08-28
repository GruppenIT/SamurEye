#!/bin/bash

# Script de correção rápida para step-ca no vlxsam01
# Execute este script após o erro de instalação do step-ca

echo "🔧 Aplicando correção para step-ca..."

# Verificar se o step-ca foi extraído corretamente
if [ -f "/tmp/step-ca" ]; then
    echo "✅ step-ca encontrado em /tmp/step-ca"
    
    # Mover para localização correta
    sudo mv /tmp/step-ca /usr/local/bin/step-ca
    sudo chmod +x /usr/local/bin/step-ca
    
    # Criar usuário step-ca se não existir
    sudo useradd --system --home /etc/step-ca --shell /bin/false step-ca 2>/dev/null || true
    
    # Verificar instalação
    if step-ca version > /dev/null 2>&1; then
        echo "✅ step-ca instalado corretamente: $(step-ca version | head -1)"
        echo "🎉 Correção aplicada com sucesso!"
        echo ""
        echo "Agora você pode continuar com o script principal ou executar:"
        echo "curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam01/install.sh | bash"
    else
        echo "❌ Erro na verificação do step-ca"
        exit 1
    fi
else
    echo "❌ step-ca não encontrado em /tmp/step-ca"
    echo "Execute primeiro o download:"
    echo "wget -q -O /tmp/step-ca.tar.gz 'https://github.com/smallstep/certificates/releases/download/v0.25.2/step-ca_linux_0.25.2_amd64.tar.gz'"
    echo "tar -xzf /tmp/step-ca.tar.gz -C /tmp/"
    exit 1
fi