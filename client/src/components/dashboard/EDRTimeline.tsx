import { Shield, AlertTriangle, XCircle } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useQuery } from '@tanstack/react-query';
import { useI18n } from '@/hooks/useI18n';

interface EDREvent {
  id: string;
  type: 'blocked' | 'detected' | 'failed';
  title: string;
  endpoint: string;
  process: string;
  latency?: string;
  timestamp: string;
}

export function EDRTimeline() {
  const { t } = useI18n();

  const { data: edrEvents, isLoading } = useQuery<EDREvent[]>({
    queryKey: ['/api/dashboard/edr-events'],
    refetchInterval: 30000,
  });

  const getEventIcon = (type: string) => {
    switch (type) {
      case 'blocked':
        return Shield;
      case 'detected':
        return AlertTriangle;
      case 'failed':
        return XCircle;
      default:
        return Shield;
    }
  };

  const getEventColor = (type: string) => {
    switch (type) {
      case 'blocked':
        return {
          bg: 'bg-green-500/20',
          text: 'text-green-500',
          badge: 'bg-green-500/20 text-green-500'
        };
      case 'detected':
        return {
          bg: 'bg-yellow-500/20',
          text: 'text-yellow-500',
          badge: 'bg-yellow-500/20 text-yellow-500'
        };
      case 'failed':
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

  const getStatusLabel = (type: string) => {
    switch (type) {
      case 'blocked':
        return 'Bloqueado';
      case 'detected':
        return 'Detectado';
      case 'failed':
        return 'Não detectado';
      default:
        return type;
    }
  };

  return (
    <Card className="bg-secondary" data-testid="edr-timeline">
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="text-xl font-semibold text-white">
            Timeline de Detecção EDR
          </CardTitle>
          <div className="flex items-center space-x-2">
            <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
            <span className="text-xs text-muted-foreground">Tempo real</span>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <div className="space-y-3 animate-pulse">
            {[...Array(3)].map((_, i) => (
              <div key={i} className="flex items-start space-x-3 p-3 rounded-lg bg-muted">
                <div className="w-8 h-8 bg-muted-foreground/20 rounded"></div>
                <div className="flex-1 space-y-2">
                  <div className="h-4 bg-muted-foreground/20 rounded w-3/4"></div>
                  <div className="h-3 bg-muted-foreground/20 rounded w-1/2"></div>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="space-y-4" data-testid="edr-events">
            {edrEvents?.map((event) => {
            const IconComponent = getEventIcon(event.type);
            const colors = getEventColor(event.type);
            
            return (
              <div 
                key={event.id} 
                className="flex items-center space-x-4 p-3 bg-card rounded-lg"
                data-testid={`edr-event-${event.id}`}
              >
                <div className={`w-10 h-10 ${colors.bg} rounded-full flex items-center justify-center`}>
                  <IconComponent className={colors.text} size={20} />
                </div>
                <div className="flex-1">
                  <div className="flex items-center justify-between">
                    <span className="font-medium text-white" data-testid={`event-title-${event.id}`}>
                      {event.title}
                    </span>
                    <span className="text-xs text-muted-foreground" data-testid={`event-time-${event.id}`}>
                      {event.timestamp}
                    </span>
                  </div>
                  <p className="text-sm text-muted-foreground mt-1" data-testid={`event-details-${event.id}`}>
                    Endpoint: {event.endpoint} | Processo: {event.process}
                  </p>
                  <div className="flex items-center mt-1">
                    <Badge 
                      className={`text-xs border-0 mr-2 ${colors.badge}`}
                      data-testid={`event-status-${event.id}`}
                    >
                      {getStatusLabel(event.type)}
                    </Badge>
                    <span className="text-xs text-muted-foreground" data-testid={`event-latency-${event.id}`}>
                      {event.latency ? `Latência: ${event.latency}` : 'Timeout'}
                    </span>
                  </div>
                </div>
              </div>
            );
          }) || []}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
