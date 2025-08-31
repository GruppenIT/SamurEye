import { Eye, LogOut, Settings, Users } from 'lucide-react';
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
  
  // Fetch admin session
  const { data: adminUser } = useQuery({
    queryKey: ['/api/admin/me'],
    retry: false,
  });

  // Fetch system settings for logo
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