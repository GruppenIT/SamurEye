import { useState } from 'react';
import { Plus, Key, Trash2, Edit, Eye, EyeOff } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { MainLayout } from '@/components/layout/MainLayout';
import { CredentialForm } from '@/components/credentials/CredentialForm';
import { JourneyForm } from '@/components/journeys/JourneyForm';
import { CollectorEnrollment } from '@/components/collectors/CollectorEnrollment';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import { useLocation } from 'wouter';
import { useI18n } from '@/hooks/useI18n';
import { useToast } from '@/hooks/use-toast';

export default function Credentials() {
  const { t } = useI18n();
  const { toast } = useToast();
  const [, setLocation] = useLocation();
  const queryClient = useQueryClient();
  const [showCredentialForm, setShowCredentialForm] = useState(false);
  const [showJourneyForm, setShowJourneyForm] = useState(false);
  const [showCollectorForm, setShowCollectorForm] = useState(false);
  const [editingCredential, setEditingCredential] = useState<any>(null);

  const { data: credentials, isLoading } = useQuery({
    queryKey: ['/api/credentials'],
  });

  const deleteCredentialMutation = useMutation({
    mutationFn: async (credentialId: string) => {
      await apiRequest('DELETE', `/api/credentials/${credentialId}`);
    },
    onSuccess: () => {
      toast({
        title: "Credencial removida",
        description: "A credencial foi removida com sucesso",
      });
      queryClient.invalidateQueries({ queryKey: ['/api/credentials'] });
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
    if (tab === 'credentials') return;
    setLocation(tab === 'dashboard' ? '/' : `/${tab}`);
  };

  const handleNewJourney = () => {
    setShowJourneyForm(true);
  };

  const handleAddCollector = () => {
    setShowCollectorForm(true);
  };

  const handleNewCredential = () => {
    setEditingCredential(null);
    setShowCredentialForm(true);
  };

  const handleEditCredential = (credential: any) => {
    setEditingCredential(credential);
    setShowCredentialForm(true);
  };

  const getCredentialTypeIcon = (type: string) => {
    return Key; // Default icon for all credential types
  };

  const getCredentialTypeColor = (type: string) => {
    switch (type.toLowerCase()) {
      case 'ssh':
        return 'bg-blue-500/20 text-blue-500';
      case 'ldap':
        return 'bg-green-500/20 text-green-500';
      case 'rdp':
        return 'bg-purple-500/20 text-purple-500';
      case 'database':
        return 'bg-orange-500/20 text-orange-500';
      default:
        return 'bg-gray-500/20 text-gray-500';
    }
  };

  return (
    <>
      <MainLayout
        activeTab="credentials"
        onTabChange={handleTabChange}
        onNewJourney={handleNewJourney}
        onAddCollector={handleAddCollector}
      >
        <div className="space-y-6" data-testid="credentials-page">
          {/* Header */}
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-3xl font-bold text-white mb-2">Gestão de Credenciais</h2>
              <p className="text-muted-foreground">
                Gerencie credenciais seguras integradas com Delinea Secret Server
              </p>
            </div>
            <Button
              className="bg-accent hover:bg-accent/90"
              onClick={handleNewCredential}
              data-testid="new-credential-button"
            >
              <Plus className="mr-2 h-4 w-4" />
              Nova Credencial
            </Button>
          </div>

          {/* Credentials Grid */}
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
          ) : credentials?.length === 0 ? (
            <Card className="bg-secondary">
              <CardContent className="p-12 text-center">
                <Key className="mx-auto h-12 w-12 text-muted-foreground mb-4" />
                <h3 className="text-lg font-semibold text-white mb-2">
                  Nenhuma credencial encontrada
                </h3>
                <p className="text-muted-foreground mb-6">
                  Comece criando sua primeira credencial para usar nas jornadas de teste
                </p>
                <Button
                  className="bg-accent hover:bg-accent/90"
                  onClick={handleNewCredential}
                >
                  <Plus className="mr-2 h-4 w-4" />
                  Criar Primeira Credencial
                </Button>
              </CardContent>
            </Card>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {credentials?.map((credential: any) => {
                const IconComponent = getCredentialTypeIcon(credential.type);
                
                return (
                  <Card key={credential.id} className="bg-secondary hover:bg-secondary/80 transition-colors" data-testid={`credential-card-${credential.name}`}>
                    <CardHeader className="pb-3">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center space-x-3">
                          <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${getCredentialTypeColor(credential.type)}`}>
                            <IconComponent size={20} />
                          </div>
                          <div>
                            <CardTitle className="text-lg">{credential.name}</CardTitle>
                            <Badge className={`text-xs border-0 ${getCredentialTypeColor(credential.type)}`}>
                              {credential.type.toUpperCase()}
                            </Badge>
                          </div>
                        </div>
                      </div>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      {credential.description && (
                        <p className="text-sm text-muted-foreground">
                          {credential.description}
                        </p>
                      )}
                      
                      <div className="space-y-2">
                        <div className="flex justify-between text-sm">
                          <span className="text-muted-foreground">Path Delinea:</span>
                        </div>
                        <code className="block text-xs bg-muted p-2 rounded break-all">
                          {credential.delineaPath}
                        </code>
                      </div>
                      
                      <div className="flex justify-between text-sm">
                        <span className="text-muted-foreground">Criada por:</span>
                        <span className="text-white">
                          {credential.createdBy?.firstName} {credential.createdBy?.lastName}
                        </span>
                      </div>
                      
                      <div className="flex justify-between text-sm">
                        <span className="text-muted-foreground">Data:</span>
                        <span className="text-white">
                          {new Date(credential.createdAt).toLocaleDateString('pt-BR')}
                        </span>
                      </div>
                      
                      <div className="flex items-center space-x-2 pt-2">
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => handleEditCredential(credential)}
                          data-testid={`edit-credential-${credential.name}`}
                        >
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          className="text-red-500 hover:text-red-400 hover:bg-red-500/10"
                          onClick={() => deleteCredentialMutation.mutate(credential.id)}
                          disabled={deleteCredentialMutation.isPending}
                          data-testid={`delete-credential-${credential.name}`}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          )}

          {/* Integration Info */}
          <Card className="bg-secondary border-accent/20">
            <CardContent className="p-6">
              <div className="flex items-start space-x-4">
                <div className="w-12 h-12 bg-accent/20 rounded-lg flex items-center justify-center">
                  <Key className="text-accent" size={24} />
                </div>
                <div>
                  <h3 className="text-lg font-semibold text-white mb-2">
                    Integração com Delinea Secret Server
                  </h3>
                  <p className="text-muted-foreground mb-4">
                    As credenciais são armazenadas de forma segura no Delinea Secret Server. 
                    Nenhuma senha é mantida localmente na plataforma SamurEye.
                  </p>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                    <div>
                      <span className="text-muted-foreground">Endpoint:</span>
                      <code className="block text-xs bg-muted p-2 rounded mt-1">
                        gruppenztna.secretservercloud.com
                      </code>
                    </div>
                    <div>
                      <span className="text-muted-foreground">Estrutura de Pastas:</span>
                      <code className="block text-xs bg-muted p-2 rounded mt-1">
                        BAS/&lt;tenant&gt;/&lt;tipo&gt;/&lt;nome&gt;
                      </code>
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </MainLayout>

      {/* Modals */}
      {showCredentialForm && (
        <CredentialForm
          isOpen={showCredentialForm}
          onClose={() => {
            setShowCredentialForm(false);
            setEditingCredential(null);
          }}
          credential={editingCredential}
        />
      )}

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
