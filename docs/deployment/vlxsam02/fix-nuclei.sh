#!/bin/bash

# Script específico para corrigir a instalação do Nuclei no vlxsam02

set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "🔧 Corrigindo instalação do Nuclei..."

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    echo "Execute como root: sudo ./fix-nuclei.sh"
    exit 1
fi

cd /tmp
NUCLEI_VERSION="3.2.9"
NUCLEI_ZIP="nuclei_${NUCLEI_VERSION}_linux_amd64.zip"

# Remover instalação anterior
log "Removendo instalação anterior do Nuclei..."
rm -f nuclei /usr/local/bin/nuclei "$NUCLEI_ZIP" 2>/dev/null

log "Baixando Nuclei v${NUCLEI_VERSION}..."
if wget -q "https://github.com/projectdiscovery/nuclei/releases/download/v${NUCLEI_VERSION}/$NUCLEI_ZIP"; then
    log "Download concluído. Extraindo..."
    
    # Extrair de forma completamente silenciosa e não-interativa
    if unzip -o -q "$NUCLEI_ZIP" 2>/dev/null; then
        if [ -f "nuclei" ]; then
            log "Movendo nuclei para /usr/local/bin/..."
            mv nuclei /usr/local/bin/
            chmod +x /usr/local/bin/nuclei
            
            # Testar instalação
            if /usr/local/bin/nuclei -version >/dev/null 2>&1; then
                VERSION_OUTPUT=$(/usr/local/bin/nuclei -version 2>/dev/null | head -1)
                log "✅ Nuclei instalado com sucesso: $VERSION_OUTPUT"
            else
                log "⚠️ Nuclei instalado mas com problemas na execução"
            fi
        else
            log "❌ Arquivo nuclei não encontrado após extração"
        fi
        
        # Limpar arquivos temporários
        log "Limpando arquivos temporários..."
        rm -f "$NUCLEI_ZIP" README*.md LICENSE.md 2>/dev/null
    else
        log "❌ Falha ao extrair Nuclei"
    fi
else
    log "❌ Falha ao baixar Nuclei"
fi

log "Correção do Nuclei concluída."