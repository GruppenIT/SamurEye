import { RefreshCw } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
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

  // Mock heatmap data - in real app this would come from API
  const heatmapData: HeatmapCell[] = [
    { severity: 'critical', service: 'SSH', port: '22/TCP', count: 15, tooltip: 'SSH - 22/TCP: 15 vulnerabilidades críticas' },
    { severity: 'high', service: 'HTTP', port: '80/TCP', count: 8, tooltip: 'HTTP - 80/TCP: 8 vulnerabilidades altas' },
    { severity: 'low', service: 'DNS', port: '53/UDP', count: 2, tooltip: 'DNS - 53/UDP: 2 vulnerabilidades baixas' },
    { severity: 'critical', service: 'RDP', port: '3389/TCP', count: 22, tooltip: 'RDP - 3389/TCP: 22 vulnerabilidades críticas' },
    { severity: 'medium', service: 'HTTPS', port: '443/TCP', count: 5, tooltip: 'HTTPS - 443/TCP: 5 vulnerabilidades médias' },
    { severity: 'low', service: 'FTP', port: '21/TCP', count: 1, tooltip: 'FTP - 21/TCP: 1 vulnerabilidade baixa' },
    { severity: 'none', service: 'Unknown', port: 'N/A', count: 0, tooltip: 'Sem dados' },
    { severity: 'info', service: 'SMTP', port: '25/TCP', count: 0, tooltip: 'SMTP - 25/TCP: Informativo' },
  ];

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
              data-testid="refresh-heatmap"
            >
              <RefreshCw className="mr-1 h-3 w-3" />
              {t('common.update')}
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {/* Heatmap Grid */}
        <div className="grid grid-cols-8 gap-1 mb-4" data-testid="heatmap-grid">
          {heatmapData.map((cell, index) => (
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
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
