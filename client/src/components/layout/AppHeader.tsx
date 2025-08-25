import { Bell, Eye, LogOut } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useTenant } from '@/contexts/TenantContext';
import { useI18n } from '@/hooks/useI18n';
import { useQuery } from '@tanstack/react-query';

interface AppHeaderProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
}

export function AppHeader({ activeTab, onTabChange }: AppHeaderProps) {
  const { currentUser } = useTenant();
  const { language, t, switchLanguage } = useI18n();
  
  // Fetch system settings to get logo (public route)
  const { data: systemSettings } = useQuery({
    queryKey: ['/api/system/settings'],
    retry: false,
  });

  const navItems = [
    { id: 'dashboard', label: t('nav.dashboard') },
    { id: 'collectors', label: t('nav.collectors') },
    { id: 'journeys', label: t('nav.journeys') },
    { id: 'intelligence', label: t('nav.intelligence') },
    { id: 'credentials', label: t('nav.credentials') },
    { id: 'users', label: 'Usuários' },
  ];

  const handleLogout = async () => {
    try {
      await fetch('/api/logout', { method: 'POST' });
      window.location.href = '/';
    } catch (error) {
      console.error('Logout error:', error);
      window.location.href = '/';
    }
  };

  const getInitials = (user: any) => {
    if (user?.firstName && user?.lastName) {
      return `${user.firstName[0]}${user.lastName[0]}`;
    }
    if (user?.email) {
      return user.email.substring(0, 2).toUpperCase();
    }
    return 'U';
  };

  return (
    <header className="bg-secondary border-b border-border sticky top-0 z-50" data-testid="app-header">
      <div className="px-6 py-4 flex items-center justify-between">
        <div className="flex items-center space-x-6">
          <div className="flex items-center space-x-3">
            {systemSettings?.logoUrl ? (
              <img
                src={systemSettings.logoUrl}
                alt="SamurEye Logo"
                className="w-12 h-12 object-contain rounded-lg"
                data-testid="system-logo"
              />
            ) : (
              <div className="w-12 h-12 bg-accent rounded-lg flex items-center justify-center">
                <Eye className="text-white text-sm" size={24} />
              </div>
            )}
            <h1 className="text-xl font-bold text-white">{systemSettings?.systemName || 'SamurEye'}</h1>
            <Badge variant="secondary" className="text-xs bg-info text-white">
              MVP
            </Badge>
          </div>
          
          {/* Navigation Menu */}
          <nav className="hidden md:flex items-center space-x-6">
            {navItems.map((item) => (
              <button
                key={item.id}
                onClick={() => onTabChange(item.id)}
                className={`text-sm font-medium transition-colors pb-1 ${
                  activeTab === item.id
                    ? 'text-accent border-b-2 border-accent'
                    : 'text-muted-foreground hover:text-foreground'
                }`}
                data-testid={`nav-${item.id}`}
              >
                {item.label}
              </button>
            ))}
          </nav>
        </div>
        
        <div className="flex items-center space-x-4">
          {/* Language Toggle */}
          <div className="flex items-center bg-muted rounded-lg p-1">
            <Button
              size="sm"
              variant={language === 'pt-BR' ? 'default' : 'ghost'}
              className="px-3 py-1 text-sm h-auto"
              onClick={() => switchLanguage('pt-BR')}
              data-testid="lang-pt"
            >
              PT
            </Button>
            <Button
              size="sm"
              variant={language === 'en' ? 'default' : 'ghost'}
              className="px-3 py-1 text-sm h-auto"
              onClick={() => switchLanguage('en')}
              data-testid="lang-en"
            >
              EN
            </Button>
          </div>
          
          {/* Notifications */}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="sm" className="relative" data-testid="notifications-button">
                <Bell size={18} />
                <Badge className="absolute -top-1 -right-1 bg-destructive text-destructive-foreground w-5 h-5 text-xs rounded-full flex items-center justify-center p-0">
                  3
                </Badge>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-80">
              <div className="p-4">
                <h4 className="font-semibold mb-3">Notificações</h4>
                <div className="space-y-2">
                  <div className="p-2 bg-muted rounded-lg">
                    <p className="text-sm font-medium">Coletor offline</p>
                    <p className="text-xs text-muted-foreground">collector-branch desconectado há 2h</p>
                  </div>
                  <div className="p-2 bg-muted rounded-lg">
                    <p className="text-sm font-medium">Nova vulnerabilidade crítica</p>
                    <p className="text-xs text-muted-foreground">CVE-2024-1234 descoberta</p>
                  </div>
                </div>
              </div>
            </DropdownMenuContent>
          </DropdownMenu>
          
          {/* User Menu */}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" className="flex items-center space-x-3 px-3" data-testid="user-menu-button">
                <div className="flex flex-col text-right">
                  <span className="text-sm font-medium">
                    {currentUser?.firstName && currentUser?.lastName
                      ? `${currentUser.firstName} ${currentUser.lastName}`
                      : currentUser?.email || 'User'}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {currentUser?.isSocUser ? 'SOC Operator' : 'User'}
                  </span>
                </div>
                <div className="w-8 h-8 bg-gradient-to-br from-purple-500 to-pink-500 rounded-full flex items-center justify-center">
                  <span className="text-white text-sm font-medium">
                    {getInitials(currentUser)}
                  </span>
                </div>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem disabled>
                <span className="text-sm">
                  {currentUser?.currentTenant?.name || 'No Tenant'}
                </span>
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={() => switchLanguage(language === 'pt-BR' ? 'en' : 'pt-BR')}>
                {t('common.switchLanguage')}
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={handleLogout} data-testid="button-logout">
                <LogOut className="mr-2 h-4 w-4" />
                {t('common.logout')}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>
    </header>
  );
}
