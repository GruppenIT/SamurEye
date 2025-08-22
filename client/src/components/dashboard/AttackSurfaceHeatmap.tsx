import { RefreshCw } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useQuery } from '@tanstack/react-query';
import { useI18n } from '@/hooks/useI18n';

interface HeatmapCell {
  severity: 'critical' | 'high' | 'medium' | 'low' | 'info' | 'none';
  service: string;
  port: string;
  count: number;
  tooltip: string;
}

export function AttackSurfaceHeatmap() {
  const { t } = useI18n();

  const { data: heatmapData, isLoading, refetch } = useQuery<HeatmapCell[]>({
    queryKey: ['/api/dashboard/attack-surface'],
    refetchInterval: 60000,
  });

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'critical':
        return 'bg-red-500/90 hover:bg-red-500';
      case 'high':
        return 'bg-orange-500/70 hover:bg-orange-500';
      case 'medium':
        return 'bg-yellow-500/60 hover:bg-yellow-500';
      case 'low':
        return 'bg-green-500/40 hover:bg-green-500';
      case 'info':
        return 'bg-blue-500/40 hover:bg-blue-500';
      default:
        return 'bg-gray-700 hover:bg-gray-600';
    }
  };

  return (
    <Card className="bg-secondary" data-testid="attack-surface-heatmap">
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="text-xl font-semibold text-white">
            Mapa de Calor - Superfície de Ataque
          </CardTitle>
          <div className="flex items-center space-x-2">
            <Badge variant="secondary" className="text-xs bg-muted">
              Interno
            </Badge>
            <Button 
              size="sm" 
              className="text-xs bg-accent hover:bg-accent/90"
              onClick={() => refetch()}
              disabled={isLoading}
              data-testid="refresh-heatmap"
            >
              <RefreshCw className={`mr-1 h-3 w-3 ${isLoading ? 'animate-spin' : ''}`} />
              {t('common.update')}
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <div className="animate-pulse">
            <div className="grid grid-cols-8 gap-1 mb-4">
              {[...Array(8)].map((_, i) => (
                <div key={i} className="w-full h-8 bg-muted rounded"></div>
              ))}
            </div>
          </div>
        ) : (
          <>
            {/* Heatmap Grid */}
            <div className="grid grid-cols-8 gap-1 mb-4" data-testid="heatmap-grid">
              {heatmapData?.map((cell, index) => (
            <div
              key={index}
              className={`w-full h-8 rounded cursor-pointer transition-all duration-200 hover:scale-110 hover:z-10 ${getSeverityColor(cell.severity)}`}
              title={cell.tooltip}
              data-testid={`heatmap-cell-${index}`}
            />
          ))}
        </div>
        
        {/* Legend */}
        <div className="flex items-center justify-between text-xs">
          <span className="text-muted-foreground">Menos crítico</span>
          <div className="flex items-center space-x-1" data-testid="heatmap-legend">
            <div className="w-3 h-3 bg-green-500/30 rounded"></div>
            <div className="w-3 h-3 bg-yellow-500/50 rounded"></div>
            <div className="w-3 h-3 bg-orange-500/70 rounded"></div>
            <div className="w-3 h-3 bg-red-500/90 rounded"></div>
          </div>
          <span className="text-muted-foreground">Mais crítico</span>
        </div>

        {/* Service Details */}
        <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
          {heatmapData.filter(cell => cell.severity !== 'none').map((cell, index) => (
            <div key={index} className="flex items-center space-x-2 p-2 bg-card rounded">
              <div className={`w-3 h-3 rounded ${getSeverityColor(cell.severity).split(' ')[0]}`}></div>
              <span className="font-medium">{cell.service}</span>
              <span className="text-muted-foreground">{cell.port}</span>
              {cell.count > 0 && (
                <Badge variant="secondary" className="text-xs">
                  {cell.count}
                </Badge>
              )}
            </div>
          )) || []}
        </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
