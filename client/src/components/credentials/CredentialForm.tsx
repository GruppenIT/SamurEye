import { useState } from 'react';
import { Key, Eye, EyeOff, Lock, Save } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import { useToast } from '@/hooks/use-toast';
import { useI18n } from '@/hooks/useI18n';
import { useTenant } from '@/contexts/TenantContext';

const credentialSchema = z.object({
  name: z.string().min(1, 'Nome é obrigatório'),
  type: z.enum(['SSH', 'LDAP', 'RDP', 'Database', 'API', 'Other']),
  description: z.string().optional(),
  // Secret data that will be sent to Delinea
  username: z.string().min(1, 'Usuário é obrigatório'),
  password: z.string().min(1, 'Senha é obrigatória'),
  domain: z.string().optional(),
  port: z.string().optional(),
  host: z.string().optional(),
  additionalFields: z.record(z.string()).optional(),
});

interface CredentialFormProps {
  isOpen: boolean;
  onClose: () => void;
  credential?: any;
}

export function CredentialForm({ isOpen, onClose, credential }: CredentialFormProps) {
  const { t } = useI18n();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const { currentUser } = useTenant();
  const [showPassword, setShowPassword] = useState(false);
  const [additionalField, setAdditionalField] = useState({ key: '', value: '' });

  const form = useForm<z.infer<typeof credentialSchema>>({
    resolver: zodResolver(credentialSchema),
    defaultValues: {
      name: credential?.name || '',
      type: credential?.type || 'SSH',
      description: credential?.description || '',
      username: '',
      password: '',
      domain: '',
      port: '',
      host: '',
      additionalFields: {},
    },
  });

  const createCredentialMutation = useMutation({
    mutationFn: async (data: z.infer<typeof credentialSchema>) => {
      // Separate the secret data from the metadata
      const { username, password, domain, port, host, additionalFields, ...metadata } = data;
      
      const secretData = {
        username,
        password,
        ...(domain && { domain }),
        ...(port && { port }),
        ...(host && { host }),
        ...additionalFields,
      };

      const payload = {
        ...metadata,
        secretData,
      };

      const response = await apiRequest('POST', '/api/credentials', payload);
      return response.json();
    },
    onSuccess: () => {
      toast({
        title: "Credencial criada",
        description: "Credencial armazenada com segurança no Delinea Secret Server",
      });
      queryClient.invalidateQueries({ queryKey: ['/api/credentials'] });
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

  const credentialTypes = [
    {
      value: 'SSH',
      label: 'SSH',
      fields: ['username', 'password', 'host', 'port'],
      defaultPort: '22',
      description: 'Credenciais para acesso SSH'
    },
    {
      value: 'LDAP',
      label: 'LDAP/Active Directory',
      fields: ['username', 'password', 'domain', 'host', 'port'],
      defaultPort: '389',
      description: 'Credenciais para autenticação LDAP/AD'
    },
    {
      value: 'RDP',
      label: 'RDP (Remote Desktop)',
      fields: ['username', 'password', 'domain', 'host', 'port'],
      defaultPort: '3389',
      description: 'Credenciais para acesso RDP'
    },
    {
      value: 'Database',
      label: 'Database',
      fields: ['username', 'password', 'host', 'port'],
      defaultPort: '1433',
      description: 'Credenciais para banco de dados'
    },
    {
      value: 'API',
      label: 'API Key',
      fields: ['username', 'password'],
      description: 'Chaves de API e tokens'
    },
    {
      value: 'Other',
      label: 'Outro',
      fields: ['username', 'password'],
      description: 'Outros tipos de credenciais'
    }
  ];

  const onSubmit = (data: z.infer<typeof credentialSchema>) => {
    createCredentialMutation.mutate(data);
  };

  const handleClose = () => {
    form.reset();
    setAdditionalField({ key: '', value: '' });
    onClose();
  };

  const watchedType = form.watch('type');
  const selectedTypeConfig = credentialTypes.find(type => type.value === watchedType);

  const addAdditionalField = () => {
    if (additionalField.key && additionalField.value) {
      const current = form.getValues('additionalFields') || {};
      form.setValue('additionalFields', {
        ...current,
        [additionalField.key]: additionalField.value
      });
      setAdditionalField({ key: '', value: '' });
    }
  };

  const removeAdditionalField = (key: string) => {
    const current = form.getValues('additionalFields') || {};
    const { [key]: removed, ...rest } = current;
    form.setValue('additionalFields', rest);
  };

  const getCredentialTypeColor = (type: string) => {
    switch (type) {
      case 'SSH':
        return 'bg-blue-500/20 text-blue-500';
      case 'LDAP':
        return 'bg-green-500/20 text-green-500';
      case 'RDP':
        return 'bg-purple-500/20 text-purple-500';
      case 'Database':
        return 'bg-orange-500/20 text-orange-500';
      case 'API':
        return 'bg-yellow-500/20 text-yellow-500';
      default:
        return 'bg-gray-500/20 text-gray-500';
    }
  };

  // Set default port when type changes
  React.useEffect(() => {
    if (selectedTypeConfig?.defaultPort && selectedTypeConfig.fields.includes('port')) {
      form.setValue('port', selectedTypeConfig.defaultPort);
    }
  }, [watchedType, selectedTypeConfig, form]);

  return (
    <Dialog open={isOpen} onOpenChange={handleClose}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto" data-testid="credential-form-dialog">
        <DialogHeader>
          <DialogTitle className="flex items-center space-x-2">
            <Key className="h-5 w-5" />
            <span>{credential ? 'Editar Credencial' : 'Nova Credencial'}</span>
          </DialogTitle>
          <DialogDescription>
            As credenciais serão armazenadas com segurança no Delinea Secret Server
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
                <div className="grid grid-cols-2 gap-4">
                  <FormField
                    control={form.control}
                    name="name"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Nome da Credencial *</FormLabel>
                        <FormControl>
                          <Input 
                            placeholder="ex: SSH_Default, Domain_Admin" 
                            {...field} 
                            data-testid="credential-name-input"
                          />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />

                  <FormField
                    control={form.control}
                    name="type"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Tipo *</FormLabel>
                        <FormControl>
                          <Select 
                            value={field.value} 
                            onValueChange={field.onChange}
                            data-testid="credential-type-select"
                          >
                            <SelectTrigger>
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {credentialTypes.map((type) => (
                                <SelectItem key={type.value} value={type.value}>
                                  <div className="flex items-center space-x-2">
                                    <Badge className={`text-xs border-0 ${getCredentialTypeColor(type.value)}`}>
                                      {type.value}
                                    </Badge>
                                    <span>{type.label}</span>
                                  </div>
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                </div>

                <FormField
                  control={form.control}
                  name="description"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Descrição</FormLabel>
                      <FormControl>
                        <Textarea 
                          placeholder="Descreva como esta credencial será usada..."
                          {...field}
                          data-testid="credential-description-input"
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                {selectedTypeConfig && (
                  <div className="p-3 bg-accent/10 rounded-lg">
                    <p className="text-sm text-muted-foreground">
                      {selectedTypeConfig.description}
                    </p>
                  </div>
                )}
              </CardContent>
            </Card>

            {/* Secret Data */}
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center space-x-2">
                  <Lock className="h-5 w-5" />
                  <span>Dados Sensíveis</span>
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <FormField
                    control={form.control}
                    name="username"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Usuário *</FormLabel>
                        <FormControl>
                          <Input 
                            placeholder={watchedType === 'LDAP' ? 'domain\\user' : 'username'} 
                            {...field} 
                            data-testid="credential-username-input"
                          />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />

                  <FormField
                    control={form.control}
                    name="password"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Senha *</FormLabel>
                        <FormControl>
                          <div className="relative">
                            <Input 
                              type={showPassword ? 'text' : 'password'}
                              placeholder="Digite a senha"
                              {...field}
                              data-testid="credential-password-input"
                            />
                            <Button
                              type="button"
                              variant="ghost"
                              size="sm"
                              className="absolute right-2 top-1/2 transform -translate-y-1/2"
                              onClick={() => setShowPassword(!showPassword)}
                              data-testid="toggle-password-visibility"
                            >
                              {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                            </Button>
                          </div>
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                </div>

                {/* Type-specific fields */}
                {selectedTypeConfig?.fields.includes('domain') && (
                  <div className="grid grid-cols-2 gap-4">
                    <FormField
                      control={form.control}
                      name="domain"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Domínio</FormLabel>
                          <FormControl>
                            <Input 
                              placeholder="ex: company.local" 
                              {...field} 
                              data-testid="credential-domain-input"
                            />
                          </FormControl>
                          <FormMessage />
                        </FormItem>
                      )}
                    />
                  </div>
                )}

                {(selectedTypeConfig?.fields.includes('host') || selectedTypeConfig?.fields.includes('port')) && (
                  <div className="grid grid-cols-2 gap-4">
                    {selectedTypeConfig.fields.includes('host') && (
                      <FormField
                        control={form.control}
                        name="host"
                        render={({ field }) => (
                          <FormItem>
                            <FormLabel>Host/Servidor</FormLabel>
                            <FormControl>
                              <Input 
                                placeholder="ex: server.company.local" 
                                {...field} 
                                data-testid="credential-host-input"
                              />
                            </FormControl>
                            <FormMessage />
                          </FormItem>
                        )}
                      />
                    )}

                    {selectedTypeConfig.fields.includes('port') && (
                      <FormField
                        control={form.control}
                        name="port"
                        render={({ field }) => (
                          <FormItem>
                            <FormLabel>Porta</FormLabel>
                            <FormControl>
                              <Input 
                                placeholder={selectedTypeConfig.defaultPort}
                                {...field}
                                data-testid="credential-port-input"
                              />
                            </FormControl>
                            <FormMessage />
                          </FormItem>
                        )}
                      />
                    )}
                  </div>
                )}
              </CardContent>
            </Card>

            {/* Additional Fields */}
            <Card>
              <CardHeader>
                <CardTitle>Campos Adicionais</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                {/* Current additional fields */}
                {form.watch('additionalFields') && Object.keys(form.watch('additionalFields') || {}).length > 0 && (
                  <div className="space-y-2">
                    {Object.entries(form.watch('additionalFields') || {}).map(([key, value]) => (
                      <div key={key} className="flex items-center space-x-2 p-2 bg-muted rounded">
                        <span className="text-sm font-medium">{key}:</span>
                        <span className="text-sm flex-1">{String(value)}</span>
                        <Button
                          type="button"
                          size="sm"
                          variant="ghost"
                          onClick={() => removeAdditionalField(key)}
                          data-testid={`remove-field-${key}`}
                        >
                          ×
                        </Button>
                      </div>
                    ))}
                  </div>
                )}

                {/* Add new field */}
                <div className="flex items-center space-x-2">
                  <Input
                    placeholder="Chave"
                    value={additionalField.key}
                    onChange={(e) => setAdditionalField(prev => ({ ...prev, key: e.target.value }))}
                    className="flex-1"
                    data-testid="additional-field-key"
                  />
                  <Input
                    placeholder="Valor"
                    value={additionalField.value}
                    onChange={(e) => setAdditionalField(prev => ({ ...prev, value: e.target.value }))}
                    className="flex-1"
                    data-testid="additional-field-value"
                  />
                  <Button
                    type="button"
                    size="sm"
                    onClick={addAdditionalField}
                    disabled={!additionalField.key || !additionalField.value}
                    data-testid="add-additional-field"
                  >
                    Adicionar
                  </Button>
                </div>
                <p className="text-xs text-muted-foreground">
                  Campos adicionais podem incluir configurações específicas ou metadados relevantes
                </p>
              </CardContent>
            </Card>

            {/* Delinea Path Preview */}
            <Card className="bg-accent/10 border-accent/20">
              <CardContent className="p-4">
                <div className="flex items-center space-x-2 mb-2">
                  <Key className="text-accent" size={16} />
                  <span className="font-medium text-accent">Path no Delinea Secret Server:</span>
                </div>
                <code className="text-sm bg-muted p-2 rounded block">
                  BAS/{currentUser?.currentTenant?.slug || 'tenant'}/{form.watch('type')}/{form.watch('name') || 'credential_name'}
                </code>
              </CardContent>
            </Card>

            {/* Actions */}
            <div className="flex justify-end space-x-3">
              <Button type="button" variant="outline" onClick={handleClose}>
                Cancelar
              </Button>
              <Button 
                type="submit" 
                disabled={createCredentialMutation.isPending}
                data-testid="save-credential-button"
              >
                <Save className="mr-2 h-4 w-4" />
                {createCredentialMutation.isPending ? 'Salvando...' : 'Salvar Credencial'}
              </Button>
            </div>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
