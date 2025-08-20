import { useState } from 'react';
import { Play, Globe, Users, Shield, Target, Network, Server } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Checkbox } from '@/components/ui/checkbox';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useMutation, useQueryClient, useQuery } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import { useToast } from '@/hooks/use-toast';
import { useI18n } from '@/hooks/useI18n';

const baseJourneySchema = z.object({
  name: z.string().min(1, 'Nome é obrigatório'),
  type: z.enum(['attack_surface', 'ad_hygiene', 'edr_testing']),
  collectorId: z.string().optional(),
  config: z.record(z.any()),
});

interface JourneyFormProps {
  isOpen: boolean;
  onClose: () => void;
  journey?: any;
}

export function JourneyForm({ isOpen, onClose, journey }: JourneyFormProps) {
  const { t } = useI18n();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [selectedType, setSelectedType] = useState<string>(journey?.type || '');

  const { data: collectors } = useQuery({
    queryKey: ['/api/collectors'],
  });

  const { data: credentials } = useQuery({
    queryKey: ['/api/credentials'],
  });

  const form = useForm<z.infer<typeof baseJourneySchema>>({
    resolver: zodResolver(baseJourneySchema),
    defaultValues: {
      name: journey?.name || '',
      type: journey?.type || 'attack_surface',
      collectorId: journey?.collectorId || '',
      config: journey?.config || {},
    },
  });

  const createJourneyMutation = useMutation({
    mutationFn: async (data: z.infer<typeof baseJourneySchema>) => {
      const response = await apiRequest('POST', '/api/journeys', data);
      return response.json();
    },
    onSuccess: () => {
      toast({
        title: "Jornada criada",
        description: "Nova jornada de teste criada com sucesso",
      });
      queryClient.invalidateQueries({ queryKey: ['/api/journeys'] });
      handleClose();
    },
    onError: (error) => {
      toast({
        title: "Erro",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  const journeyTypes = [
    {
      id: 'attack_surface',
      name: 'Attack Surface',
      icon: Globe,
      description: 'Descubra serviços expostos e vulnerabilidades em hosts e redes',
      color: 'text-blue-500',
      bgColor: 'bg-blue-500/20'
    },
    {
      id: 'ad_hygiene',
      name: 'Higiene AD/LDAP',
      icon: Users,
      description: 'Analise políticas de Active Directory e higiene de usuários',
      color: 'text-green-500',
      bgColor: 'bg-green-500/20'
    },
    {
      id: 'edr_testing',
      name: 'EDR/AV Testing',
      icon: Shield,
      description: 'Teste eficácia de soluções EDR e antivírus',
      color: 'text-purple-500',
      bgColor: 'bg-purple-500/20'
    }
  ];

  const onSubmit = (data: z.infer<typeof baseJourneySchema>) => {
    // Build specific config based on journey type
    let config = { ...data.config };
    
    if (selectedType === 'attack_surface') {
      config = {
        ...config,
        scanType: data.config.scanType || 'internal',
        targets: data.config.targets || [],
        ports: data.config.ports || 'default',
        nmapOptions: data.config.nmapOptions || '-sV -sC',
        nucleiTemplates: data.config.nucleiTemplates || 'all'
      };
    } else if (selectedType === 'ad_hygiene') {
      config = {
        ...config,
        domainController: data.config.domainController || '',
        credentialId: data.config.credentialId || '',
        checks: data.config.checks || []
      };
    } else if (selectedType === 'edr_testing') {
      config = {
        ...config,
        endpoints: data.config.endpoints || [],
        testSuite: data.config.testSuite || 'standard',
        credentialId: data.config.credentialId || ''
      };
    }

    createJourneyMutation.mutate({
      ...data,
      config
    });
  };

  const handleClose = () => {
    form.reset();
    setSelectedType('');
    onClose();
  };

  const watchedType = form.watch('type');

  const renderAttackSurfaceConfig = () => (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div>
          <Label>Tipo de Scan</Label>
          <Select 
            value={form.watch('config.scanType')} 
            onValueChange={(value) => form.setValue('config.scanType', value)}
            data-testid="attack-surface-scan-type"
          >
            <SelectTrigger>
              <SelectValue placeholder="Selecione o tipo" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="internal">Interno (via Collector)</SelectItem>
              <SelectItem value="external">Externo (via Cloud)</SelectItem>
            </SelectContent>
          </Select>
        </div>
        
        {form.watch('config.scanType') === 'internal' && (
          <div>
            <Label>Collector</Label>
            <Select 
              value={form.watch('collectorId')} 
              onValueChange={(value) => form.setValue('collectorId', value)}
              data-testid="collector-select"
            >
              <SelectTrigger>
                <SelectValue placeholder="Selecione o collector" />
              </SelectTrigger>
              <SelectContent>
                {collectors?.filter((c: any) => c.status === 'online').map((collector: any) => (
                  <SelectItem key={collector.id} value={collector.id}>
                    {collector.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}
      </div>

      <div>
        <Label>Alvos (IPs, ranges ou hostnames)</Label>
        <Textarea 
          placeholder="192.168.1.0/24&#10;10.0.0.1-10.0.0.100&#10;example.com"
          value={form.watch('config.targets')?.join('\n') || ''}
          onChange={(e) => form.setValue('config.targets', e.target.value.split('\n').filter(Boolean))}
          data-testid="targets-input"
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <Label>Portas</Label>
          <Input 
            placeholder="1-1000 ou default"
            value={form.watch('config.ports') || ''}
            onChange={(e) => form.setValue('config.ports', e.target.value)}
            data-testid="ports-input"
          />
        </div>
        <div>
          <Label>Opções Nmap</Label>
          <Input 
            placeholder="-sV -sC --script vuln"
            value={form.watch('config.nmapOptions') || ''}
            onChange={(e) => form.setValue('config.nmapOptions', e.target.value)}
            data-testid="nmap-options-input"
          />
        </div>
      </div>

      <div>
        <Label>Templates Nuclei</Label>
        <Select 
          value={form.watch('config.nucleiTemplates')} 
          onValueChange={(value) => form.setValue('config.nucleiTemplates', value)}
          data-testid="nuclei-templates-select"
        >
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos os templates</SelectItem>
            <SelectItem value="critical">Apenas críticos</SelectItem>
            <SelectItem value="high">Críticos e altos</SelectItem>
            <SelectItem value="custom">Personalizado</SelectItem>
          </SelectContent>
        </Select>
      </div>
    </div>
  );

  const renderADHygieneConfig = () => (
    <div className="space-y-4">
      <div>
        <Label>Domain Controller</Label>
        <Input 
          placeholder="dc.domain.local"
          value={form.watch('config.domainController') || ''}
          onChange={(e) => form.setValue('config.domainController', e.target.value)}
          data-testid="domain-controller-input"
        />
      </div>

      <div>
        <Label>Credencial LDAP</Label>
        <Select 
          value={form.watch('config.credentialId')} 
          onValueChange={(value) => form.setValue('config.credentialId', value)}
          data-testid="ldap-credential-select"
        >
          <SelectTrigger>
            <SelectValue placeholder="Selecione uma credencial" />
          </SelectTrigger>
          <SelectContent>
            {credentials?.filter((c: any) => c.type.toLowerCase() === 'ldap').map((credential: any) => (
              <SelectItem key={credential.id} value={credential.id}>
                {credential.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div>
        <Label>Verificações</Label>
        <div className="grid grid-cols-2 gap-2 mt-2">
          {[
            'inactive_accounts',
            'weak_passwords',
            'orphaned_admins',
            'stale_computers',
            'delegation_issues',
            'kerberoast_vulnerable'
          ].map((check) => (
            <div key={check} className="flex items-center space-x-2">
              <Checkbox 
                id={check}
                checked={form.watch('config.checks')?.includes(check) || false}
                onCheckedChange={(checked) => {
                  const currentChecks = form.watch('config.checks') || [];
                  if (checked) {
                    form.setValue('config.checks', [...currentChecks, check]);
                  } else {
                    form.setValue('config.checks', currentChecks.filter((c: string) => c !== check));
                  }
                }}
                data-testid={`check-${check}`}
              />
              <Label htmlFor={check} className="text-sm">
                {check.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}
              </Label>
            </div>
          ))}
        </div>
      </div>
    </div>
  );

  const renderEDRTestingConfig = () => (
    <div className="space-y-4">
      <div>
        <Label>Endpoints de Teste</Label>
        <Textarea 
          placeholder="Lista de endpoints (IPs ou hostnames)&#10;192.168.1.10&#10;ws-001.domain.local"
          value={form.watch('config.endpoints')?.join('\n') || ''}
          onChange={(e) => form.setValue('config.endpoints', e.target.value.split('\n').filter(Boolean))}
          data-testid="endpoints-input"
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <Label>Suite de Testes</Label>
          <Select 
            value={form.watch('config.testSuite')} 
            onValueChange={(value) => form.setValue('config.testSuite', value)}
            data-testid="test-suite-select"
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="standard">Padrão (MITRE ATT&CK)</SelectItem>
              <SelectItem value="advanced">Avançado (Evasion)</SelectItem>
              <SelectItem value="custom">Personalizado</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <div>
          <Label>Credencial de Acesso</Label>
          <Select 
            value={form.watch('config.credentialId')} 
            onValueChange={(value) => form.setValue('config.credentialId', value)}
            data-testid="access-credential-select"
          >
            <SelectTrigger>
              <SelectValue placeholder="Selecione uma credencial" />
            </SelectTrigger>
            <SelectContent>
              {credentials?.filter((c: any) => ['ssh', 'rdp'].includes(c.type.toLowerCase())).map((credential: any) => (
                <SelectItem key={credential.id} value={credential.id}>
                  {credential.name} ({credential.type})
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>
    </div>
  );

  const renderConfigForType = (type: string) => {
    switch (type) {
      case 'attack_surface':
        return renderAttackSurfaceConfig();
      case 'ad_hygiene':
        return renderADHygieneConfig();
      case 'edr_testing':
        return renderEDRTestingConfig();
      default:
        return null;
    }
  };

  return (
    <Dialog open={isOpen} onOpenChange={handleClose}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto" data-testid="journey-form-dialog">
        <DialogHeader>
          <DialogTitle className="flex items-center space-x-2">
            <Play className="h-5 w-5" />
            <span>{journey ? 'Editar Jornada' : 'Nova Jornada de Teste'}</span>
          </DialogTitle>
          <DialogDescription>
            Configure uma nova jornada de teste de segurança para descobrir vulnerabilidades
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
            {/* Basic Information */}
            <Card>
              <CardHeader>
                <CardTitle>Informações Básicas</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <FormField
                  control={form.control}
                  name="name"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Nome da Jornada *</FormLabel>
                      <FormControl>
                        <Input 
                          placeholder="ex: Attack Surface - Rede DMZ" 
                          {...field} 
                          data-testid="journey-name-input"
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                {/* Journey Type Selection */}
                <FormField
                  control={form.control}
                  name="type"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Tipo de Jornada *</FormLabel>
                      <FormControl>
                        <div className="grid grid-cols-1 md:grid-cols-3 gap-4" data-testid="journey-type-selection">
                          {journeyTypes.map((type) => {
                            const IconComponent = type.icon;
                            const isSelected = field.value === type.id;
                            
                            return (
                              <Card 
                                key={type.id}
                                className={`cursor-pointer transition-all ${
                                  isSelected 
                                    ? 'ring-2 ring-accent bg-accent/10' 
                                    : 'hover:bg-secondary/80'
                                }`}
                                onClick={() => {
                                  field.onChange(type.id);
                                  setSelectedType(type.id);
                                }}
                                data-testid={`journey-type-${type.id}`}
                              >
                                <CardContent className="p-4">
                                  <div className={`w-12 h-12 rounded-lg flex items-center justify-center mb-3 ${type.bgColor}`}>
                                    <IconComponent className={type.color} size={24} />
                                  </div>
                                  <h3 className="font-semibold text-white mb-2">{type.name}</h3>
                                  <p className="text-sm text-muted-foreground">{type.description}</p>
                                </CardContent>
                              </Card>
                            );
                          })}
                        </div>
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </CardContent>
            </Card>

            {/* Type-specific Configuration */}
            {watchedType && (
              <Card>
                <CardHeader>
                  <CardTitle>Configuração Específica</CardTitle>
                </CardHeader>
                <CardContent>
                  {renderConfigForType(watchedType)}
                </CardContent>
              </Card>
            )}

            {/* Actions */}
            <div className="flex justify-end space-x-3">
              <Button type="button" variant="outline" onClick={handleClose}>
                Cancelar
              </Button>
              <Button 
                type="submit" 
                disabled={createJourneyMutation.isPending || !watchedType}
                data-testid="create-journey-button"
              >
                {createJourneyMutation.isPending ? 'Criando...' : 'Criar Jornada'}
              </Button>
            </div>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
