import { Shield, AlertTriangle, XCircle } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
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

  // Mock EDR events - in real app this would come from WebSocket or API
  const edrEvents: EDREvent[] = [
    {
      id: '1',
      type: 'blocked',
      title: 'Malware Detected',
      endpoint: 'WS-LAB-001',
      process: 'suspicious.exe',
      latency: '125ms',
      timestamp: '14:32:15'
    },
    {
      id: '2',
      type: 'detected',
      title: 'Suspicious Activity',
      endpoint: 'WS-LAB-003',
      process: 'powershell.exe',
      latency: '2.3s',
      timestamp: '14:28:42'
    },
    {
      id: '3',
      type: 'failed',
      title: 'Detection Failed',
      endpoint: 'WS-LAB-005',
      process: 'mimikatz.exe',
      latency: 'Timeout',
      timestamp: '14:25:18'
    }
  ];

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
        <div className="space-y-4" data-testid="edr-events">
          {edrEvents.map((event) => {
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
          })}
        </div>
      </CardContent>
    </Card>
  );
}
