import { Play, Check, AlertTriangle, Shield, ArrowRight } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useQuery } from '@tanstack/react-query';
import { useI18n } from '@/hooks/useI18n';

export function ActivityFeed() {
  const { t } = useI18n();
  
  const { data: activities, isLoading } = useQuery({
    queryKey: ['/api/activities'],
    refetchInterval: 30000,
  });

  // Safe mock data
  const getMockActivities = () => [
    {
      id: 'mock-1',
      action: 'journey_started',
      title: 'Nova jornada Attack Surface iniciada',
      user: { firstName: 'João', lastName: 'Silva' },
      metadata: { target: '192.168.100.0/24' },
      timestamp: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
      status: 'running'
    },
    {
      id: 'mock-2',
      action: 'journey_completed',
      title: 'Jornada EDR Testing concluída',
      user: { firstName: 'João', lastName: 'Silva' },
      metadata: { endpointsTested: 23 },
      timestamp: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
      status: 'completed'
    }
  ];

  // Ensure we always have a valid array
  const safeActivities = Array.isArray(activities) ? activities : getMockActivities();

  const getIcon = (action: string) => {
    if (action === 'journey_started') return Play;
    if (action === 'journey_completed') return Check;
    if (action === 'collector_offline') return AlertTriangle;
    return Shield;
  };

  const getColors = (status: string) => {
    if (status === 'running') return { bg: 'bg-blue-500/20', text: 'text-blue-500', badge: 'bg-blue-500/20 text-blue-500' };
    if (status === 'completed') return { bg: 'bg-green-500/20', text: 'text-green-500', badge: 'bg-green-500/20 text-green-500' };
    if (status === 'offline') return { bg: 'bg-yellow-500/20', text: 'text-yellow-500', badge: 'bg-red-500/20 text-red-500' };
    return { bg: 'bg-gray-500/20', text: 'text-gray-500', badge: 'bg-gray-500/20 text-gray-500' };
  };

  const getStatusText = (status: string) => {
    if (status === 'running') return 'EM EXECUÇÃO';
    if (status === 'completed') return 'CONCLUÍDA';
    if (status === 'offline') return 'OFFLINE';
    return 'CRÍTICO';
  };

  if (isLoading) {
    return (
      <Card className="bg-secondary">
        <CardHeader>
          <CardTitle className="text-xl font-semibold text-white">Atividades Recentes</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {[1, 2, 3].map((i) => (
              <div key={i} className="flex items-start space-x-4 p-4 bg-card rounded-lg animate-pulse">
                <div className="w-8 h-8 bg-muted rounded-full"></div>
                <div className="flex-1">
                  <div className="h-4 bg-muted rounded mb-2"></div>
                  <div className="h-3 bg-muted rounded w-3/4"></div>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="bg-secondary">
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="text-xl font-semibold text-white">
            Atividades Recentes
          </CardTitle>
          <Button variant="ghost" size="sm" className="text-accent hover:text-accent/80">
            Ver todas
            <ArrowRight className="ml-1 h-4 w-4" />
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {safeActivities && safeActivities.length > 0 ? (
            safeActivities.map((activity: any) => {
              const IconComponent = getIcon(activity.action);
              const colors = getColors(activity.status);
              
              return (
                <div 
                  key={activity.id} 
                  className="flex items-start space-x-4 p-4 bg-card rounded-lg"
                >
                  <div className={`w-8 h-8 ${colors.bg} rounded-full flex items-center justify-center flex-shrink-0`}>
                    <IconComponent className={`${colors.text} text-sm`} size={16} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between">
                      <p className="text-white font-medium">
                        {activity.title || 'Atividade sem título'}
                      </p>
                      <span className="text-xs text-muted-foreground">
                        há poucos minutos
                      </span>
                    </div>
                    
                    <div className="text-sm text-muted-foreground mt-1">
                      {activity.user && activity.user.firstName && (
                        <span>
                          Por <span className="text-accent">{activity.user.firstName} {activity.user.lastName}</span>
                        </span>
                      )}
                    </div>
                    
                    <div className="flex items-center mt-2">
                      <Badge className={`text-xs border-0 mr-2 ${colors.badge}`}>
                        {getStatusText(activity.status)}
                      </Badge>
                    </div>
                  </div>
                </div>
              );
            })
          ) : (
            <div className="text-center py-8">
              <p className="text-muted-foreground">Nenhuma atividade recente</p>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}