import { useState } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Settings, Save } from 'lucide-react';
import { LogoUploader } from '@/components/admin/LogoUploader';
import { apiRequest, queryClient } from '@/lib/queryClient';
import { useToast } from '@/hooks/use-toast';

interface SystemSettings {
  id: string;
  logoUrl: string | null;
  systemName: string;
  systemDescription: string;
  supportEmail: string;
  updatedAt: string;
}

export default function AdminSettings() {
  const { toast } = useToast();
  const [systemName, setSystemName] = useState('');
  const [systemDescription, setSystemDescription] = useState('');
  const [supportEmail, setSupportEmail] = useState('');

  const { data: settings, isLoading } = useQuery<SystemSettings>({
    queryKey: ['/api/admin/settings'],
    onSuccess: (data) => {
      setSystemName(data.systemName || 'SamurEye');
      setSystemDescription(data.systemDescription || '');
      setSupportEmail(data.supportEmail || '');
    },
  });

  const updateSettingsMutation = useMutation({
    mutationFn: async (data: Partial<SystemSettings>) => {
      const response = await apiRequest('PUT', '/api/admin/settings', data);
      return await response.json();
    },
    onSuccess: () => {
      toast({
        title: 'Configurações salvas',
        description: 'As configurações do sistema foram atualizadas.',
      });
      queryClient.invalidateQueries({ queryKey: ['/api/admin/settings'] });
    },
    onError: (error: Error) => {
      toast({
        title: 'Erro ao salvar',
        description: error.message,
        variant: 'destructive',
      });
    },
  });

  const handleSaveSettings = () => {
    updateSettingsMutation.mutate({
      systemName,
      systemDescription,
      supportEmail,
    });
  };

  if (isLoading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center gap-2">
          <Settings className="w-6 h-6" />
          <h1 className="text-2xl font-bold">Configurações do Sistema</h1>
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {[...Array(2)].map((_, i) => (
            <Card key={i} className="animate-pulse">
              <CardContent className="p-6">
                <div className="h-32 bg-muted rounded"></div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6" data-testid="admin-settings">
      <div className="flex items-center gap-2">
        <Settings className="w-6 h-6" />
        <h1 className="text-2xl font-bold">Configurações do Sistema</h1>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Logo Upload */}
        <LogoUploader
          title="Logo do SamurEye"
          currentLogo={settings?.logoUrl}
          uploadEndpoint="/api/admin/settings"
          type="system"
        />

        {/* System Settings */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Settings className="w-5 h-5" />
              Configurações Gerais
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="systemName">Nome do Sistema</Label>
              <Input
                id="systemName"
                value={systemName}
                onChange={(e) => setSystemName(e.target.value)}
                placeholder="SamurEye"
                data-testid="input-system-name"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="systemDescription">Descrição</Label>
              <Input
                id="systemDescription"
                value={systemDescription}
                onChange={(e) => setSystemDescription(e.target.value)}
                placeholder="Plataforma de Simulação de Ataques"
                data-testid="input-system-description"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="supportEmail">Email de Suporte</Label>
              <Input
                id="supportEmail"
                type="email"
                value={supportEmail}
                onChange={(e) => setSupportEmail(e.target.value)}
                placeholder="suporte@samureye.com.br"
                data-testid="input-support-email"
              />
            </div>

            <Button
              onClick={handleSaveSettings}
              disabled={updateSettingsMutation.isPending}
              className="w-full"
              data-testid="button-save-settings"
            >
              <Save className="w-4 h-4 mr-2" />
              {updateSettingsMutation.isPending ? 'Salvando...' : 'Salvar Configurações'}
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}