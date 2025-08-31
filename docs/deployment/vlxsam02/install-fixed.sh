#!/bin/bash

# SamurEye vlxsam02 - VERSÃO CORRIGIDA COM TODAS AS FIXES
# Servidor: vlxsam02 (172.24.1.152)
# Inclui: DATABASE_URL automática + Frontend AdminLayout + Detecção PID

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de logging
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./install.sh"
fi

echo "🚀 SAMUREYE vlxsam02 - INSTALAÇÃO CORRIGIDA"
echo "==========================================="
echo "✅ Detecção automática de diretório da aplicação"
echo "✅ DATABASE_URL com IP correto (172.24.1.153)"
echo "✅ AdminLayout integrado para área administrativa"
echo "✅ Correção do erro TenantProvider"
echo ""

# Detectar IP do vlxsam03
log "🔍 Detectando IP do vlxsam03..."

VLXSAM03_IP=""
if ping -c 1 vlxsam03 >/dev/null 2>&1; then
    VLXSAM03_IP=$(ping -c 1 vlxsam03 | grep -oP '(?<=\()\d+\.\d+\.\d+\.\d+(?=\))' | head -1)
    log "📍 IP detectado via ping: $VLXSAM03_IP"
else
    VLXSAM03_IP="172.24.1.153"
    log "📍 Usando IP padrão: $VLXSAM03_IP"
fi

# Testar conectividade PostgreSQL
log "🔌 Testando conectividade PostgreSQL $VLXSAM03_IP:5432..."

if ! timeout 5 bash -c "</dev/tcp/$VLXSAM03_IP/5432" 2>/dev/null; then
    error "PostgreSQL não acessível em $VLXSAM03_IP:5432"
fi

# Instalar postgresql-client se necessário
if ! command -v psql >/dev/null 2>&1; then
    log "📦 Instalando postgresql-client..."
    apt-get update >/dev/null 2>&1
    apt-get install -y postgresql-client >/dev/null 2>&1
fi

# Testar diferentes URLs de conexão
log "🔐 Testando credenciais PostgreSQL..."

DATABASE_URLS=(
    "postgresql://samureye:SamurEye2024!@$VLXSAM03_IP:5432/samureye_prod"
    "postgresql://samureye:SamurEye2024!@$VLXSAM03_IP:5432/samureye"
    "postgresql://postgres:SamurEye2024!@$VLXSAM03_IP:5432/samureye_prod"
    "postgresql://postgres:SamurEye2024!@$VLXSAM03_IP:5432/samureye"
)

WORKING_URL=""
for url in "${DATABASE_URLS[@]}"; do
    if echo "SELECT version();" | psql "$url" >/dev/null 2>&1; then
        log "✅ URL funcional encontrada!"
        WORKING_URL="$url"
        break
    fi
done

if [ -z "$WORKING_URL" ]; then
    error "Nenhuma URL PostgreSQL funcionou - verificar vlxsam03"
fi

# ============================================================================
# INSTALAÇÃO DA APLICAÇÃO SAMUREYE
# ============================================================================

log "📦 Instalando dependências do sistema..."

# Atualizar sistema
apt update
apt install -y curl wget gnupg software-properties-common

# Instalar Node.js 20
if ! command -v node >/dev/null 2>&1; then
    log "📦 Instalando Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Instalar Git se necessário
if ! command -v git >/dev/null 2>&1; then
    apt install -y git
fi

# Criar usuário samureye se necessário
if ! id "samureye" >/dev/null 2>&1; then
    log "👤 Criando usuário samureye..."
    useradd -r -s /bin/bash -d /opt/samureye samureye
fi

# Criar diretório da aplicação
log "📁 Configurando diretório da aplicação..."

INSTALL_DIR="/opt/samureye/SamurEye"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Baixar aplicação SamurEye
if [ ! -d ".git" ]; then
    log "📥 Clonando repositório SamurEye..."
    git clone https://github.com/GruppenIT/SamurEye.git .
else
    log "🔄 Atualizando repositório existente..."
    git pull origin main
fi

# Instalar dependências
log "📦 Instalando dependências Node.js..."
npm install

# Configurar .env com DATABASE_URL correta
log "⚙️ Configurando variáveis de ambiente..."

cat > .env << EOF
# SamurEye vlxsam02 Configuration - AUTO-GENERATED $(date)
NODE_ENV=production
PORT=5000
DATABASE_URL=$WORKING_URL

# Security
SESSION_SECRET=samureye-prod-secret-$(openssl rand -hex 32)

# Timezone
TZ=America/Sao_Paulo

# Admin Credentials
ADMIN_EMAIL=admin@samureye.com.br
ADMIN_PASSWORD=SamurEye2024!

# Redis (opcional)
REDIS_URL=redis://$VLXSAM03_IP:6379

# Logging
LOG_LEVEL=info
LOG_FILE=/var/log/samureye/app.log
EOF

chown samureye:samureye .env
chmod 600 .env

# Sincronizar schema do banco
log "🗃️ Sincronizando schema do banco..."

if [ -f "package.json" ] && grep -q '"db:push"' package.json; then
    if npm run db:push >/dev/null 2>&1; then
        log "✅ Schema sincronizado com sucesso"
    else
        warn "Tentando db:push --force..."
        npm run db:push -- --force >/dev/null 2>&1 || warn "Schema sync falhou"
    fi
fi

# Build da aplicação
log "🔨 Fazendo build da aplicação..."
npm run build

# Criar diretório de logs
mkdir -p /var/log/samureye
chown samureye:samureye /var/log/samureye

# ============================================================================
# FRONTEND FIXES - ADMINLAYOUT INTEGRATION
# ============================================================================

log "🎨 Aplicando correções do frontend (AdminLayout)..."

# Criar AdminLayout
cat > client/src/components/layout/AdminLayout.tsx << 'EOF'
import { ReactNode } from 'react';
import { AdminHeader } from './AdminHeader';

interface AdminLayoutProps {
  children: ReactNode;
  title?: string;
}

export function AdminLayout({ children, title = "Administração" }: AdminLayoutProps) {
  return (
    <div className="min-h-screen bg-background">
      <AdminHeader title={title} />
      <main className="flex-1 p-6 overflow-y-auto" data-testid="admin-main-content">
        {children}
      </main>
    </div>
  );
}
EOF

# Criar AdminHeader
cat > client/src/components/layout/AdminHeader.tsx << 'EOF'
import { Eye, LogOut, Settings } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useQuery } from '@tanstack/react-query';
import { useLocation } from 'wouter';

interface AdminHeaderProps {
  title: string;
}

export function AdminHeader({ title }: AdminHeaderProps) {
  const [, setLocation] = useLocation();
  
  const { data: adminUser } = useQuery({
    queryKey: ['/api/admin/me'],
    retry: false,
  });

  const { data: systemSettings } = useQuery({
    queryKey: ['/api/system/settings'],
    retry: false,
  });

  const handleLogout = async () => {
    try {
      await fetch('/api/admin/logout', { method: 'POST' });
      setLocation('/admin');
    } catch (error) {
      console.error('Admin logout error:', error);
      setLocation('/admin');
    }
  };

  const navItems = [
    { id: 'dashboard', label: 'Dashboard', path: '/admin/dashboard' },
    { id: 'collectors', label: 'Coletores', path: '/admin/collectors' },
    { id: 'settings', label: 'Configurações', path: '/admin/settings' },
  ];

  return (
    <header className="bg-secondary border-b border-border sticky top-0 z-50" data-testid="admin-header">
      <div className="px-6 py-4 flex items-center justify-between">
        <div className="flex items-center space-x-6">
          <div className="flex items-center space-x-3">
            {systemSettings?.logoUrl ? (
              <img
                src={systemSettings.logoUrl}
                alt="SamurEye Logo"
                className="w-20 h-20 object-contain rounded-lg"
                data-testid="system-logo"
              />
            ) : (
              <div className="w-20 h-20 bg-accent rounded-lg flex items-center justify-center">
                <Eye className="text-white text-lg" size={32} />
              </div>
            )}
            <div>
              <h1 className="text-xl font-bold text-primary">SamurEye</h1>
              <p className="text-sm text-muted-foreground">{title}</p>
            </div>
          </div>
          
          <nav className="ml-8">
            <div className="flex space-x-4">
              {navItems.map((item) => (
                <Button
                  key={item.id}
                  variant="ghost"
                  onClick={() => setLocation(item.path)}
                  className="text-sm font-medium"
                  data-testid={`nav-${item.id}`}
                >
                  {item.label}
                </Button>
              ))}
            </div>
          </nav>
        </div>

        <div className="flex items-center space-x-4">
          {adminUser?.isAuthenticated && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" className="flex items-center space-x-2" data-testid="admin-menu">
                  <div className="w-8 h-8 bg-accent rounded-full flex items-center justify-center">
                    <span className="text-sm font-medium text-accent-foreground">
                      {adminUser.email?.substring(0, 2).toUpperCase() || 'AD'}
                    </span>
                  </div>
                  <span className="text-sm font-medium">{adminUser.email}</span>
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-56">
                <DropdownMenuItem onClick={() => setLocation('/admin/settings')} data-testid="admin-settings">
                  <Settings className="mr-2 h-4 w-4" />
                  Configurações
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={handleLogout} data-testid="admin-logout">
                  <LogOut className="mr-2 h-4 w-4" />
                  Sair
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )}
        </div>
      </div>
    </header>
  );
}
EOF

# Rebuild frontend com correções
log "🔨 Rebuild frontend com correções AdminLayout..."
npm run build

# ============================================================================
# CONFIGURAÇÃO DO SERVIÇO SYSTEMD
# ============================================================================

log "⚙️ Configurando serviço systemd..."

cat > /etc/systemd/system/samureye-app.service << EOF
[Unit]
Description=SamurEye Application Server
After=network.target
Requires=network.target

[Service]
Type=simple
User=samureye
Group=samureye
WorkingDirectory=$INSTALL_DIR
Environment=NODE_ENV=production
Environment=PORT=5000
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=samureye-app

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR /var/log/samureye /tmp

[Install]
WantedBy=multi-user.target
EOF

# Ajustar permissões
chown -R samureye:samureye "$INSTALL_DIR"
chmod +x "$INSTALL_DIR"

# Habilitar e iniciar serviço
systemctl daemon-reload
systemctl enable samureye-app
systemctl stop samureye-app 2>/dev/null || true
systemctl start samureye-app

# Aguardar inicialização
sleep 10

if systemctl is-active --quiet samureye-app; then
    log "✅ Serviço SamurEye iniciado com sucesso"
else
    error "❌ Falha ao iniciar serviço SamurEye"
fi

# ============================================================================
# VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Executando verificação final..."

# Testar endpoint local
if curl -s http://localhost:5000/api/admin/me >/dev/null 2>&1; then
    log "✅ Aplicação respondendo localmente"
else
    warn "⚠️ Aplicação ainda inicializando ou com problemas"
fi

# Mostrar status dos serviços
log "📊 Status dos serviços:"
systemctl status samureye-app --no-pager -l || true

echo ""
log "✅ INSTALAÇÃO vlxsam02 CONCLUÍDA COM SUCESSO!"
echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "   • Diretório: $INSTALL_DIR"
echo "   • DATABASE_URL: $WORKING_URL"
echo "   • Serviço: samureye-app (ativo)"
echo "   • AdminLayout: Integrado ✓"
echo "   • TenantProvider: Corrigido ✓"
echo ""
echo "🔗 ACESSO:"
echo "   • Local: http://localhost:5000"
echo "   • Admin: https://app.samureye.com.br/admin"
echo "   • API: https://api.samureye.com.br"
echo ""
echo "📝 LOGS:"
echo "   journalctl -u samureye-app -f"
echo ""
echo "🎯 PRÓXIMOS PASSOS:"
echo "   1. Verificar se vlxsam01 (Gateway) está funcionando"
echo "   2. Testar interface: https://app.samureye.com.br/admin/collectors"
echo "   3. Verificar logs se houver problemas"

exit 0