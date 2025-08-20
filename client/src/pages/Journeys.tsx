import { useState } from 'react';
import { Play, Plus, Pause, RotateCcw, Globe, Users, Shield, Clock, CheckCircle, XCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MainLayout } from '@/components/layout/MainLayout';
import { JourneyForm } from '@/components/journeys/JourneyForm';
import { CollectorEnrollment } from '@/components/collectors/CollectorEnrollment';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import { useLocation } from 'wouter';
import { useI18n } from '@/hooks/useI18n';
import { useToast } from '@/hooks/use-toast';

export default function Journeys() {
  const { t } = useI18n();
  const { toast } = useToast();
  const [, setLocation] = useLocation();
  const queryClient = useQueryClient();
  const [showJourneyForm, setShowJourneyForm] = useState(false);
  const [showCollectorForm, setShowCollectorForm] = useState(false);

  const { data: journeys, isLoading } = useQuery({
    queryKey: ['/api/journeys'],
    refetchInterval: 30000,
  });

  const startJourneyMutation = useMutation({
    mutationFn: async (journeyId: string) => {
      await apiRequest('POST', `/api/journeys/${journeyId}/start`);
    },
    onSuccess: () => {
      toast({
        title: "Jornada iniciada",
        description: "A jornada foi iniciada com sucesso",
      });
      queryClient.invalidateQueries({ queryKey: ['/api/journeys'] });
    },
    onError: (error) => {
      toast({
        title: "Erro",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  const handleTabChange = (tab: string) => {
    if (tab === 'journeys') return;
    setLocation(tab === 'dashboard' ? '/' : `/${tab}`);
  };

  const handleNewJourney = () => {
    setShowJourneyForm(true);
  };

  const handleAddCollector = () => {
    setShowCollectorForm(true);
  };

  const getJourneyIcon = (type: string) => {
    switch (type) {
      case 'attack_surface':
        return Globe;
      case 'ad_hygiene':
        return Users;
      case 'edr_testing':
        return Shield;
      default:
        return Play;
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'completed':
        return CheckCircle;
      case 'failed':
        return XCircle;
      case 'running':
        return Play;
      case 'pending':
        return Clock;
      default:
        return Clock;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed':
        return 'bg-green-500/20 text-green-500';
      case 'failed':
        return 'bg-red-500/20 text-red-500';
      case 'running':
        return 'bg-blue-500/20 text-blue-500';
      case 'pending':
        return 'bg-yellow-500/20 text-yellow-500';
      default:
        return 'bg-gray-500/20 text-gray-500';
    }
  };

  const getJourneyTypeLabel = (type: string) => {
    switch (type) {
      case 'attack_surface':
        return 'Attack Surface';
      case 'ad_hygiene':
        return 'Higiene AD/LDAP';
      case 'edr_testing':
        return 'EDR/AV Testing';
      default:
        return type;
    }
  };

  const formatDuration = (startedAt: string, completedAt: string) => {
    if (!startedAt || !completedAt) return '--';
    const start = new Date(startedAt);
    const end = new Date(completedAt);
    const diffMs = end.getTime() - start.getTime();
    const diffMins = Math.floor(diffMs / (1000 * 60));
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    
    if (diffHours > 0) {
      return `${diffHours}h ${diffMins % 60}min`;
    }
    return `${diffMins}min`;
  };

  const journeysByType = journeys?.reduce((acc: any, journey: any) => {
    const type = journey.type;
    if (!acc[type]) acc[type] = [];
    acc[type].push(journey);
    return acc;
  }, {}) || {};

  return (
    <>
      <MainLayout
        activeTab="journeys"
        onTabChange={handleTabChange}
        onNewJourney={handleNewJourney}
        onAddCollector={handleAddCollector}
      >
        <div className="space-y-6" data-testid="journeys-page">
          {/* Header */}
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-3xl font-bold text-white mb-2">Jornadas de Teste</h2>
              <p className="text-muted-foreground">
                Gerencie e monitore suas jornadas de simulação de ataques
              </p>
            </div>
            <Button
              className="bg-accent hover:bg-accent/90"
              onClick={handleNewJourney}
              data-testid="new-journey-button"
            >
              <Plus className="mr-2 h-4 w-4" />
              Nova Jornada
            </Button>
          </div>

          {/* Journey Types Tabs */}
          <Tabs defaultValue="all" className="w-full">
            <TabsList className="grid w-full grid-cols-4">
              <TabsTrigger value="all">Todas</TabsTrigger>
              <TabsTrigger value="attack_surface">Attack Surface</TabsTrigger>
              <TabsTrigger value="ad_hygiene">AD/LDAP</TabsTrigger>
              <TabsTrigger value="edr_testing">EDR/AV</TabsTrigger>
            </TabsList>

            <TabsContent value="all" className="space-y-4">
              {isLoading ? (
                <div className="space-y-4">
                  {[...Array(3)].map((_, i) => (
                    <Card key={i} className="bg-secondary animate-pulse">
                      <CardContent className="p-6">
                        <div className="h-4 bg-muted rounded mb-4"></div>
                        <div className="h-3 bg-muted rounded mb-2"></div>
                        <div className="h-3 bg-muted rounded w-3/4"></div>
                      </CardContent>
                    </Card>
                  ))}
                </div>
              ) : (
                <div className="space-y-4">
                  {journeys?.map((journey: any) => {
                    const IconComponent = getJourneyIcon(journey.type);
                    const StatusIcon = getStatusIcon(journey.status);
                    
                    return (
                      <Card key={journey.id} className="bg-secondary hover:bg-secondary/80 transition-colors">
                        <CardContent className="p-6">
                          <div className="flex items-center justify-between">
                            <div className="flex items-center space-x-4">
                              <div className="w-12 h-12 bg-accent/20 rounded-lg flex items-center justify-center">
                                <IconComponent className="text-accent" size={24} />
                              </div>
                              <div>
                                <h3 className="text-lg font-semibold text-white">{journey.name}</h3>
                                <p className="text-sm text-muted-foreground">
                                  {getJourneyTypeLabel(journey.type)}
                                </p>
                                <div className="flex items-center space-x-4 mt-2">
                                  <span className="text-xs text-muted-foreground">
                                    Criada por: {journey.createdBy?.firstName} {journey.createdBy?.lastName}
                                  </span>
                                  {journey.collector && (
                                    <span className="text-xs text-muted-foreground">
                                      Collector: {journey.collector.name}
                                    </span>
                                  )}
                                  {journey.completedAt && journey.startedAt && (
                                    <span className="text-xs text-muted-foreground">
                                      Duração: {formatDuration(journey.startedAt, journey.completedAt)}
                                    </span>
                                  )}
                                </div>
                              </div>
                            </div>
                            
                            <div className="flex items-center space-x-3">
                              <div className="text-right">
                                <Badge className={`mb-2 border-0 ${getStatusColor(journey.status)}`}>
                                  <StatusIcon className="mr-1" size={12} />
                                  {journey.status.toUpperCase()}
                                </Badge>
                                <p className="text-xs text-muted-foreground">
                                  {new Date(journey.createdAt).toLocaleDateString('pt-BR')}
                                </p>
                              </div>
                              
                              <div className="flex items-center space-x-2">
                                {journey.status === 'pending' && (
                                  <Button
                                    size="sm"
                                    className="bg-green-600 hover:bg-green-700"
                                    onClick={() => startJourneyMutation.mutate(journey.id)}
                                    disabled={startJourneyMutation.isPending}
                                    data-testid={`start-journey-${journey.id}`}
                                  >
                                    <Play className="h-4 w-4" />
                                  </Button>
                                )}
                                {journey.status === 'running' && (
                                  <Button size="sm" variant="outline" disabled>
                                    <Pause className="h-4 w-4" />
                                  </Button>
                                )}
                                {(journey.status === 'completed' || journey.status === 'failed') && (
                                  <Button size="sm" variant="outline">
                                    <RotateCcw className="h-4 w-4" />
                                  </Button>
                                )}
                              </div>
                            </div>
                          </div>
                          
                          {/* Journey Results Preview */}
                          {journey.results && (
                            <div className="mt-4 p-4 bg-card rounded-lg">
                              <h4 className="text-sm font-medium text-white mb-2">Resultados:</h4>
                              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                                {Object.entries(journey.results).slice(0, 4).map(([key, value]: [string, any]) => (
                                  <div key={key} className="text-center">
                                    <div className="text-lg font-semibold text-accent">{value}</div>
                                    <div className="text-xs text-muted-foreground">{key}</div>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}
                        </CardContent>
                      </Card>
                    );
                  })}
                </div>
              )}
            </TabsContent>

            {/* Journey Type Specific Tabs */}
            {Object.entries(journeysByType).map(([type, typeJourneys]) => (
              <TabsContent key={type} value={type} className="space-y-4">
                <div className="space-y-4">
                  {(typeJourneys as any[]).map((journey: any) => {
                    const IconComponent = getJourneyIcon(journey.type);
                    const StatusIcon = getStatusIcon(journey.status);
                    
                    return (
                      <Card key={journey.id} className="bg-secondary hover:bg-secondary/80 transition-colors">
                        <CardContent className="p-6">
                          <div className="flex items-center justify-between">
                            <div className="flex items-center space-x-4">
                              <div className="w-12 h-12 bg-accent/20 rounded-lg flex items-center justify-center">
                                <IconComponent className="text-accent" size={24} />
                              </div>
                              <div>
                                <h3 className="text-lg font-semibold text-white">{journey.name}</h3>
                                <p className="text-sm text-muted-foreground">
                                  {getJourneyTypeLabel(journey.type)}
                                </p>
                              </div>
                            </div>
                            
                            <div className="flex items-center space-x-3">
                              <Badge className={`border-0 ${getStatusColor(journey.status)}`}>
                                <StatusIcon className="mr-1" size={12} />
                                {journey.status.toUpperCase()}
                              </Badge>
                              
                              {journey.status === 'pending' && (
                                <Button
                                  size="sm"
                                  className="bg-green-600 hover:bg-green-700"
                                  onClick={() => startJourneyMutation.mutate(journey.id)}
                                  disabled={startJourneyMutation.isPending}
                                >
                                  <Play className="h-4 w-4" />
                                </Button>
                              )}
                            </div>
                          </div>
                        </CardContent>
                      </Card>
                    );
                  })}
                </div>
              </TabsContent>
            ))}
          </Tabs>
        </div>
      </MainLayout>

      {/* Modals */}
      {showJourneyForm && (
        <JourneyForm
          isOpen={showJourneyForm}
          onClose={() => setShowJourneyForm(false)}
        />
      )}

      {showCollectorForm && (
        <CollectorEnrollment 
          isOpen={showCollectorForm}
          onClose={() => setShowCollectorForm(false)}
        />
      )}
    </>
  );
}
