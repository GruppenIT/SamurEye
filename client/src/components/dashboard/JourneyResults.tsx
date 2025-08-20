import { Globe, Users, Shield, ExternalLink } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useQuery } from '@tanstack/react-query';
import { useI18n } from '@/hooks/useI18n';

export function JourneyResults() {
  const { t } = useI18n();
  const { data: metrics } = useQuery({
    queryKey: ['/api/dashboard/metrics'],
    refetchInterval: 30000,
  });

  const journeyData = [
    {
      id: 'attack-surface',
      title: t('journey.attackSurface'),
      icon: Globe,
      iconColor: 'text-blue-500',
      iconBg: 'bg-blue-500/20',
      lastExecution: '2h ' + t('time.ago'),
      status: 'success',
      results: {
        hostsScanned: 847,
        servicesExposed: 2341,
        criticalCves: metrics?.vulnerabilities?.critical || 23,
        internetFacing: 127
      },
      scanType: 'Escaneamento interno via collector'
    },
    {
      id: 'ad-hygiene',
      title: t('journey.adHygiene'),
      icon: Users,
      iconColor: 'text-blue-400',
      iconBg: 'bg-blue-400/20',
      lastExecution: '6h ' + t('time.ago'),
      status: 'warning',
      results: {
        inactiveAccounts: 142,
        orphanAdmins: 7,
        weakPolicies: 28,
        slaExpiring: 15
      },
      scanType: 'Análise contínua de domínio'
    },
    {
      id: 'edr-testing',
      title: t('journey.edrTesting'),
      icon: Shield,
      iconColor: 'text-green-500',
      iconBg: 'bg-green-500/20',
      lastExecution: '30min ' + t('time.ago'),
      status: 'success',
      results: {
        detectionRate: `${metrics?.edr?.detectionRate || 94.2}%`,
        blockRate: `${metrics?.edr?.blockRate || 87.8}%`,
        avgLatency: `${metrics?.edr?.avgLatency || 1.2}s`,
        detectionFailures: 4
      },
      scanType: 'Testando 23 endpoints ativos'
    }
  ];

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'success':
        return 'bg-green-500';
      case 'warning':
        return 'bg-yellow-500';
      case 'error':
        return 'bg-red-500';
      default:
        return 'bg-blue-500';
    }
  };

  const getResultLabels = (journeyId: string) => {
    switch (journeyId) {
      case 'attack-surface':
        return {
          hostsScanned: 'Hosts Varridos',
          servicesExposed: 'Serviços Expostos',
          criticalCves: 'CVEs Críticas',
          internetFacing: 'Internet-facing'
        };
      case 'ad-hygiene':
        return {
          inactiveAccounts: 'Contas Inativas',
          orphanAdmins: 'Admins Órfãos',
          weakPolicies: 'Políticas Fracas',
          slaExpiring: 'SLA Vencendo'
        };
      case 'edr-testing':
        return {
          detectionRate: 'Taxa Detecção',
          blockRate: 'Taxa Bloqueio',
          avgLatency: 'Latência Média',
          detectionFailures: 'Falhas Detecção'
        };
      default:
        return {};
    }
  };

  const getResultColor = (key: string, value: any) => {
    if (key.includes('critical') || key.includes('orphan') || key.includes('failure') || key.includes('sla')) {
      return 'text-red-500';
    }
    if (key.includes('weak') || key.includes('inactive')) {
      return 'text-yellow-500';
    }
    if (key.includes('rate') || key.includes('detection')) {
      return 'text-green-500';
    }
    return 'text-white';
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8" data-testid="journey-results">
      {journeyData.map((journey) => {
        const IconComponent = journey.icon;
        const labels = getResultLabels(journey.id);
        
        return (
          <Card key={journey.id} className="bg-secondary" data-testid={`journey-card-${journey.id}`}>
            <CardContent className="p-6">
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center space-x-3">
                  <div className={`w-10 h-10 ${journey.iconBg} rounded-lg flex items-center justify-center`}>
                    <IconComponent className={journey.iconColor} size={20} />
                  </div>
                  <div>
                    <h3 className="font-semibold text-white" data-testid={`journey-title-${journey.id}`}>
                      {journey.title}
                    </h3>
                    <p className="text-xs text-muted-foreground" data-testid={`journey-execution-${journey.id}`}>
                      {t('journey.lastExecution')}: {journey.lastExecution}
                    </p>
                  </div>
                </div>
                <Button variant="ghost" size="sm" data-testid={`journey-link-${journey.id}`}>
                  <ExternalLink className={journey.iconColor} size={16} />
                </Button>
              </div>
              
              <div className="space-y-3">
                {Object.entries(journey.results).map(([key, value]) => (
                  <div key={key} className="flex items-center justify-between">
                    <span className="text-sm text-muted-foreground">
                      {labels[key as keyof typeof labels] || key}
                    </span>
                    <span className={`font-semibold ${getResultColor(key, value)}`} data-testid={`journey-result-${journey.id}-${key}`}>
                      {typeof value === 'number' ? value.toLocaleString() : value}
                    </span>
                  </div>
                ))}
              </div>
              
              <div className="mt-4 pt-4 border-t border-border">
                <div className="flex items-center space-x-2">
                  <div className={`w-2 h-2 rounded-full ${getStatusColor(journey.status)} ${journey.status === 'success' ? 'animate-pulse' : ''}`}></div>
                  <span className="text-xs text-muted-foreground" data-testid={`journey-scan-type-${journey.id}`}>
                    {journey.scanType}
                  </span>
                </div>
              </div>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
