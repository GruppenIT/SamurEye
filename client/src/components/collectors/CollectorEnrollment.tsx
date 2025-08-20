import { useState } from 'react';
import { Copy, Server, Download, Terminal, CheckCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useMutation, useQueryClient, useQuery } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import { useToast } from '@/hooks/use-toast';
import { useI18n } from '@/hooks/useI18n';

const collectorSchema = z.object({
  name: z.string().min(1, 'Nome é obrigatório'),
  hostname: z.string().optional(),
  ipAddress: z.string().optional(),
  description: z.string().optional(),
});

interface CollectorEnrollmentProps {
  isOpen: boolean;
  onClose: () => void;
}

export function CollectorEnrollment({ isOpen, onClose }: CollectorEnrollmentProps) {
  const { t } = useI18n();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [step, setStep] = useState(1);
  const [enrollmentData, setEnrollmentData] = useState<any>(null);

  const form = useForm<z.infer<typeof collectorSchema>>({
    resolver: zodResolver(collectorSchema),
    defaultValues: {
      name: '',
      hostname: '',
      ipAddress: '',
      description: '',
    },
  });

  const createCollectorMutation = useMutation({
    mutationFn: async (data: z.infer<typeof collectorSchema>) => {
      const response = await apiRequest('POST', '/api/collectors', data);
      return response.json();
    },
    onSuccess: (data) => {
      setEnrollmentData(data);
      setStep(2);
      queryClient.invalidateQueries({ queryKey: ['/api/collectors'] });
      toast({
        title: "Coletor criado",
        description: "Coletor criado com sucesso. Use o token para enrollment.",
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

  const onSubmit = (data: z.infer<typeof collectorSchema>) => {
    createCollectorMutation.mutate(data);
  };

  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      toast({
        title: "Copiado",
        description: "Texto copiado para a área de transferência",
      });
    } catch (error) {
      toast({
        title: "Erro",
        description: "Falha ao copiar texto",
        variant: "destructive",
      });
    }
  };

  const installScript = enrollmentData ? `#!/bin/bash
# SamurEye Collector Installation Script
set -e

echo "Installing SamurEye Collector..."

# Download and install collector
curl -sSL https://releases.samureye.com.br/collector/install.sh | sudo bash

# Configure collector
sudo tee /etc/samureye/collector.conf > /dev/null <<EOF
api_endpoint=https://api.samureye.com.br
enrollment_token=${enrollmentData.enrollmentToken}
collector_name=${enrollmentData.name}
tenant_id=${enrollmentData.tenantId}
EOF

# Start collector service
sudo systemctl enable samureye-collector
sudo systemctl start samureye-collector

echo "✅ SamurEye Collector installed successfully!"
echo "Check status with: sudo systemctl status samureye-collector"
` : '';

  const ubuntuInstructions = `# 1. Baixe e execute o script de instalação
curl -sSL install.samureye.com.br | sudo bash

# 2. Configure o coletor com seu token
sudo samureye-collector enroll --token ${enrollmentData?.enrollmentToken || 'YOUR_TOKEN'}

# 3. Inicie o serviço
sudo systemctl enable samureye-collector
sudo systemctl start samureye-collector

# 4. Verifique o status
sudo systemctl status samureye-collector`;

  const handleClose = () => {
    setStep(1);
    setEnrollmentData(null);
    form.reset();
    onClose();
  };

  return (
    <Dialog open={isOpen} onOpenChange={handleClose}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto" data-testid="collector-enrollment-dialog">
        <DialogHeader>
          <DialogTitle className="flex items-center space-x-2">
            <Server className="h-5 w-5" />
            <span>
              {step === 1 ? 'Novo Coletor' : 'Instruções de Deployment'}
            </span>
          </DialogTitle>
          <DialogDescription>
            {step === 1 
              ? 'Configure um novo coletor para executar jornadas de teste'
              : 'Use as instruções abaixo para instalar o coletor no ambiente alvo'
            }
          </DialogDescription>
        </DialogHeader>

        {step === 1 ? (
          /* Step 1: Collector Configuration */
          <Form {...form}>
            <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <FormField
                  control={form.control}
                  name="name"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Nome do Coletor *</FormLabel>
                      <FormControl>
                        <Input 
                          placeholder="ex: collector-dmz" 
                          {...field} 
                          data-testid="collector-name-input"
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="hostname"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Hostname</FormLabel>
                      <FormControl>
                        <Input 
                          placeholder="ex: ubuntu-server-01" 
                          {...field} 
                          data-testid="collector-hostname-input"
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="ipAddress"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Endereço IP</FormLabel>
                      <FormControl>
                        <Input 
                          placeholder="ex: 192.168.100.151" 
                          {...field} 
                          data-testid="collector-ip-input"
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <div className="md:col-span-1">
                  <Label>Sistema Operacional</Label>
                  <Select defaultValue="ubuntu">
                    <SelectTrigger data-testid="collector-os-select">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ubuntu">Ubuntu 20.04+</SelectItem>
                      <SelectItem value="debian">Debian 11+</SelectItem>
                      <SelectItem value="centos">CentOS 8+</SelectItem>
                      <SelectItem value="rhel">RHEL 8+</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <FormField
                control={form.control}
                name="description"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Descrição</FormLabel>
                    <FormControl>
                      <Textarea 
                        placeholder="Descreva o ambiente onde este coletor será instalado..."
                        {...field}
                        data-testid="collector-description-input"
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <div className="flex justify-end space-x-3">
                <Button type="button" variant="outline" onClick={handleClose}>
                  Cancelar
                </Button>
                <Button 
                  type="submit" 
                  disabled={createCollectorMutation.isPending}
                  data-testid="create-collector-button"
                >
                  {createCollectorMutation.isPending ? 'Criando...' : 'Criar Coletor'}
                </Button>
              </div>
            </form>
          </Form>
        ) : (
          /* Step 2: Deployment Instructions */
          <div className="space-y-6">
            {/* Collector Details */}
            <Card className="bg-green-500/10 border-green-500/20">
              <CardContent className="p-4">
                <div className="flex items-center space-x-2 mb-3">
                  <CheckCircle className="text-green-500" size={20} />
                  <span className="font-medium text-green-500">Coletor criado com sucesso!</span>
                </div>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-muted-foreground">Nome:</span>
                    <span className="ml-2 font-medium">{enrollmentData?.name}</span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">ID:</span>
                    <span className="ml-2 font-mono text-xs">{enrollmentData?.id}</span>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Enrollment Token */}
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Token de Enrollment</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex items-center space-x-2">
                  <Input 
                    value={enrollmentData?.enrollmentToken || ''} 
                    readOnly 
                    className="font-mono text-sm"
                    data-testid="enrollment-token"
                  />
                  <Button 
                    size="sm" 
                    variant="outline"
                    onClick={() => copyToClipboard(enrollmentData?.enrollmentToken || '')}
                    data-testid="copy-token-button"
                  >
                    <Copy className="h-4 w-4" />
                  </Button>
                </div>
                <p className="text-sm text-yellow-500">
                  ⚠️ Este token expira em 15 minutos. Salve-o em local seguro.
                </p>
              </CardContent>
            </Card>

            {/* Installation Methods */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              {/* Automated Script */}
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg flex items-center space-x-2">
                    <Download className="h-5 w-5" />
                    <span>Script Automatizado</span>
                  </CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  <p className="text-sm text-muted-foreground">
                    Script completo para instalação e configuração automática:
                  </p>
                  <div className="relative">
                    <pre className="bg-muted p-3 rounded text-xs overflow-x-auto">
                      {installScript}
                    </pre>
                    <Button
                      size="sm"
                      variant="outline"
                      className="absolute top-2 right-2"
                      onClick={() => copyToClipboard(installScript)}
                      data-testid="copy-script-button"
                    >
                      <Copy className="h-3 w-3" />
                    </Button>
                  </div>
                  <Button 
                    size="sm" 
                    className="w-full"
                    onClick={() => {
                      const blob = new Blob([installScript], { type: 'text/plain' });
                      const url = URL.createObjectURL(blob);
                      const a = document.createElement('a');
                      a.href = url;
                      a.download = `install-${enrollmentData?.name}.sh`;
                      a.click();
                    }}
                    data-testid="download-script-button"
                  >
                    <Download className="mr-2 h-4 w-4" />
                    Baixar Script
                  </Button>
                </CardContent>
              </Card>

              {/* Manual Instructions */}
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg flex items-center space-x-2">
                    <Terminal className="h-5 w-5" />
                    <span>Instruções Manuais</span>
                  </CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  <p className="text-sm text-muted-foreground">
                    Para instalação manual no Ubuntu:
                  </p>
                  <div className="relative">
                    <pre className="bg-muted p-3 rounded text-xs overflow-x-auto">
                      {ubuntuInstructions}
                    </pre>
                    <Button
                      size="sm"
                      variant="outline"
                      className="absolute top-2 right-2"
                      onClick={() => copyToClipboard(ubuntuInstructions)}
                      data-testid="copy-instructions-button"
                    >
                      <Copy className="h-3 w-3" />
                    </Button>
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Requirements */}
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Requisitos do Sistema</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
                  <div>
                    <h4 className="font-medium mb-2">Sistema Operacional</h4>
                    <ul className="space-y-1 text-muted-foreground">
                      <li>• Ubuntu 20.04+</li>
                      <li>• Debian 11+</li>
                      <li>• CentOS 8+</li>
                      <li>• RHEL 8+</li>
                    </ul>
                  </div>
                  <div>
                    <h4 className="font-medium mb-2">Hardware Mínimo</h4>
                    <ul className="space-y-1 text-muted-foreground">
                      <li>• 2 vCPU</li>
                      <li>• 4 GB RAM</li>
                      <li>• 30 GB disco</li>
                      <li>• Conectividade HTTPS</li>
                    </ul>
                  </div>
                  <div>
                    <h4 className="font-medium mb-2">Rede</h4>
                    <ul className="space-y-1 text-muted-foreground">
                      <li>• Saída 443/TCP para *.samureye.com.br</li>
                      <li>• Acesso aos alvos de teste</li>
                      <li>• Resolução DNS</li>
                      <li>• NTP sincronizado</li>
                    </ul>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Actions */}
            <div className="flex justify-end space-x-3">
              <Button variant="outline" onClick={handleClose}>
                Fechar
              </Button>
              <Button 
                onClick={() => setStep(1)}
                data-testid="create-another-button"
              >
                Criar Outro Coletor
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
