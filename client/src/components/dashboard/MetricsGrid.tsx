import { Shield, AlertTriangle, Network, ShieldCheck, TrendingUp, TrendingDown } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useQuery } from '@tanstack/react-query';
import { useI18n } from '@/hooks/useI18n';

export function MetricsGrid() {
  const { t } = useI18n();
  const { data: metrics, isLoading } = useQuery({
    queryKey: ['/api/dashboard/metrics'],
    refetchInterval: 30000,
  });

  if (isLoading) {
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        {[...Array(4)].map((_, i) => (
          <Card key={i} className="bg-secondary animate-pulse" data-testid={`metric-skeleton-${i}`}>
            <CardContent className="p-6">
              <div className="h-12 bg-muted rounded mb-4"></div>
              <div className="h-8 bg-muted rounded mb-2"></div>
              <div className="h-4 bg-muted rounded w-3/4"></div>
            </CardContent>
          </Card>
        ))}
      </div>
    );
  }

  const metricCards = [
    {
      title: t('metrics.criticalVulns'),
      value: metrics?.vulnerabilities?.critical || 0,
      icon: Shield,
      color: 'destructive',
      bgColor: 'bg-destructive/20',
      textColor: 'text-destructive',
      trend: '+12%',
      trendDirection: 'up' as const,
      testId: 'critical-vulns'
    },
    {
      title: t('metrics.highVulns'),
      value: metrics?.vulnerabilities?.high || 0,
      icon: AlertTriangle,
      color: 'warning',
      bgColor: 'bg-yellow-500/20',
      textColor: 'text-yellow-500',
      trend: '-5%',
      trendDirection: 'down' as const,
      testId: 'high-vulns'
    },
    {
      title: t('metrics.assetsDiscovered'),
      value: metrics?.assets?.total?.toLocaleString() || '0',
      icon: Network,
      color: 'info',
      bgColor: 'bg-blue-500/20',
      textColor: 'text-blue-500',
      trend: '+3%',
      trendDirection: 'up' as const,
      testId: 'assets-discovered'
    },
    {
      title: t('metrics.detectionRate'),
      value: `${metrics?.edr?.detectionRate || 0}%`,
      icon: ShieldCheck,
      color: 'success',
      bgColor: 'bg-green-500/20',
      textColor: 'text-green-500',
      trend: '+2.1%',
      trendDirection: 'up' as const,
      testId: 'detection-rate'
    }
  ];

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8" data-testid="metrics-grid">
      {metricCards.map((metric, index) => {
        const IconComponent = metric.icon;
        const TrendIcon = metric.trendDirection === 'up' ? TrendingUp : TrendingDown;
        
        return (
          <Card 
            key={index} 
            className="bg-secondary hover:bg-secondary/80 transition-colors cursor-pointer transform hover:scale-105 transition-transform"
            data-testid={`metric-card-${metric.testId}`}
          >
            <CardContent className="p-6">
              <div className="flex items-center justify-between mb-4">
                <div className={`w-12 h-12 ${metric.bgColor} rounded-lg flex items-center justify-center`}>
                  <IconComponent className={`${metric.textColor} text-xl`} size={24} />
                </div>
                <Badge 
                  variant="secondary" 
                  className={`text-xs ${metric.bgColor} ${metric.textColor} border-0`}
                >
                  {index === 0 ? t('status.critical') : 
                   index === 1 ? t('status.high') :
                   index === 2 ? t('status.active') : 'EDR'}
                </Badge>
              </div>
              <div>
                <h3 className="text-2xl font-bold text-white mb-1" data-testid={`metric-value-${metric.testId}`}>
                  {metric.value}
                </h3>
                <p className="text-muted-foreground text-sm" data-testid={`metric-title-${metric.testId}`}>
                  {metric.title}
                </p>
                <div className="flex items-center mt-2">
                  <TrendIcon 
                    className={`${metric.trendDirection === 'up' && index !== 1 ? 'text-green-500' : 
                               metric.trendDirection === 'down' && index === 1 ? 'text-green-500' : 
                               'text-red-500'} text-xs mr-1`} 
                    size={12} 
                  />
                  <span 
                    className={`${metric.trendDirection === 'up' && index !== 1 ? 'text-green-500' : 
                               metric.trendDirection === 'down' && index === 1 ? 'text-green-500' : 
                               'text-red-500'} text-xs`}
                    data-testid={`metric-trend-${metric.testId}`}
                  >
                    {metric.trend} vs semana anterior
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
