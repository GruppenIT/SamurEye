import { Plus, Server, Play } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { useTenant } from '@/contexts/TenantContext';
import { useQuery } from '@tanstack/react-query';
import { useI18n } from '@/hooks/useI18n';

interface SidebarProps {
  onNewJourney: () => void;
  onAddCollector: () => void;
}

export function Sidebar({ onNewJourney, onAddCollector }: SidebarProps) {
  const { currentUser, switchTenant } = useTenant();
  const { t } = useI18n();

  const { data: metrics } = useQuery({
    queryKey: ['/api/dashboard/metrics'],
    refetchInterval: 30000, // Refresh every 30 seconds
  });

  const handleTenantChange = async (tenantId: string) => {
    try {
      await switchTenant(tenantId);
    } catch (error) {
      console.error('Failed to switch tenant:', error);
    }
  };

  return (
    <aside className="w-64 bg-secondary border-r border-border p-6" data-testid="sidebar">
      {/* Tenant Selector */}
      <div className="mb-6">
        <label className="block text-sm font-medium text-muted-foreground mb-2">
          {t('dashboard.activeTenant')}
        </label>
        <Select
          value={currentUser?.currentTenant?.id || ''}
          onValueChange={handleTenantChange}
          data-testid="tenant-selector"
        >
          <SelectTrigger className="w-full">
            <SelectValue placeholder="Selecione um tenant" />
          </SelectTrigger>
          <SelectContent>
            {currentUser?.tenants?.map((tenantUser) => (
              <SelectItem key={tenantUser.tenant.id} value={tenantUser.tenant.id}>
                {tenantUser.tenant.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      
      {/* Quick Stats */}
      <div className="space-y-4 mb-6">
        <div className="bg-card p-3 rounded-lg" data-testid="collectors-stat">
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">{t('dashboard.collectorsOnline')}</span>
            <span className="text-success font-semibold">
              {metrics?.collectors.online || 0}/{metrics?.collectors.total || 0}
            </span>
          </div>
          <div className="flex items-center mt-1">
            <div className="w-2 h-2 bg-success rounded-full animate-pulse mr-2"></div>
            <span className="text-xs text-muted-foreground">
              Última sincronização: 2{t('time.minutes')}
            </span>
          </div>
        </div>
        
        <div className="bg-card p-3 rounded-lg" data-testid="jobs-stat">
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">{t('dashboard.activeJobs')}</span>
            <span className="text-info font-semibold">
              {metrics?.journeys.active || 0}
            </span>
          </div>
        </div>
        
        <div className="bg-card p-3 rounded-lg" data-testid="alerts-stat">
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">{t('dashboard.criticalAlerts')}</span>
            <span className="text-destructive font-semibold">
              {metrics?.vulnerabilities.critical || 0}
            </span>
          </div>
        </div>
      </div>
      
      {/* Quick Actions */}
      <div className="space-y-2">
        <Button
          className="w-full bg-accent hover:bg-accent/90"
          onClick={onNewJourney}
          data-testid="new-journey-button"
        >
          <Play className="mr-2 h-4 w-4" />
          {t('dashboard.newJourney')}
        </Button>
        <Button
          variant="outline"
          className="w-full"
          onClick={onAddCollector}
          data-testid="add-collector-button"
        >
          <Server className="mr-2 h-4 w-4" />
          {t('dashboard.addCollector')}
        </Button>
      </div>
    </aside>
  );
}
