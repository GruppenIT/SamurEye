import { useState } from 'react';
import { Plus, Wifi, WifiOff, Clock, RefreshCw, Terminal, Package } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MainLayout } from '@/components/layout/MainLayout';
import { CollectorEnrollment } from '@/components/collectors/CollectorEnrollment';
import { JourneyForm } from '@/components/journeys/JourneyForm';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import { useLocation } from 'wouter';
import { useI18n } from '@/hooks/useI18n';
import { useToast } from '@/hooks/use-toast';

export default function Collectors() {
  const { t } = useI18n();
  const { toast } = useToast();
  const [, setLocation] = useLocation();
  const queryClient = useQueryClient();
  const [showCollectorForm, setShowCollectorForm] = useState(false);
  const [showJourneyForm, setShowJourneyForm] = useState(false);

  const { data: collectors, isLoading } = useQuery({
    queryKey: ['/api/collectors'],
    refetchInterval: 10000,
  });

  const regenerateTokenMutation = useMutation({
    mutationFn: async (collectorId: string) => {
      const response = await apiRequest('POST', `/api/collectors/${collectorId}/regenerate-token`);
      return response.json();
    },
    onSuccess: () => {
      toast({
        title: "Token regenerado",
        description: "Novo token de enrollment gerado com sucesso",
      });
      queryClient.invalidateQueries({ queryKey: ['/api/collectors'] });
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
    if (tab === 'collectors') return;
    setLocation(tab === 'dashboard' ? '/' : `/${tab}`);
  };

  const handleNewJourney = () => {
    setShowJourneyForm(true);
  };

  const handleAddCollector = () => {
    setShowCollectorForm(true);
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'online':
        return <Wifi className="text-green-500" size={16} />;
      case 'offline':
        return <WifiOff className="text-red-500" size={16} />;
      case 'enrolling':
        return <Clock className="text-yellow-500" size={16} />;
      default:
        return <WifiOff className="text-gray-500" size={16} />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'online':
        return 'bg-green-500/20 text-green-500';
      case 'offline':
        return 'bg-red-500/20 text-red-500';
      case 'enrolling':
        return 'bg-yellow-500/20 text-yellow-500';
      default:
        return 'bg-gray-500/20 text-gray-500';
    }
  };

  const mockTelemetry = (index: number) => ({
    cpu: index === 0 ? 23.4 : index === 1 ? 12.1 : index === 2 ? 89.3 : 0,
    memory: index === 0 ? 67.8 : index === 1 ? 34.7 : index === 2 ? 92.1 : 0,
    disk: index === 0 ? 45.2 : index === 1 ? 78.9 : index === 2 ? 23.4 : 0,
    lastSync: index === 0 ? '2min' : index === 1 ? '5min' : index === 2 ? '1min' : '2h'
  });

  return (
    <>
      <MainLayout
        activeTab="collectors"
        onTabChange={handleTabChange}
        onNewJourney={handleNewJourney}
        onAddCollector={handleAddCollector}
      >
        <div className="space-y-6" data-testid="collectors-page">
          {/* Header */}
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-3xl font-bold text-white mb-2">Gestão de Coletores</h2>
              <p className="text-muted-foreground">
                Monitore e gerencie seus coletores distribuídos
              </p>
            </div>
            <div className="flex items-center space-x-3">
              <Button
                variant="outline"
                data-testid="refresh-collectors"
                onClick={() => queryClient.invalidateQueries({ queryKey: ['/api/collectors'] })}
              >
                <RefreshCw className="mr-2 h-4 w-4" />
                Atualizar
              </Button>
              <Button
                className="bg-accent hover:bg-accent/90"
                onClick={handleAddCollector}
                data-testid="add-collector-button"
              >
                <Plus className="mr-2 h-4 w-4" />
                Novo Coletor
              </Button>
            </div>
          </div>

          {/* Collectors Grid */}
          {isLoading ? (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {[...Array(6)].map((_, i) => (
                <Card key={i} className="bg-secondary animate-pulse">
                  <CardContent className="p-6">
                    <div className="h-4 bg-muted rounded mb-4"></div>
                    <div className="space-y-2">
                      <div className="h-3 bg-muted rounded"></div>
                      <div className="h-3 bg-muted rounded"></div>
                      <div className="h-3 bg-muted rounded"></div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {collectors?.map((collector: any, index: number) => {
                const telemetry = mockTelemetry(index);
                
                return (
                  <Card key={collector.id} className="bg-secondary" data-testid={`collector-card-${collector.name}`}>
                    <CardHeader className="pb-3">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center space-x-2">
                          {getStatusIcon(collector.status)}
                          <CardTitle className="text-lg">{collector.name}</CardTitle>
                        </div>
                        <Badge className={`text-xs border-0 ${getStatusColor(collector.status)}`}>
                          {collector.status.toUpperCase()}
                        </Badge>
                      </div>
                      {collector.hostname && (
                        <p className="text-sm text-muted-foreground">{collector.hostname}</p>
                      )}
                      {collector.ipAddress && (
                        <p className="text-sm text-muted-foreground">{collector.ipAddress}</p>
                      )}
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <Tabs defaultValue="telemetry" className="w-full">
                        <TabsList className="grid w-full grid-cols-3">
                          <TabsTrigger value="telemetry" className="text-xs">
                            <RefreshCw size={12} className="mr-1" />
                            Telemetria
                          </TabsTrigger>
                          <TabsTrigger value="packages" className="text-xs">
                            <Package size={12} className="mr-1" />
                            Pacotes
                          </TabsTrigger>
                          <TabsTrigger value="deployment" className="text-xs">
                            <Terminal size={12} className="mr-1" />
                            Deploy
                          </TabsTrigger>
                        </TabsList>

                        <TabsContent value="telemetry" className="space-y-3 mt-4">
                          {collector.status === 'online' ? (
                            <>
                              <div className="space-y-2">
                                <div className="flex justify-between text-sm">
                                  <span className="text-muted-foreground">CPU</span>
                                  <span className="text-white">{telemetry.cpu}%</span>
                                </div>
                                <Progress value={telemetry.cpu} className="h-2" />
                              </div>
                              
                              <div className="space-y-2">
                                <div className="flex justify-between text-sm">
                                  <span className="text-muted-foreground">Memória</span>
                                  <span className="text-white">{telemetry.memory}%</span>
                                </div>
                                <Progress value={telemetry.memory} className="h-2" />
                              </div>
                              
                              <div className="space-y-2">
                                <div className="flex justify-between text-sm">
                                  <span className="text-muted-foreground">Disco</span>
                                  <span className="text-white">{telemetry.disk}%</span>
                                </div>
                                <Progress value={telemetry.disk} className="h-2" />
                              </div>
                              
                              <div className="flex justify-between text-sm pt-2 border-t border-border">
                                <span className="text-muted-foreground">Última sync</span>
                                <span className="text-white">{telemetry.lastSync} atrás</span>
                              </div>
                            </>
                          ) : (
                            <div className="text-center py-4">
                              <p className="text-muted-foreground text-sm">
                                {collector.status === 'offline' ? 'Coletor offline' : 'Aguardando enrollment'}
                              </p>
                            </div>
                          )}
                        </TabsContent>

                        <TabsContent value="packages" className="space-y-3 mt-4">
                          <div className="space-y-2">
                            <div className="flex justify-between text-sm">
                              <span className="text-muted-foreground">nmap</span>
                              <Badge variant="outline" className="text-xs">7.94</Badge>
                            </div>
                            <div className="flex justify-between text-sm">
                              <span className="text-muted-foreground">nuclei</span>
                              <Badge variant="outline" className="text-xs">3.1.2</Badge>
                            </div>
                            <div className="flex justify-between text-sm">
                              <span className="text-muted-foreground">samureye-agent</span>
                              <Badge variant="outline" className="text-xs">1.0.0</Badge>
                            </div>
                          </div>
                          <Button 
                            size="sm" 
                            variant="outline" 
                            className="w-full"
                            disabled={collector.status !== 'online'}
                          >
                            <Package className="mr-2 h-3 w-3" />
                            Update Packages
                          </Button>
                        </TabsContent>

                        <TabsContent value="deployment" className="space-y-3 mt-4">
                          <div className="text-xs space-y-2">
                            <p className="text-muted-foreground">Instruções Ubuntu:</p>
                            <code className="block bg-muted p-2 rounded text-xs">
                              curl -sSL install.samureye.com.br | sudo bash
                            </code>
                          </div>
                          <Button
                            size="sm"
                            variant="outline"
                            className="w-full"
                            onClick={() => regenerateTokenMutation.mutate(collector.id)}
                            disabled={regenerateTokenMutation.isPending}
                            data-testid={`regenerate-token-${collector.name}`}
                          >
                            <RefreshCw className="mr-2 h-3 w-3" />
                            Gerar Novo Token
                          </Button>
                        </TabsContent>
                      </Tabs>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          )}
        </div>
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
