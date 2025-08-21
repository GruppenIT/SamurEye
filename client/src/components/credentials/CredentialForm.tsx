import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import { useToast } from '@/hooks/use-toast';
import { Eye, EyeOff } from 'lucide-react';

// Credential types with their required fields
const CREDENTIAL_TYPES = {
  ssh: {
    label: 'SSH',
    fields: ['hostname', 'port', 'username', 'password', 'privateKey']
  },
  snmp: {
    label: 'SNMP',
    fields: ['hostname', 'port', 'community', 'version']
  },
  telnet: {
    label: 'Telnet',
    fields: ['hostname', 'port', 'username', 'password']
  },
  ldap: {
    label: 'LDAP',
    fields: ['hostname', 'port', 'bindDn', 'bindPassword', 'baseDn']
  },
  wmi: {
    label: 'WMI',
    fields: ['hostname', 'username', 'password', 'domain']
  },
  http: {
    label: 'HTTP',
    fields: ['url', 'username', 'password', 'headers']
  },
  https: {
    label: 'HTTPS',
    fields: ['url', 'username', 'password', 'headers', 'certificate']
  },
  database: {
    label: 'Database',
    fields: ['hostname', 'port', 'database', 'username', 'password', 'connectionString']
  },
  api_key: {
    label: 'API Key',
    fields: ['url', 'apiKey', 'headers']
  },
  certificate: {
    label: 'Certificate',
    fields: ['certificate', 'privateKey', 'passphrase']
  }
} as const;

const credentialSchema = z.object({
  name: z.string().min(1, 'Nome é obrigatório'),
  type: z.enum(['ssh', 'snmp', 'telnet', 'ldap', 'wmi', 'http', 'https', 'database', 'api_key', 'certificate']),
  description: z.string().optional(),
  credentialData: z.record(z.string(), z.any())
});

type CredentialForm = z.infer<typeof credentialSchema>;

interface CredentialFormProps {
  open: boolean;
  onClose: () => void;
  credential?: any;
}

export function CredentialForm({ open, onClose, credential }: CredentialFormProps) {
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [selectedType, setSelectedType] = useState<string>(credential?.type || '');
  const [showPasswords, setShowPasswords] = useState<Record<string, boolean>>({});

  const form = useForm<CredentialForm>({
    resolver: zodResolver(credentialSchema),
    defaultValues: {
      name: credential?.name || '',
      type: credential?.type || 'ssh',
      description: credential?.description || '',
      credentialData: credential?.credentialData || {}
    }
  });

  const createMutation = useMutation({
    mutationFn: async (data: CredentialForm) => {
      const endpoint = credential ? `/api/credentials/${credential.id}` : '/api/credentials';
      const method = credential ? 'PUT' : 'POST';
      const response = await apiRequest(method, endpoint, data);
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['/api/credentials'] });
      toast({
        title: 'Sucesso',
        description: credential ? 'Credencial atualizada com sucesso' : 'Credencial criada com sucesso'
      });
      onClose();
    },
    onError: (error: any) => {
      toast({
        title: 'Erro',
        description: error.message || 'Erro ao salvar credencial',
        variant: 'destructive'
      });
    }
  });

  const togglePasswordVisibility = (fieldName: string) => {
    setShowPasswords(prev => ({
      ...prev,
      [fieldName]: !prev[fieldName]
    }));
  };

  const renderFieldInput = (fieldName: string, value: any, onChange: (value: any) => void) => {
    const isPasswordField = fieldName.toLowerCase().includes('password') || 
                           fieldName.toLowerCase().includes('key') ||
                           fieldName === 'passphrase';
    
    const isLongTextField = fieldName === 'certificate' || 
                           fieldName === 'privateKey' ||
                           fieldName === 'connectionString' ||
                           fieldName === 'headers';

    if (isLongTextField) {
      return (
        <Textarea
          value={value || ''}
          onChange={(e) => onChange(e.target.value)}
          placeholder={`Digite ${fieldName}`}
          rows={3}
          data-testid={`input-${fieldName}`}
        />
      );
    }

    if (isPasswordField) {
      return (
        <div className="relative">
          <Input
            type={showPasswords[fieldName] ? 'text' : 'password'}
            value={value || ''}
            onChange={(e) => onChange(e.target.value)}
            placeholder={`Digite ${fieldName}`}
            data-testid={`input-${fieldName}`}
          />
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="absolute right-0 top-0 h-full px-3"
            onClick={() => togglePasswordVisibility(fieldName)}
          >
            {showPasswords[fieldName] ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </Button>
        </div>
      );
    }

    return (
      <Input
        value={value || ''}
        onChange={(e) => onChange(e.target.value)}
        placeholder={`Digite ${fieldName}`}
        data-testid={`input-${fieldName}`}
      />
    );
  };

  const getFieldLabel = (fieldName: string) => {
    const labels: Record<string, string> = {
      hostname: 'Hostname',
      port: 'Porta',
      username: 'Usuário',
      password: 'Senha',
      privateKey: 'Chave Privada',
      community: 'Community',
      version: 'Versão SNMP',
      bindDn: 'Bind DN',
      bindPassword: 'Senha Bind',
      baseDn: 'Base DN',
      domain: 'Domínio',
      url: 'URL',
      headers: 'Headers (JSON)',
      database: 'Database',
      connectionString: 'String de Conexão',
      apiKey: 'API Key',
      certificate: 'Certificado',
      passphrase: 'Passphrase'
    };
    return labels[fieldName] || fieldName;
  };

  const onSubmit = (data: CredentialForm) => {
    createMutation.mutate(data);
  };

  const typeConfig = selectedType ? CREDENTIAL_TYPES[selectedType as keyof typeof CREDENTIAL_TYPES] : null;

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {credential ? 'Editar Credencial' : 'Nova Credencial'}
          </DialogTitle>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
            <FormField
              control={form.control}
              name="name"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Nome</FormLabel>
                  <FormControl>
                    <Input {...field} data-testid="input-name" />
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
                  <FormLabel>Tipo</FormLabel>
                  <Select 
                    value={field.value} 
                    onValueChange={(value) => {
                      field.onChange(value);
                      setSelectedType(value);
                      form.setValue('credentialData', {});
                    }}
                  >
                    <FormControl>
                      <SelectTrigger data-testid="select-type">
                        <SelectValue placeholder="Selecione o tipo" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {Object.entries(CREDENTIAL_TYPES).map(([key, config]) => (
                        <SelectItem key={key} value={key}>
                          {config.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            {typeConfig && (
              <div className="space-y-4">
                <h4 className="text-sm font-medium">Configuração {typeConfig.label}</h4>
                {typeConfig.fields.map((fieldName) => (
                  <FormField
                    key={fieldName}
                    control={form.control}
                    name="credentialData"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>{getFieldLabel(fieldName)}</FormLabel>
                        <FormControl>
                          {renderFieldInput(
                            fieldName,
                            field.value?.[fieldName],
                            (value) => {
                              const newData = { ...field.value, [fieldName]: value };
                              field.onChange(newData);
                            }
                          )}
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                ))}
              </div>
            )}

            <FormField
              control={form.control}
              name="description"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Descrição</FormLabel>
                  <FormControl>
                    <Textarea {...field} data-testid="input-description" />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <div className="flex justify-end space-x-2">
              <Button type="button" variant="outline" onClick={onClose}>
                Cancelar
              </Button>
              <Button 
                type="submit" 
                disabled={createMutation.isPending}
                data-testid="button-save"
              >
                {createMutation.isPending ? 'Salvando...' : 'Salvar'}
              </Button>
            </div>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}