import { useState, useEffect } from 'react';
import { useParams, useLocation } from 'wouter';
import { useQuery, useMutation } from '@tanstack/react-query';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Building2, Save, ArrowLeft, Upload } from 'lucide-react';
import { apiRequest, queryClient } from '@/lib/queryClient';
import { useToast } from '@/hooks/use-toast';
import { LogoUploader } from '@/components/admin/LogoUploader';

interface Tenant {
  id: string;
  name: string;
  slug: string;
  description?: string;
  logoUrl?: string;
  isActive: boolean;
}

export default function AdminTenantEdit() {
  const params = useParams();
  const [, setLocation] = useLocation();
  const { toast } = useToast();
  const tenantId = params.tenantId;

  const [name, setName] = useState('');
  const [slug, setSlug] = useState('');
  const [description, setDescription] = useState('');
  const [logoUrl, setLogoUrl] = useState('');
  const [isActive, setIsActive] = useState(true);

  const { data: tenant, isLoading: tenantLoading } = useQuery<Tenant>({
    queryKey: ['/api/admin/tenants', tenantId],
    enabled: !!tenantId,
  });

  // Load tenant data when it arrives
  useEffect(() => {
    if (tenant) {
      setName(tenant.name);
      setSlug(tenant.slug);
      setDescription(tenant.description || '');
      setLogoUrl(tenant.logoUrl || '');
      setIsActive(tenant.isActive);
    }
  }, [tenant]);

  const updateTenantMutation = useMutation({
    mutationFn: async (data: any) => {
      const response = await apiRequest('PUT', `/api/admin/tenants/${tenantId}`, data);
      return await response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['/api/admin/tenants'] });
      toast({
        title: 'Sucesso',
        description: 'Tenant atualizado com sucesso',
      });
      setLocation('/admin/dashboard');
    },
    onError: (error: any) => {
      toast({
        title: 'Erro',
        description: error.message || 'Erro ao atualizar tenant',
        variant: 'destructive',
      });
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    updateTenantMutation.mutate({
      name,
      slug,
      description,
      logoUrl,
      isActive,
    });
  };

  if (tenantLoading) {
    return (
      <div className="min-h-screen bg-gray-50 dark:bg-gray-900 flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      {/* Header */}
      <header className="bg-white dark:bg-gray-800 shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center py-6">
            <Button
              variant="ghost"
              onClick={() => setLocation('/admin/dashboard')}
              className="mr-4"
              data-testid="button-back"
            >
              <ArrowLeft className="h-4 w-4 mr-2" />
              Voltar
            </Button>
            <div className="flex items-center">
              <Building2 className="h-8 w-8 text-primary mr-3" />
              <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                Editar Tenant
              </h1>
            </div>
          </div>
        </div>
      </header>

      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Basic Information */}
          <Card>
            <CardHeader>
              <CardTitle>Informações Básicas</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="name">Nome do Tenant</Label>
                  <Input
                    id="name"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="Nome do tenant"
                    required
                    data-testid="input-tenant-name"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="slug">Slug</Label>
                  <Input
                    id="slug"
                    value={slug}
                    onChange={(e) => setSlug(e.target.value)}
                    placeholder="slug-do-tenant"
                    required
                    data-testid="input-tenant-slug"
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="description">Descrição</Label>
                <Textarea
                  id="description"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Descrição do tenant"
                  rows={3}
                  data-testid="input-tenant-description"
                />
              </div>
              <div className="flex items-center space-x-2">
                <Switch
                  id="is-active"
                  checked={isActive}
                  onCheckedChange={setIsActive}
                  data-testid="switch-tenant-active"
                />
                <Label htmlFor="is-active">Tenant Ativo</Label>
              </div>
            </CardContent>
          </Card>

          {/* Logo Upload */}
          <Card>
            <CardHeader>
              <CardTitle>Logo do Tenant</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {logoUrl && (
                <div className="flex items-center space-x-4">
                  <img
                    src={logoUrl}
                    alt="Logo atual"
                    className="w-16 h-16 object-contain border rounded"
                    data-testid="image-current-logo"
                  />
                  <span className="text-sm text-muted-foreground">Logo atual</span>
                </div>
              )}
              <LogoUploader
                title="Logo do Tenant"
                currentLogo={logoUrl}
                uploadEndpoint={`/api/admin/tenants/${tenantId}`}
                onSuccess={() => window.location.reload()}
                type="tenant"
                entityId={tenantId}
              />
            </CardContent>
          </Card>

          {/* Save Button */}
          <div className="flex justify-end space-x-4">
            <Button
              type="button"
              variant="outline"
              onClick={() => setLocation('/admin/dashboard')}
              data-testid="button-cancel"
            >
              Cancelar
            </Button>
            <Button
              type="submit"
              disabled={updateTenantMutation.isPending}
              data-testid="button-save"
            >
              <Save className="mr-2 h-4 w-4" />
              {updateTenantMutation.isPending ? 'Salvando...' : 'Salvar'}
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
}