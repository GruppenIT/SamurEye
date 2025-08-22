import { useState, useEffect } from 'react';
import { useParams, useLocation } from 'wouter';
import { useQuery, useMutation } from '@tanstack/react-query';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { User, Save, ArrowLeft, Plus, X, Key } from 'lucide-react';
import { apiRequest, queryClient } from '@/lib/queryClient';
import { useToast } from '@/hooks/use-toast';

interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  isSocUser: boolean;
  isActive: boolean;
  tenants: Array<{
    tenantId: string;
    role: string;
    tenant: {
      id: string;
      name: string;
    };
  }>;
}

interface Tenant {
  id: string;
  name: string;
}

export default function AdminUserEdit() {
  const params = useParams();
  const [, setLocation] = useLocation();
  const { toast } = useToast();
  const userId = params.id;

  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [email, setEmail] = useState('');
  const [isSocUser, setIsSocUser] = useState(false);
  const [isActive, setIsActive] = useState(true);
  const [newPassword, setNewPassword] = useState('');
  const [userTenants, setUserTenants] = useState<Array<{tenantId: string, role: string}>>([]);
  const [selectedTenant, setSelectedTenant] = useState('');
  const [selectedRole, setSelectedRole] = useState('');

  const { data: user, isLoading: userLoading } = useQuery<User>({
    queryKey: ['/api/admin/users', userId],
    enabled: !!userId,
  });

  // Load user data when it arrives
  useEffect(() => {
    if (user) {
      setFirstName(user.firstName);
      setLastName(user.lastName);
      setEmail(user.email);
      setIsSocUser(user.isSocUser);
      setIsActive(user.isActive);
      setUserTenants(user.tenants.map(t => ({ tenantId: t.tenantId, role: t.role })));
    }
  }, [user]);

  const { data: allTenants } = useQuery<Tenant[]>({
    queryKey: ['/api/admin/tenants'],
  });

  const updateUserMutation = useMutation({
    mutationFn: async (data: any) => {
      const response = await apiRequest('PUT', `/api/admin/users/${userId}`, data);
      return await response.json();
    },
    onSuccess: () => {
      toast({
        title: 'Usuário atualizado',
        description: 'As informações do usuário foram salvas.',
      });
      queryClient.invalidateQueries({ queryKey: ['/api/admin/users'] });
      setLocation('/admin/dashboard');
    },
    onError: (error: Error) => {
      toast({
        title: 'Erro ao atualizar',
        description: error.message,
        variant: 'destructive',
      });
    },
  });

  const handleSave = () => {
    const updateData: any = {
      firstName,
      lastName,
      email,
      isSocUser,
      isActive,
      tenants: userTenants,
    };

    if (newPassword.trim()) {
      updateData.password = newPassword;
    }

    updateUserMutation.mutate(updateData);
  };

  const handleAddTenant = () => {
    if (selectedTenant && selectedRole) {
      const exists = userTenants.some(t => t.tenantId === selectedTenant);
      if (!exists) {
        setUserTenants([...userTenants, { tenantId: selectedTenant, role: selectedRole }]);
        setSelectedTenant('');
        setSelectedRole('');
      }
    }
  };

  const handleRemoveTenant = (tenantId: string) => {
    setUserTenants(userTenants.filter(t => t.tenantId !== tenantId));
  };

  const getTenantName = (tenantId: string) => {
    return allTenants?.find(t => t.id === tenantId)?.name || 'Tenant não encontrado';
  };

  const getRoleLabel = (role: string) => {
    const roles: Record<string, string> = {
      'tenant_admin': 'Administrador',
      'operator': 'Operador',
      'viewer': 'Visualizador',
      'tenant_auditor': 'Auditor',
      'soc_operator': 'Operador SOC'
    };
    return roles[role] || role;
  };

  if (userLoading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center gap-2">
          <User className="w-6 h-6" />
          <h1 className="text-2xl font-bold">Editando Usuário</h1>
        </div>
        <Card className="animate-pulse">
          <CardContent className="p-6">
            <div className="h-96 bg-muted rounded"></div>
          </CardContent>
        </Card>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="flex flex-col items-center justify-center h-96 space-y-4">
        <User className="w-12 h-12 text-muted-foreground" />
        <p className="text-lg text-muted-foreground">Usuário não encontrado</p>
        <Button onClick={() => setLocation('/admin/dashboard')}>
          <ArrowLeft className="w-4 h-4 mr-2" />
          Voltar
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6" data-testid="admin-user-edit">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <User className="w-6 h-6" />
          <h1 className="text-2xl font-bold">Editando: {user.firstName} {user.lastName}</h1>
        </div>
        <Button variant="outline" onClick={() => setLocation('/admin/dashboard')}>
          <ArrowLeft className="w-4 h-4 mr-2" />
          Voltar
        </Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* User Information */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <User className="w-5 h-5" />
              Informações do Usuário
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="firstName">Nome</Label>
              <Input
                id="firstName"
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                data-testid="input-first-name"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="lastName">Sobrenome</Label>
              <Input
                id="lastName"
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                data-testid="input-last-name"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                data-testid="input-email"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="newPassword">Nova Senha (deixe vazio para manter)</Label>
              <Input
                id="newPassword"
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                placeholder="Digite uma nova senha"
                data-testid="input-new-password"
              />
            </div>

            <div className="flex items-center justify-between">
              <Label htmlFor="isSocUser">Usuário SOC (acesso a todos os tenants)</Label>
              <Switch
                id="isSocUser"
                checked={isSocUser}
                onCheckedChange={setIsSocUser}
                data-testid="switch-soc-user"
              />
            </div>

            <div className="flex items-center justify-between">
              <Label htmlFor="isActive">Usuário Ativo</Label>
              <Switch
                id="isActive"
                checked={isActive}
                onCheckedChange={setIsActive}
                data-testid="switch-active"
              />
            </div>
          </CardContent>
        </Card>

        {/* Tenant Associations */}
        <Card>
          <CardHeader>
            <CardTitle>Vínculos com Tenants</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Add Tenant */}
            <div className="space-y-3">
              <div className="space-y-2">
                <Label>Adicionar Tenant</Label>
                <Select value={selectedTenant} onValueChange={setSelectedTenant}>
                  <SelectTrigger data-testid="select-tenant">
                    <SelectValue placeholder="Selecione um tenant" />
                  </SelectTrigger>
                  <SelectContent>
                    {allTenants?.filter(t => !userTenants.some(ut => ut.tenantId === t.id)).map(tenant => (
                      <SelectItem key={tenant.id} value={tenant.id}>
                        {tenant.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label>Role</Label>
                <Select value={selectedRole} onValueChange={setSelectedRole}>
                  <SelectTrigger data-testid="select-role">
                    <SelectValue placeholder="Selecione uma role" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="tenant_admin">Administrador</SelectItem>
                    <SelectItem value="operator">Operador</SelectItem>
                    <SelectItem value="viewer">Visualizador</SelectItem>
                    <SelectItem value="tenant_auditor">Auditor</SelectItem>
                    <SelectItem value="soc_operator">Operador SOC</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <Button
                onClick={handleAddTenant}
                disabled={!selectedTenant || !selectedRole}
                className="w-full"
                data-testid="button-add-tenant"
              >
                <Plus className="w-4 h-4 mr-2" />
                Adicionar Vínculo
              </Button>
            </div>

            {/* Current Tenants */}
            <div className="space-y-2">
              <Label>Tenants Vinculados</Label>
              <div className="space-y-2">
                {userTenants.map((userTenant) => (
                  <div
                    key={userTenant.tenantId}
                    className="flex items-center justify-between p-3 border rounded-lg"
                  >
                    <div className="space-y-1">
                      <p className="font-medium">{getTenantName(userTenant.tenantId)}</p>
                      <Badge variant="secondary">{getRoleLabel(userTenant.role)}</Badge>
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleRemoveTenant(userTenant.tenantId)}
                      data-testid={`button-remove-tenant-${userTenant.tenantId}`}
                    >
                      <X className="w-4 h-4" />
                    </Button>
                  </div>
                ))}
                {userTenants.length === 0 && (
                  <p className="text-sm text-muted-foreground py-4 text-center">
                    Nenhum tenant vinculado
                  </p>
                )}
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="flex justify-end">
        <Button
          onClick={handleSave}
          disabled={updateUserMutation.isPending}
          size="lg"
          data-testid="button-save-user"
        >
          <Save className="w-4 h-4 mr-2" />
          {updateUserMutation.isPending ? 'Salvando...' : 'Salvar Alterações'}
        </Button>
      </div>
    </div>
  );
}