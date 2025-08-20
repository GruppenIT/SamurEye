import { Plus, RefreshCw } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { useQuery } from '@tanstack/react-query';
import { useI18n } from '@/hooks/useI18n';

export function CollectorStatus() {
  const { t } = useI18n();
  
  const { data: collectors, isLoading } = useQuery({
    queryKey: ['/api/collectors'],
    refetchInterval: 10000, // Refresh every 10 seconds
  });

  if (isLoading) {
    return (
      <Card className="bg-secondary mb-8">
        <CardHeader>
          <CardTitle className="text-xl font-semibold text-white">Status dos Coletores</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-4 gap-4">
            {[...Array(4)].map((_, i) => (
              <div key={i} className="bg-card p-4 rounded-lg animate-pulse">
                <div className="h-4 bg-muted rounded mb-3"></div>
                <div className="space-y-2">
                  <div className="h-3 bg-muted rounded"></div>
                  <div className="h-3 bg-muted rounded"></div>
                  <div className="h-3 bg-muted rounded"></div>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    );
  }

  // Mock telemetry data - in real app this would come from WebSocket or separate API
  const collectorsWithTelemetry = collectors?.map((collector: any, index: number) => ({
    ...collector,
    telemetry: {
      cpu: index === 0 ? 23.4 : index === 1 ? 12.1 : index === 2 ? 89.3 : 0,
      memory: index === 0 ? 67.8 : index === 1 ? 34.7 : index === 2 ? 92.1 : 0,
      disk: index === 0 ? 45.2 : index === 1 ? 78.9 : index === 2 ? 23.4 : 0,
      lastSync: index === 0 ? '2min' : index === 1 ? '5min' : index === 2 ? '1min' : '2h'
    }
  })) || [];

  const onlineCollectors = collectorsWithTelemetry.filter((c: any) => c.status === 'online').length;
  const totalCollectors = collectorsWithTelemetry.length;

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'online':
        return {
          border: 'border-l-4 border-green-500',
          badge: 'bg-green-500/20 text-green-500',
          dot: 'bg-green-500 animate-pulse'
        };
      case 'offline':
        return {
          border: 'border-l-4 border-red-500',
          badge: 'bg-red-500/20 text-red-500',
          dot: 'bg-red-500'
        };
      case 'enrolling':
        return {
          border: 'border-l-4 border-yellow-500',
          badge: 'bg-yellow-500/20 text-yellow-500',
          dot: 'bg-yellow-500 animate-pulse'
        };
      default:
        return {
          border: 'border-l-4 border-gray-500',
          badge: 'bg-gray-500/20 text-gray-500',
          dot: 'bg-gray-500'
        };
    }
  };

  const getProgressColor = (value: number) => {
    if (value >= 80) return 'bg-red-500';
    if (value >= 60) return 'bg-yellow-500';
    return 'bg-green-500';
  };

  return (
    <Card className="bg-secondary mb-8" data-testid="collector-status">
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <CardTitle className="text-xl font-semibold text-white">
              Status dos Coletores
            </CardTitle>
            <Badge variant="secondary" className="bg-green-500/20 text-green-500" data-testid="collectors-online-badge">
              {onlineCollectors}/{totalCollectors} Online
            </Badge>
          </div>
          <div className="flex items-center space-x-2">
            <Button 
              size="sm" 
              className="bg-accent hover:bg-accent/90"
              data-testid="add-collector-button"
            >
              <Plus className="mr-2 h-4 w-4" />
              {t('dashboard.addCollector')}
            </Button>
            <Button 
              variant="outline" 
              size="sm"
              data-testid="refresh-collectors-button"
            >
              <RefreshCw className="mr-2 h-4 w-4" />
              {t('common.refresh')}
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-4 gap-4">
          {collectorsWithTelemetry.map((collector: any) => {
            const statusColors = getStatusColor(collector.status);
            
            return (
              <div 
                key={collector.id} 
                className={`bg-card p-4 rounded-lg ${statusColors.border}`}
                data-testid={`collector-card-${collector.name}`}
              >
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center space-x-2">
                    <div className={`w-3 h-3 rounded-full ${statusColors.dot}`}></div>
                    <span className="font-semibold text-white" data-testid={`collector-name-${collector.name}`}>
                      {collector.name}
                    </span>
                  </div>
                  <Badge className={`text-xs border-0 ${statusColors.badge}`} data-testid={`collector-status-${collector.name}`}>
                    {t(`status.${collector.status}`) || collector.status.toUpperCase()}
                  </Badge>
                </div>
                
                {collector.status === 'online' && (
                  <div className="space-y-2 text-sm">
                    <div className="flex items-center justify-between">
                      <span className="text-muted-foreground">CPU</span>
                      <span className="text-white" data-testid={`collector-cpu-${collector.name}`}>
                        {collector.telemetry.cpu}%
                      </span>
                    </div>
                    <Progress 
                      value={collector.telemetry.cpu} 
                      className="w-full h-1.5"
                      data-testid={`collector-cpu-progress-${collector.name}`}
                    />
                    
                    <div className="flex items-center justify-between">
                      <span className="text-muted-foreground">Memória</span>
                      <span className="text-white" data-testid={`collector-memory-${collector.name}`}>
                        {collector.telemetry.memory}%
                      </span>
                    </div>
                    <Progress 
                      value={collector.telemetry.memory} 
                      className="w-full h-1.5"
                      data-testid={`collector-memory-progress-${collector.name}`}
                    />
                    
                    <div className="flex items-center justify-between">
                      <span className="text-muted-foreground">Disco</span>
                      <span className="text-white" data-testid={`collector-disk-${collector.name}`}>
                        {collector.telemetry.disk}%
                      </span>
                    </div>
                    <Progress 
                      value={collector.telemetry.disk} 
                      className="w-full h-1.5"
                      data-testid={`collector-disk-progress-${collector.name}`}
                    />
                    
                    <div className="flex items-center justify-between pt-2">
                      <span className="text-muted-foreground">Última sync</span>
                      <span className="text-white text-xs" data-testid={`collector-sync-${collector.name}`}>
                        {collector.telemetry.lastSync} {t('time.ago')}
                      </span>
                    </div>
                  </div>
                )}
                
                {collector.status === 'offline' && (
                  <div className="space-y-2 text-sm">
                    {['CPU', 'Memória', 'Disco'].map(metric => (
                      <div key={metric}>
                        <div className="flex items-center justify-between">
                          <span className="text-muted-foreground">{metric}</span>
                          <span className="text-muted-foreground">--</span>
                        </div>
                        <div className="w-full bg-muted rounded-full h-1.5">
                          <div className="bg-muted h-1.5 rounded-full" style={{ width: '0%' }}></div>
                        </div>
                      </div>
                    ))}
                    
                    <div className="flex items-center justify-between pt-2">
                      <span className="text-muted-foreground">Última sync</span>
                      <span className="text-red-500 text-xs" data-testid={`collector-offline-sync-${collector.name}`}>
                        {collector.telemetry.lastSync} {t('time.ago')}
                      </span>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
}
