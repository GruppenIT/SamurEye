#!/bin/bash

# Correção rápida de permissões vlxsam04
set -e

echo "🔧 Corrigindo permissões vlxsam04..."

# Parar serviço
systemctl stop samureye-collector

# Corrigir permissões do arquivo .env
chown samureye-collector:samureye-collector /etc/samureye-collector/.env
chmod 644 /etc/samureye-collector/.env

# Corrigir permissões do diretório de configuração
chown samureye-collector:samureye-collector /etc/samureye-collector
chmod 755 /etc/samureye-collector

# Corrigir todas as permissões do collector
chown -R samureye-collector:samureye-collector /opt/samureye-collector
chown -R samureye-collector:samureye-collector /var/log/samureye-collector

echo "✅ Permissões corrigidas"

# Testar leitura do arquivo .env
if sudo -u samureye-collector test -r /etc/samureye-collector/.env; then
    echo "✅ Arquivo .env acessível pelo usuário samureye-collector"
else
    echo "❌ Arquivo .env ainda inacessível"
    exit 1
fi

# Iniciar serviço
systemctl start samureye-collector
sleep 2

# Verificar status
if systemctl is-active --quiet samureye-collector; then
    echo "✅ Serviço iniciado com sucesso!"
    echo "📝 Ver logs: journalctl -f -u samureye-collector"
else
    echo "❌ Serviço ainda com problemas"
    systemctl status samureye-collector
fi