import { Play, Check, AlertTriangle, Shield, ArrowRight } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useQuery } from '@tanstack/react-query';
import { useI18n } from '@/hooks/useI18n';

export function RecentActivities() {
  const { t } = useI18n();
  
  const { data: activities, isLoading } = useQuery({
    queryKey: ['/api/activities'],
    refetchInterval: 30000,
  });

  // Mock activities for demo if no data available
  const mockActivities = [
    {
      id: '1',
      action: 'journey_started',
      title: 'Nova jornada Attack Surface iniciada',
      user: { firstName: 'João', lastName: 'Silva' },
      metadata: { journeyName: 'Attack Surface', target: '192.168.100.0/24', collector: 'vlxsam04' },
      timestamp: new Date(Date.now() - 2 * 60 * 1000).toISOString(), // 2 minutes ago
      status: 'running'
    },
    {
      id: '2',
      action: 'journey_completed',
      title: 'Jornada EDR Testing concluída',
      user: { firstName: 'João', lastName: 'Silva' },
      metadata: { endpointsTested: 23, detectionRate: 94.2, failures: 4 },
      timestamp: new Date(Date.now() - 30 * 60 * 1000).toISOString(), // 30 minutes ago
      status: 'completed'
    },
    {
      id: '3',
      action: 'collector_offline',
      title: 'Coletor collector-branch desconectado',
      user: { firstName: 'Sistema', lastName: '' },
      metadata: { lastSeen: '14:32', reason: 'Timeout de conexão' },
      timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(), // 2 hours ago
      status: 'offline'
    },
    {
      id: '4',
      action: 'vulnerabilities_found',
      title: '23 vulnerabilidades críticas descobertas',
      user: { firstName: 'Sistema', lastName: '' },
      metadata: { cves: ['CVE-2024-1234', 'CVE-2024-5678'], action: 'Requer ação imediata' },
      timestamp: new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString(), // 3 hours ago
      status: 'critical'
    }
  ];

  const displayActivities = activities || mockActivities;

  const getActivityIcon = (action: string) => {
    switch (action) {
      case 'journey_started':
        return Play;
      case 'journey_completed':
        return Check;
      case 'collector_offline':
        return AlertTriangle;
      case 'vulnerabilities_found':
        return Shield;
      default:
        return Play;
    }
  };

  const getActivityColor = (status: string) => {
    switch (status) {
      case 'running':
        return {
          bg: 'bg-blue-500/20',
          text: 'text-blue-500',
          badge: 'bg-blue-500/20 text-blue-500'
        };
      case 'completed':
        return {
          bg: 'bg-green-500/20',
          text: 'text-green-500',
          badge: 'bg-green-500/20 text-green-500'
        };
      case 'offline':
        return {
          bg: 'bg-yellow-500/20',
          text: 'text-yellow-500',
          badge: 'bg-red-500/20 text-red-500'
        };
      case 'critical':
        return {
          bg: 'bg-red-500/20',
          text: 'text-red-500',
          badge: 'bg-red-500/20 text-red-500'
        };
      default:
        return {
          bg: 'bg-gray-500/20',
          text: 'text-gray-500',
          badge: 'bg-gray-500/20 text-gray-500'
        };
    }
  };

  const getStatusLabel = (status: string) => {
    switch (status) {
      case 'running':
        return 'EM EXECUÇÃO';
      case 'completed':
        return 'CONCLUÍDA';
      case 'offline':
        return 'OFFLINE';
      case 'critical':
        return 'CRÍTICO';
      default:
        return status.toUpperCase();
    }
  };

  const formatTimeAgo = (timestamp: string) => {
    const now = new Date();
    const time = new Date(timestamp);
    const diffMs = now.getTime() - time.getTime();
    const diffMins = Math.floor(diffMs / (1000 * 60));
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));

    if (diffMins < 60) {
      return `há ${diffMins} ${diffMins === 1 ? 'minuto' : 'minutos'}`;
    } else {
      return `há ${diffHours} ${diffHours === 1 ? 'hora' : 'horas'}`;
    }
  };

  if (isLoading) {
    return (
      <Card className="bg-secondary">
        <CardHeader>
          <CardTitle className="text-xl font-semibold text-white">Atividades Recentes</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {[...Array(4)].map((_, i) => (
              <div key={i} className="flex items-start space-x-4 p-4 bg-card rounded-lg animate-pulse">
                <div className="w-8 h-8 bg-muted rounded-full"></div>
                <div className="flex-1">
                  <div className="h-4 bg-muted rounded mb-2"></div>
                  <div className="h-3 bg-muted rounded w-3/4 mb-2"></div>
                  <div className="h-3 bg-muted rounded w-1/2"></div>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="bg-secondary" data-testid="recent-activities">
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="text-xl font-semibold text-white">
            Atividades Recentes
          </CardTitle>
          <Button variant="ghost" size="sm" className="text-accent hover:text-accent/80" data-testid="view-all-activities">
            {t('common.viewAll')}
            <ArrowRight className="ml-1 h-4 w-4" />
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-4" data-testid="activities-list">
          {displayActivities.map((activity: any) => {
            const IconComponent = getActivityIcon(activity.action);
            const colors = getActivityColor(activity.status);
            
            return (
              <div 
                key={activity.id} 
                className="flex items-start space-x-4 p-4 bg-card rounded-lg"
                data-testid={`activity-${activity.id}`}
              >
                <div className={`w-8 h-8 ${colors.bg} rounded-full flex items-center justify-center flex-shrink-0`}>
                  <IconComponent className={`${colors.text} text-sm`} size={16} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between">
                    <p className="text-white font-medium" data-testid={`activity-title-${activity.id}`}>
                      {activity.title}
                    </p>
                    <span className="text-xs text-muted-foreground" data-testid={`activity-time-${activity.id}`}>
                      {formatTimeAgo(activity.timestamp)}
                    </span>
                  </div>
                  
                  {activity.metadata && (
                    <p className="text-sm text-muted-foreground mt-1" data-testid={`activity-details-${activity.id}`}>
                      {activity.action === 'journey_started' && (
                        <>
                          Iniciada por <span className="text-accent">{activity.user.firstName} {activity.user.lastName}</span>
                          {activity.metadata.target && <> • Target: <span className="text-white">{activity.metadata.target}</span></>}
                          {activity.metadata.collector && <> • Collector: <span className="text-white">{activity.metadata.collector}</span></>}
                        </>
                      )}
                      {activity.action === 'journey_completed' && (
                        <>
                          {activity.metadata.endpointsTested} endpoints testados • {activity.metadata.detectionRate}% taxa de detecção
                          • {activity.metadata.failures} falhas identificadas
                        </>
                      )}
                      {activity.action === 'collector_offline' && (
                        <>
                          Última comunicação: {activity.metadata.lastSeen} • Verificar conectividade de rede
                        </>
                      )}
                      {activity.action === 'vulnerabilities_found' && (
                        <>
                          Jornada Attack Surface • {activity.metadata.cves?.join(', ')}
                          • {activity.metadata.action}
                        </>
                      )}
                    </p>
                  )}
                  
                  <div className="flex items-center mt-2">
                    <Badge className={`text-xs border-0 mr-2 ${colors.badge}`} data-testid={`activity-status-${activity.id}`}>
                      {getStatusLabel(activity.status)}
                    </Badge>
                    <span className="text-xs text-muted-foreground" data-testid={`activity-meta-${activity.id}`}>
                      {activity.action === 'journey_started' && 'ETA: 15 minutos'}
                      {activity.action === 'journey_completed' && 'Duração: 12 minutos'}
                      {activity.action === 'collector_offline' && activity.metadata.reason}
                      {activity.action === 'vulnerabilities_found' && 'Enviado para SIEM'}
                    </span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
}
