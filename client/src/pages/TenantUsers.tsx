import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";
import { apiRequest } from "@/lib/queryClient";
import { useToast } from "@/hooks/use-toast";
import { useAuth } from "@/hooks/useAuth";
import { z } from "zod";
import { Users, Plus, UserPlus, Shield, Eye, Settings, FileText } from "lucide-react";

const createUserSchema = z.object({
  email: z.string().email("Email inválido"),
  firstName: z.string().min(1, "Nome é obrigatório"),
  lastName: z.string().min(1, "Sobrenome é obrigatório"),
  role: z.enum(["tenant_admin", "operator", "viewer", "tenant_auditor"]),
});

type CreateUserForm = z.infer<typeof createUserSchema>;

const roleLabels = {
  tenant_admin: "Administrador",
  operator: "Operador",
  viewer: "Visualizador",
  tenant_auditor: "Auditor"
};

const roleIcons = {
  tenant_admin: Shield,
  operator: Settings,
  viewer: Eye,
  tenant_auditor: FileText
};

export default function TenantUsers() {
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [selectedUser, setSelectedUser] = useState<any>(null);
  const [roleDialogOpen, setRoleDialogOpen] = useState(false);
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const { user } = useAuth();

  const form = useForm<CreateUserForm>({
    resolver: zodResolver(createUserSchema),
    defaultValues: {
      email: "",
      firstName: "",
      lastName: "",
      role: "viewer",
    },
  });

  const { data: tenantUsers = [], isLoading } = useQuery({
    queryKey: ["/api/tenant/users"],
    retry: false,
  });

  // Ensure tenantUsers is always an array
  const userList = Array.isArray(tenantUsers) ? tenantUsers : [];

  const createUserMutation = useMutation({
    mutationFn: async (data: CreateUserForm) => {
      const response = await apiRequest("POST", "/api/tenant/users", data);
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/tenant/users"] });
      setCreateDialogOpen(false);
      form.reset();
      toast({
        title: "Sucesso",
        description: "Usuário convidado com sucesso",
      });
    },
    onError: (error) => {
      toast({
        title: "Erro",
        description: "Falha ao convidar usuário",
        variant: "destructive",
      });
    },
  });

  const updateRoleMutation = useMutation({
    mutationFn: async ({ userId, role }: { userId: string; role: string }) => {
      return apiRequest(`/api/tenant/users/${userId}/role`, "PUT", { role });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/tenant/users"] });
      setRoleDialogOpen(false);
      setSelectedUser(null);
      toast({
        title: "Sucesso",
        description: "Função do usuário atualizada",
      });
    },
    onError: (error) => {
      toast({
        title: "Erro",
        description: "Falha ao atualizar função",
        variant: "destructive",
      });
    },
  });

  const handleCreateUser = (data: CreateUserForm) => {
    createUserMutation.mutate(data);
  };

  const handleUpdateRole = (role: string) => {
    if (selectedUser) {
      updateRoleMutation.mutate({ userId: selectedUser.userId, role });
    }
  };

  if (isLoading) {
    return (
      <div className="container mx-auto py-6">
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-32 w-32 border-b-2 border-primary"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto py-6" data-testid="tenant-users-page">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold tracking-tight" data-testid="page-title">
            Usuários do Tenant
          </h1>
          <p className="text-muted-foreground">
            Gerencie usuários e suas funções
          </p>
        </div>
        
        <Dialog open={createDialogOpen} onOpenChange={setCreateDialogOpen}>
          <DialogTrigger asChild>
            <Button data-testid="button-invite-user">
              <UserPlus className="mr-2 h-4 w-4" />
              Convidar Usuário
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Convidar Usuário</DialogTitle>
              <DialogDescription>
                Adicione um novo usuário ao tenant
              </DialogDescription>
            </DialogHeader>
            
            <Form {...form}>
              <form onSubmit={form.handleSubmit(handleCreateUser)} className="space-y-4">
                <FormField
                  control={form.control}
                  name="email"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Email</FormLabel>
                      <FormControl>
                        <Input 
                          type="email"
                          placeholder="usuario@exemplo.com" 
                          data-testid="input-user-email"
                          {...field} 
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                
                <div className="grid grid-cols-2 gap-4">
                  <FormField
                    control={form.control}
                    name="firstName"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Nome</FormLabel>
                        <FormControl>
                          <Input 
                            placeholder="João" 
                            data-testid="input-user-firstname"
                            {...field} 
                          />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                  
                  <FormField
                    control={form.control}
                    name="lastName"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Sobrenome</FormLabel>
                        <FormControl>
                          <Input 
                            placeholder="Silva" 
                            data-testid="input-user-lastname"
                            {...field} 
                          />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                </div>
                
                <FormField
                  control={form.control}
                  name="role"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Função</FormLabel>
                      <Select onValueChange={field.onChange} defaultValue={field.value}>
                        <FormControl>
                          <SelectTrigger data-testid="select-user-role">
                            <SelectValue placeholder="Selecione uma função" />
                          </SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          <SelectItem value="viewer">Visualizador</SelectItem>
                          <SelectItem value="operator">Operador</SelectItem>
                          <SelectItem value="tenant_auditor">Auditor</SelectItem>
                          <SelectItem value="tenant_admin">Administrador</SelectItem>
                        </SelectContent>
                      </Select>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                
                <DialogFooter>
                  <Button 
                    type="button" 
                    variant="outline" 
                    onClick={() => setCreateDialogOpen(false)}
                    data-testid="button-cancel"
                  >
                    Cancelar
                  </Button>
                  <Button 
                    type="submit" 
                    disabled={createUserMutation.isPending}
                    data-testid="button-submit-user"
                  >
                    {createUserMutation.isPending ? "Enviando..." : "Convidar"}
                  </Button>
                </DialogFooter>
              </form>
            </Form>
          </DialogContent>
        </Dialog>
      </div>

      <div className="grid gap-4">
        {userList.map((tenantUser: any) => {
          const RoleIcon = roleIcons[tenantUser.role as keyof typeof roleIcons];
          return (
            <Card key={tenantUser.id} data-testid={`card-user-${tenantUser.id}`}>
              <CardContent className="p-6">
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-4">
                    <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                      <Users className="h-5 w-5 text-primary" />
                    </div>
                    <div>
                      <h3 className="font-semibold" data-testid={`text-user-name-${tenantUser.id}`}>
                        {tenantUser.user.firstName} {tenantUser.user.lastName}
                      </h3>
                      <p className="text-sm text-muted-foreground" data-testid={`text-user-email-${tenantUser.id}`}>
                        {tenantUser.user.email}
                      </p>
                    </div>
                  </div>
                  
                  <div className="flex items-center space-x-3">
                    <Badge 
                      variant="secondary" 
                      className="flex items-center gap-1"
                      data-testid={`badge-user-role-${tenantUser.id}`}
                    >
                      <RoleIcon className="h-3 w-3" />
                      {roleLabels[tenantUser.role as keyof typeof roleLabels]}
                    </Badge>
                    
                    <Badge variant={tenantUser.isActive ? "default" : "secondary"}>
                      {tenantUser.isActive ? "Ativo" : "Inativo"}
                    </Badge>
                    
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => {
                        setSelectedUser(tenantUser);
                        setRoleDialogOpen(true);
                      }}
                      data-testid={`button-edit-role-${tenantUser.id}`}
                    >
                      <Settings className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>

      {userList.length === 0 && (
        <div className="text-center py-12">
          <Users className="mx-auto h-12 w-12 text-muted-foreground" />
          <h3 className="mt-4 text-lg font-semibold">Nenhum usuário encontrado</h3>
          <p className="mt-2 text-muted-foreground">
            Comece convidando usuários para o tenant.
          </p>
        </div>
      )}

      {/* Role Update Dialog */}
      <Dialog open={roleDialogOpen} onOpenChange={setRoleDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Alterar Função do Usuário</DialogTitle>
            <DialogDescription>
              Selecione a nova função para {selectedUser?.user.firstName} {selectedUser?.user.lastName}
            </DialogDescription>
          </DialogHeader>
          
          <div className="space-y-4">
            {Object.entries(roleLabels).map(([value, label]) => {
              const RoleIcon = roleIcons[value as keyof typeof roleIcons];
              return (
                <Button
                  key={value}
                  variant={selectedUser?.role === value ? "default" : "outline"}
                  className="w-full justify-start"
                  onClick={() => handleUpdateRole(value)}
                  disabled={updateRoleMutation.isPending}
                  data-testid={`button-role-${value}`}
                >
                  <RoleIcon className="mr-2 h-4 w-4" />
                  {label}
                </Button>
              );
            })}
          </div>
          
          <DialogFooter>
            <Button 
              variant="outline" 
              onClick={() => setRoleDialogOpen(false)}
              data-testid="button-cancel-role"
            >
              Cancelar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}