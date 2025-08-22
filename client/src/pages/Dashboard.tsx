import { useState } from 'react';
import { Download, Calendar } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { MainLayout } from '@/components/layout/MainLayout';
import { MetricsGrid } from '@/components/dashboard/MetricsGrid';
import { AttackSurfaceHeatmap } from '@/components/dashboard/AttackSurfaceHeatmap';
import { EDRTimeline } from '@/components/dashboard/EDRTimeline';
import { JourneyResults } from '@/components/dashboard/JourneyResults';
import { CollectorStatus } from '@/components/dashboard/CollectorStatus';
import { ActivityFeed } from '@/components/dashboard/ActivityFeed';
import { CollectorEnrollment } from '@/components/collectors/CollectorEnrollment';
import { JourneyForm } from '@/components/journeys/JourneyForm';
import { useI18n } from '@/hooks/useI18n';
import { useWebSocket } from '@/hooks/useWebSocket';
import { useLocation } from 'wouter';

export default function Dashboard() {
  const { t } = useI18n();
  const [, setLocation] = useLocation();
  const [showCollectorForm, setShowCollectorForm] = useState(false);
  const [showJourneyForm, setShowJourneyForm] = useState(false);
  const { isConnected } = useWebSocket();

  const handleTabChange = (tab: string) => {
    if (tab === 'dashboard') return;
    setLocation(`/${tab}`);
  };

  const handleNewJourney = () => {
    setShowJourneyForm(true);
  };

  const handleAddCollector = () => {
    setShowCollectorForm(true);
  };

  return (
    <>
      <MainLayout
        activeTab="dashboard"
        onTabChange={handleTabChange}
        onNewJourney={handleNewJourney}
        onAddCollector={handleAddCollector}
      >
        {/* Dashboard Header */}
        <div className="mb-8" data-testid="dashboard-header">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-3xl font-bold text-white mb-2">
                {t('dashboard.title')}
              </h2>
              <p className="text-muted-foreground">
                {t('dashboard.subtitle')}
              </p>
              {/* Connection Status */}
              <div className="flex items-center mt-2">
                <div className={`w-2 h-2 rounded-full mr-2 ${isConnected ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`}></div>
                <span className="text-xs text-muted-foreground">
                  {isConnected ? 'Conectado' : 'Desconectado'}
                </span>
              </div>
            </div>
            <div className="flex items-center space-x-3">
              <Select defaultValue="24h" data-testid="time-range-selector">
                <SelectTrigger className="w-40">
                  <Calendar className="mr-2 h-4 w-4" />
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="24h">Últimas 24h</SelectItem>
                  <SelectItem value="week">Última semana</SelectItem>
                  <SelectItem value="month">Último mês</SelectItem>
                </SelectContent>
              </Select>
              <Button 
                className="bg-accent hover:bg-accent/90"
                data-testid="export-button"
              >
                <Download className="mr-2 h-4 w-4" />
                {t('dashboard.export')}
              </Button>
            </div>
          </div>
        </div>

        {/* Metrics Grid */}
        <MetricsGrid />

        {/* Charts Row */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <AttackSurfaceHeatmap />
          <EDRTimeline />
        </div>

        {/* Journey Results */}
        <JourneyResults />

        {/* Collector Status */}
        <CollectorStatus />

        {/* Recent Activities */}
        <ActivityFeed />
      </MainLayout>

      {/* Modals */}
      {showCollectorForm && (
        <CollectorEnrollment 
          isOpen={showCollectorForm}
          onClose={() => setShowCollectorForm(false)}
        />
      )}

      {showJourneyForm && (
        <JourneyForm
          isOpen={showJourneyForm}
          onClose={() => setShowJourneyForm(false)}
        />
      )}
    </>
  );
}
