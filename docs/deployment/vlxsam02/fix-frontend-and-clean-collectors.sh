#!/bin/bash

# vlxsam02 - Correção Frontend + Limpeza Collectors
# Execute APENAS no vlxsam02

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./fix-frontend-and-clean-collectors.sh"
fi

echo "🔧 vlxsam02 - CORREÇÃO FRONTEND + LIMPEZA COLLECTORS"
echo "===================================================="
echo "Servidor: vlxsam02 (172.24.1.152)"
echo "Função: Application Server"
echo ""

# Detectar diretório da aplicação
WORKING_DIR=""
if [ -d "/opt/samureye/SamurEye" ]; then
    WORKING_DIR="/opt/samureye/SamurEye"
elif [ -d "/opt/SamurEye" ]; then
    WORKING_DIR="/opt/SamurEye"
else
    error "Diretório da aplicação SamurEye não encontrado"
fi

log "📁 Aplicação encontrada em: $WORKING_DIR"
cd "$WORKING_DIR"

# ============================================================================
# 1. VERIFICAR E CORRIGIR PROPRIEDADE DO REPOSITÓRIO
# ============================================================================

if [ -d ".git" ]; then
    log "🔧 Corrigindo propriedade do repositório Git..."
    git config --global --add safe.directory "$WORKING_DIR"
    chown -R samureye:samureye .git 2>/dev/null || true
fi

# ============================================================================
# 2. PARAR APLICAÇÃO ANTES DAS CORREÇÕES
# ============================================================================

log "⏹️ Parando aplicação..."
systemctl stop samureye-app 2>/dev/null || warn "Serviço já estava parado"

# ============================================================================
# 3. CORREÇÕES DO FRONTEND - ADMINLAYOUT
# ============================================================================

log "🎨 Aplicando correções do frontend..."

mkdir -p client/src/components/layout

# AdminLayout.tsx
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

# AdminHeader.tsx
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

log "✅ AdminLayout e AdminHeader criados"

# ============================================================================
# 4. LIMPEZA DE CACHE E REBUILD
# ============================================================================

log "🧹 Limpando cache do build..."
rm -rf dist/public 2>/dev/null || true
rm -rf node_modules/.vite 2>/dev/null || true

log "🔨 Fazendo rebuild do frontend..."
if npm run build; then
    log "✅ Build concluído com sucesso"
else
    error "Build falhou - verificar erros de sintaxe"
fi

# ============================================================================
# 5. LIMPEZA DE COLLECTORS DUPLICADOS
# ============================================================================

log "🧹 Limpando collectors duplicados..."

# Detectar IP do PostgreSQL
POSTGRES_IP=""
if ping -c 1 vlxsam03 >/dev/null 2>&1; then
    POSTGRES_IP=$(ping -c 1 vlxsam03 | grep -oP '(?<=\()\d+\.\d+\.\d+\.\d+(?=\))' | head -1)
elif ping -c 1 172.24.1.153 >/dev/null 2>&1; then
    POSTGRES_IP="172.24.1.153"
else
    error "PostgreSQL vlxsam03 não acessível"
fi

# URLs de teste
DATABASE_URLS=(
    "postgresql://samureye:SamurEye2024!@$POSTGRES_IP:5432/samureye_prod"
    "postgresql://samureye:SamurEye2024!@$POSTGRES_IP:5432/samureye"
    "postgresql://postgres:SamurEye2024!@$POSTGRES_IP:5432/samureye_prod"
    "postgresql://postgres:SamurEye2024!@$POSTGRES_IP:5432/samureye"
)

WORKING_URL=""
for url in "${DATABASE_URLS[@]}"; do
    if echo "SELECT 1;" | psql "$url" >/dev/null 2>&1; then
        WORKING_URL="$url"
        break
    fi
done

if [ -z "$WORKING_URL" ]; then
    error "Nenhuma URL PostgreSQL funcionou"
fi

# Verificar collectors
TOTAL_COLLECTORS=$(psql "$WORKING_URL" -t -c "SELECT COUNT(*) FROM collectors;" | tr -d ' ')
log "📊 Collectors no banco: $TOTAL_COLLECTORS"

if [ "$TOTAL_COLLECTORS" -gt 1 ]; then
    log "🗑️ Limpando $TOTAL_COLLECTORS collectors duplicados..."
    psql "$WORKING_URL" -c "DELETE FROM collectors;" >/dev/null 2>&1
    log "✅ Collectors limpos - re-registro será feito pelo vlxsam04"
elif [ "$TOTAL_COLLECTORS" -eq 1 ]; then
    log "✅ Apenas 1 collector - mantendo registro"
else
    log "ℹ️ 0 collectors - vlxsam04 irá registrar quando reiniciado"
fi

# ============================================================================
# 6. AJUSTAR PERMISSÕES E INICIAR APLICAÇÃO
# ============================================================================

log "🔧 Ajustando permissões..."
chown -R samureye:samureye "$WORKING_DIR"
chmod +x "$WORKING_DIR"

log "🚀 Iniciando aplicação..."
systemctl start samureye-app

# Aguardar inicialização
sleep 10

if systemctl is-active --quiet samureye-app; then
    log "✅ Aplicação iniciada com sucesso"
    
    # Testar endpoint
    if curl -s http://localhost:5000/api/admin/me >/dev/null 2>&1; then
        log "✅ API respondendo"
    else
        warn "API ainda inicializando"
    fi
else
    error "❌ Falha ao iniciar aplicação - verificar logs"
fi

echo ""
log "✅ CORREÇÕES vlxsam02 CONCLUÍDAS!"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo "   1. Executar script de correção no vlxsam04:"
echo "      curl -fsSL https://raw.githubusercontent.com/GruppenIT/SamurEye/refs/heads/main/docs/deployment/vlxsam04/fix-collector-registration.sh | sudo bash"
echo ""
echo "   2. Testar interface corrigida:"
echo "      https://app.samureye.com.br/admin/collectors"
echo ""
echo "📝 MONITORAR:"
echo "   journalctl -u samureye-app -f"

exit 0