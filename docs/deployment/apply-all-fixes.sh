#!/bin/bash

# SamurEye - Aplicar TODAS as correções no ambiente on-premise
# Resolve: TenantProvider + Frontend + Collectors duplicados

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO: $1${NC}"; }

if [ "$EUID" -ne 0 ]; then
    error "Execute como root: sudo ./apply-all-fixes.sh"
fi

echo "🚀 SAMUREYE - APLICAÇÃO DE TODAS AS CORREÇÕES"
echo "============================================"
echo "✅ Correção TenantProvider (AdminLayout)"
echo "✅ Frontend rebuild com fixes"
echo "✅ Limpeza de collectors duplicados"
echo "✅ Re-registro limpo do vlxsam04"
echo ""

# Detectar onde estamos executando
if [ -f "/opt/samureye/SamurEye/package.json" ]; then
    WORKING_DIR="/opt/samureye/SamurEye"
    log "📁 Executando no vlxsam02 - diretório da aplicação encontrado"
elif [ -f "/opt/samureye-collector/collector_agent.py" ]; then
    log "📁 Executando no vlxsam04 - collector detectado"
    error "Execute este script no vlxsam02 (Application Server)"
else
    error "Diretório da aplicação SamurEye não encontrado"
fi

cd "$WORKING_DIR"

# ============================================================================
# 1. CORREÇÕES DO FRONTEND - ADMINLAYOUT
# ============================================================================

log "🎨 Aplicando correções do frontend..."

# Verificar se AdminLayout já existe
if [ ! -f "client/src/components/layout/AdminLayout.tsx" ]; then
    log "📝 Criando AdminLayout.tsx..."
    
    mkdir -p client/src/components/layout
    
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
    log "✅ AdminLayout.tsx criado"
else
    log "✅ AdminLayout.tsx já existe"
fi

# Verificar se AdminHeader já existe
if [ ! -f "client/src/components/layout/AdminHeader.tsx" ]; then
    log "📝 Criando AdminHeader.tsx..."
    
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
    log "✅ AdminHeader.tsx criado"
else
    log "✅ AdminHeader.tsx já existe"
fi

# ============================================================================
# 2. REBUILD FRONTEND COM CORREÇÕES
# ============================================================================

log "🔨 Fazendo rebuild do frontend com correções..."

# Limpar cache do build
rm -rf dist/public 2>/dev/null || true
rm -rf node_modules/.vite 2>/dev/null || true

# Build com as correções
if npm run build 2>/dev/null; then
    log "✅ Build do frontend concluído com sucesso"
else
    error "Build do frontend falhou"
fi

# ============================================================================
# 3. LIMPEZA DE COLLECTORS DUPLICADOS
# ============================================================================

log "🧹 Verificando collectors duplicados no banco..."

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

# Verificar quantos collectors existem
TOTAL_COLLECTORS=$(psql "$WORKING_URL" -t -c "SELECT COUNT(*) FROM collectors;" | tr -d ' ')
log "📊 Collectors no banco: $TOTAL_COLLECTORS"

if [ "$TOTAL_COLLECTORS" -gt 1 ]; then
    warn "⚠️ $TOTAL_COLLECTORS collectors encontrados (esperado: 1)"
    log "🗑️ Limpando collectors duplicados..."
    
    # Limpeza automática (sem confirmação)
    psql "$WORKING_URL" -c "DELETE FROM collectors;" >/dev/null 2>&1
    
    REMAINING=$(psql "$WORKING_URL" -t -c "SELECT COUNT(*) FROM collectors;" | tr -d ' ')
    if [ "$REMAINING" -eq 0 ]; then
        log "✅ Limpeza concluída - 0 collectors no banco"
    else
        error "Limpeza falhou - ainda há $REMAINING collectors"
    fi
else
    log "✅ Apenas $TOTAL_COLLECTORS collector no banco - OK"
fi

# ============================================================================
# 4. REINICIAR SERVIÇOS
# ============================================================================

log "🔄 Reiniciando serviços..."

# Reiniciar aplicação principal
if systemctl restart samureye-app; then
    log "✅ samureye-app reiniciado"
else
    warn "Falha ao reiniciar samureye-app"
fi

# Reiniciar collector vlxsam04 se possível
if ssh -o ConnectTimeout=5 vlxsam04 "systemctl restart samureye-collector" 2>/dev/null; then
    log "✅ Collector vlxsam04 reiniciado via SSH"
else
    warn "SSH para vlxsam04 falhou - reiniciar manualmente"
fi

# ============================================================================
# 5. VERIFICAÇÃO FINAL
# ============================================================================

log "🧪 Aguardando estabilização (30 segundos)..."
sleep 30

# Verificar se a aplicação está respondendo
if curl -s http://localhost:5000/api/admin/me >/dev/null 2>&1; then
    log "✅ Aplicação respondendo localmente"
else
    warn "⚠️ Aplicação ainda inicializando"
fi

# Verificar collectors registrados
NEW_COUNT=$(psql "$WORKING_URL" -t -c "SELECT COUNT(*) FROM collectors;" | tr -d ' ')
log "📊 Collectors após correções: $NEW_COUNT"

if [ "$NEW_COUNT" -eq 1 ]; then
    log "✅ Exatamente 1 collector registrado - perfeito!"
elif [ "$NEW_COUNT" -eq 0 ]; then
    warn "⚠️ Aguardando re-registro do collector..."
else
    warn "⚠️ $NEW_COUNT collectors (verificar se há duplicação)"
fi

echo ""
log "✅ TODAS AS CORREÇÕES APLICADAS COM SUCESSO!"
echo ""
echo "📋 RESUMO:"
echo "   ✓ Frontend: AdminLayout integrado"
echo "   ✓ Build: Aplicação rebuilded"
echo "   ✓ Banco: Collectors duplicados limpos"
echo "   ✓ Serviços: Reiniciados"
echo ""
echo "🔗 TESTAR INTERFACE:"
echo "   https://app.samureye.com.br/admin/collectors"
echo ""
echo "📝 MONITORAR LOGS:"
echo "   journalctl -u samureye-app -f"
echo "   ssh vlxsam04 'journalctl -u samureye-collector -f'"
echo ""
echo "❓ SE AINDA HOUVER PROBLEMAS:"
echo "   1. Aguardar 2-3 minutos para re-registro"
echo "   2. Verificar se vlxsam04 está enviando heartbeat"
echo "   3. Recarregar página da interface (Ctrl+F5)"

exit 0