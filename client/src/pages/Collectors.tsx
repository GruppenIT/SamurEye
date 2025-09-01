import { useState } from 'react';
import { Plus, Wifi, WifiOff, Clock, RefreshCw, Terminal, Package, Copy } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MainLayout } from '@/components/layout/MainLayout';
import { AdminLayout } from '@/components/layout/AdminLayout';
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
  const [location, setLocation] = useLocation();
  const queryClient = useQueryClient();
  
  // Detect if we're in admin route
  const isAdminRoute = location.startsWith('/admin');
  const [showCollectorForm, setShowCollectorForm] = useState(false);
  const [showJourneyForm, setShowJourneyForm] = useState(false);

  const { data: collectors = [], isLoading } = useQuery({
    queryKey: ['/api/admin/collectors'],
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
      queryClient.invalidateQueries({ queryKey: ['/api/admin/collectors'] });
    },
    onError: (error) => {
      toast({
        title: "Erro",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  const updatePackagesMutation = useMutation({
    mutationFn: async (collectorId: string) => {
      const response = await apiRequest('POST', `/api/collectors/${collectorId}/update-packages`);
      return response.json();
    },
    onSuccess: (data) => {
      toast({
        title: "Atualização iniciada",
        description: data.warning || "Pacotes sendo atualizados",
        variant: "default",
      });
    },
    onError: (error) => {
      toast({
        title: "Erro",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  const getDeployCommandMutation = useMutation({
    mutationFn: async (collectorId: string) => {
      const response = await apiRequest('GET', `/api/collectors/${collectorId}/deploy-command`);
      return response.json();
    },
    onSuccess: (data) => {
      // Copy command to clipboard
      navigator.clipboard.writeText(data.deployCommand).then(() => {
        toast({
          title: "Comando copiado",
          description: "Comando de deploy copiado para área de transferência",
        });
      });
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
        return <Clock className="text-gray-500" size={16} />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'online':
        return 'bg-green-500/20 text-green-400';
      case 'offline':
        return 'bg-red-500/20 text-red-400';
      case 'enrolling':
        return 'bg-yellow-500/20 text-yellow-400';
      default:
        return 'bg-gray-500/20 text-gray-400';
    }
  };

  const formatLastSync = (timestamp: string | null) => {
    if (!timestamp) return 'Nunca';
    const diff = Date.now() - new Date(timestamp).getTime();
    const minutes = Math.floor(diff / 60000);
    return minutes < 1 ? 'Agora' : `${minutes}min atrás`;
  };

  const Layout = isAdminRoute ? AdminLayout : MainLayout;

  return (
    <Layout>
      <div className="space-y-6">
        <CollectorEnrollment 
          open={showCollectorForm} 
          onOpenChange={setShowCollectorForm}
        />
        
        <JourneyForm 
          open={showJourneyForm} 
          onOpenChange={setShowJourneyForm}
          onJourneyCreate={() => {
            toast({
              title: "Jornada criada",
              description: "A nova jornada foi criada com sucesso",
            });
            setShowJourneyForm(false);
          }}
        />

        {/* Header */}
        <div className="flex flex-col space-y-4 md:flex-row md:items-center md:justify-between md:space-y-0">
          <div>
            <h1 className="text-3xl font-bold text-white">Gestão de Coletores</h1>
            <p className="text-muted-foreground">
              Monitore e gerencie seus coletores distribuídos
            </p>
          </div>
          <div className="flex items-center space-x-3">
            <Button
              variant="outline"
              data-testid="refresh-collectors"
              onClick={() => queryClient.invalidateQueries({ queryKey: ['/api/admin/collectors'] })}
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
            {collectors.map((collector: any) => {
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
                        {collector.status === 'online' && collector.latestTelemetry ? (
                          <>
                            <div className="space-y-2">
                              <div className="flex justify-between text-sm">
                                <span className="text-muted-foreground">CPU</span>
                                <span className="text-white">{Math.round(collector.latestTelemetry.cpuUsage || 0)}%</span>
                              </div>
                              <Progress value={collector.latestTelemetry.cpuUsage || 0} className="h-2" />
                            </div>
                            
                            <div className="space-y-2">
                              <div className="flex justify-between text-sm">
                                <span className="text-muted-foreground">Memória</span>
                                <span className="text-white">{Math.round(collector.latestTelemetry.memoryUsage || 0)}%</span>
                              </div>
                              <Progress value={collector.latestTelemetry.memoryUsage || 0} className="h-2" />
                            </div>
                            
                            <div className="space-y-2">
                              <div className="flex justify-between text-sm">
                                <span className="text-muted-foreground">Disco</span>
                                <span className="text-white">{Math.round(collector.latestTelemetry.diskUsage || 0)}%</span>
                              </div>
                              <Progress value={collector.latestTelemetry.diskUsage || 0} className="h-2" />
                            </div>
                            
                            <div className="flex justify-between text-sm pt-2 border-t border-border">
                              <span className="text-muted-foreground">Última sync</span>
                              <span className="text-white">
                                {formatLastSync(collector.lastSeen)}
                              </span>
                            </div>
                          </>
                        ) : (
                          <div className="text-center py-4">
                            <p className="text-muted-foreground text-sm">
                              {collector.status === 'offline' ? 'Coletor offline' : 'Aguardando dados de telemetria'}
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
                          className="w-full mt-4" 
                          variant="outline"
                          onClick={() => updatePackagesMutation.mutate(collector.id)}
                          disabled={updatePackagesMutation.isPending || collector.status !== 'online'}
                        >
                          <Package className="mr-2 h-4 w-4" />
                          {updatePackagesMutation.isPending ? 'Atualizando...' : 'Update Packages'}
                        </Button>
                        
                        {collector.status !== 'online' && (
                          <p className="text-xs text-muted-foreground text-center">
                            Collector deve estar online para atualizar pacotes
                          </p>
                        )}
                      </TabsContent>

                      <TabsContent value="deployment" className="space-y-3 mt-4">
                        <div className="text-center space-y-3">
                          <p className="text-sm text-muted-foreground">
                            Execute o comando abaixo no servidor Ubuntu:
                          </p>
                          
                          <Button 
                            className="w-full" 
                            variant="default"
                            onClick={() => getDeployCommandMutation.mutate(collector.id)}
                            disabled={getDeployCommandMutation.isPending}
                          >
                            <Copy className="mr-2 h-4 w-4" />
                            {getDeployCommandMutation.isPending ? 'Copiando...' : 'Copiar Comando Deploy'}
                          </Button>
                          
                          <div className="text-xs text-muted-foreground space-y-1">
                            <p>Tenant: <span className="text-white">{collector.tenantSlug || 'N/A'}</span></p>
                            <p>Collector: <span className="text-white">{collector.name}</span></p>
                          </div>
                        </div>
                      </TabsContent>
                    </Tabs>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}

        {/* Empty State */}
        {!isLoading && collectors.length === 0 && (
          <Card className="bg-secondary">
            <CardContent className="p-12 text-center">
              <div className="mx-auto w-12 h-12 rounded-full bg-muted flex items-center justify-center mb-4">
                <Wifi className="h-6 w-6 text-muted-foreground" />
              </div>
              <h3 className="text-lg font-medium text-white mb-2">
                Nenhum coletor encontrado
              </h3>
              <p className="text-muted-foreground mb-6">
                Adicione seu primeiro coletor para começar a monitorar a infraestrutura.
              </p>
              <Button 
                className="bg-accent hover:bg-accent/90"
                onClick={handleAddCollector}
              >
                <Plus className="mr-2 h-4 w-4" />
                Adicionar Coletor
              </Button>
            </CardContent>
          </Card>
        )}
      </div>
    </Layout>
  );
}