import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { insertTenantSchema } from "@shared/schema";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";
import { apiRequest } from "@/lib/queryClient";
import { useToast } from "@/hooks/use-toast";
import { z } from "zod";
import { Building2, Users, Plus, Trash2, Settings, Shield, LogOut, Edit } from "lucide-react";
import { useLocation } from "wouter";

const createTenantSchema = insertTenantSchema.extend({
  name: z.string().min(1, "Nome é obrigatório"),
  slug: z.string().min(1, "Slug é obrigatório").regex(/^[a-z0-9-]+$/, "Slug deve conter apenas letras minúsculas, números e hífens"),
});

type CreateTenantForm = z.infer<typeof createTenantSchema>;

// Admin Users List Component
function AdminUsersList() {
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [, setLocation] = useLocation();
  
  const { data: users = [], isLoading } = useQuery({
    queryKey: ["/api/admin/users"],
    retry: false,
  });

  const deleteUserMutation = useMutation({
    mutationFn: async (userId: string) => {
      const response = await apiRequest("DELETE", `/api/admin/users/${userId}`);
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/admin/users"] });
      toast({
        title: "Sucesso",
        description: "Usuário excluído com sucesso",
      });
    },
    onError: (error: any) => {
      toast({
        title: "Erro",
        description: error.message || "Erro ao excluir usuário",
        variant: "destructive",
      });
    },
  });

  const handleDeleteUser = (userId: string) => {
    if (confirm("Tem certeza que deseja excluir este usuário?")) {
      deleteUserMutation.mutate(userId);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
      </div>
    );
  }

  return (
    <div>
      {Array.isArray(users) && users.length > 0 ? (
        <div className="grid gap-4">
          {users.map((user: any) => (
            <Card key={user.id} data-testid={`card-user-${user.id}`}>
              <CardContent className="p-6">
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-4">
                    <div className="w-10 h-10 bg-primary/10 rounded-full flex items-center justify-center">
                      <Users className="h-5 w-5 text-primary" />
                    </div>
                    <div>
                      <h3 className="font-medium" data-testid={`text-user-name-${user.id}`}>
                        {user.firstName} {user.lastName}
                      </h3>
                      <p className="text-sm text-muted-foreground" data-testid={`text-user-email-${user.id}`}>
                        {user.email}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center space-x-2">
                    {user.isSocUser && (
                      <Badge variant="secondary" data-testid={`badge-soc-${user.id}`}>
                        <Shield className="h-3 w-3 mr-1" />
                        SOC
                      </Badge>
                    )}
                    <Badge variant={user.isActive ? "default" : "secondary"} data-testid={`badge-status-${user.id}`}>
                      {user.isActive ? "Ativo" : "Inativo"}
                    </Badge>
                    <Button 
                      variant="outline" 
                      size="sm"
                      onClick={() => setLocation(`/admin/users/${user.id}/edit`)}
                      data-testid={`button-edit-user-${user.id}`}
                    >
                      <Edit className="h-4 w-4" />
                    </Button>
                    <Button 
                      variant="outline" 
                      size="sm"
                      onClick={() => handleDeleteUser(user.id)}
                      data-testid={`button-delete-user-${user.id}`}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      ) : (
        <div className="text-center py-12">
          <Users className="mx-auto h-12 w-12 text-muted-foreground" />
          <h3 className="mt-4 text-lg font-semibold">Nenhum usuário encontrado</h3>
          <p className="mt-2 text-muted-foreground">
            Clique em "Criar Usuário" para adicionar novos usuários ao sistema.
          </p>
        </div>
      )}
    </div>
  );
}

export default function AdminDashboard() {
  const [createTenantDialogOpen, setCreateTenantDialogOpen] = useState(false);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [selectedTenant, setSelectedTenant] = useState<any>(null);
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [, setLocation] = useLocation();

  const form = useForm<CreateTenantForm>({
    resolver: zodResolver(createTenantSchema),
    defaultValues: {
      name: "",
      slug: "",
      description: "",
    },
  });

  const { data: tenants = [], isLoading: tenantsLoading } = useQuery({
    queryKey: ["/api/admin/tenants"],
    retry: false,
  });

  const { data: stats = {}, isLoading: statsLoading } = useQuery({
    queryKey: ["/api/admin/stats"],
    retry: false,
  });

  // Ensure data is properly typed
  const tenantList = Array.isArray(tenants) ? tenants : [];
  const statsData = stats as any;

  const createTenantMutation = useMutation({
    mutationFn: async (data: CreateTenantForm) => {
      const response = await apiRequest("POST", "/api/admin/tenants", data);
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/admin/tenants"] });
      queryClient.invalidateQueries({ queryKey: ["/api/admin/stats"] });
      setCreateTenantDialogOpen(false);
      form.reset();
      toast({
        title: "Sucesso",
        description: "Tenant criado com sucesso",
      });
    },
    onError: (error: any) => {
      toast({
        title: "Erro",
        description: error.message || "Erro ao criar tenant",
        variant: "destructive",
      });
    },
  });

  const deleteTenantMutation = useMutation({
    mutationFn: async (tenantId: string) => {
      const response = await apiRequest("DELETE", `/api/admin/tenants/${tenantId}`, {});
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/admin/tenants"] });
      queryClient.invalidateQueries({ queryKey: ["/api/admin/stats"] });
      setDeleteDialogOpen(false);
      setSelectedTenant(null);
      toast({
        title: "Sucesso",
        description: "Tenant excluído com sucesso",
      });
    },
    onError: (error: any) => {
      toast({
        title: "Erro",
        description: error.message || "Erro ao excluir tenant",
        variant: "destructive",
      });
    },
  });

  const handleLogout = async () => {
    try {
      await apiRequest("POST", "/api/admin/logout", {});
      // Force page reload to clear all session data
      window.location.href = "/admin";
    } catch (error) {
      console.error("Logout error:", error);
      window.location.href = "/admin";
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      {/* Header */}
      <header className="bg-white dark:bg-gray-800 shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <Shield className="h-8 w-8 text-primary mr-3" />
              <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                SamurEye Admin
              </h1>
            </div>
            <div className="flex items-center space-x-2">
              <Button 
                variant="ghost" 
                onClick={() => setLocation('/admin/settings')}
                data-testid="button-settings"
              >
                <Settings className="h-4 w-4 mr-2" />
                Configurações
              </Button>
              <Button variant="ghost" onClick={handleLogout} data-testid="button-logout">
                <LogOut className="h-4 w-4 mr-2" />
                Sair
              </Button>
            </div>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <Tabs defaultValue="tenants" className="space-y-6">
          <TabsList>
            <TabsTrigger value="tenants">Gestão de Tenants</TabsTrigger>
            <TabsTrigger value="users">Gestão de Usuários</TabsTrigger>
          </TabsList>

          <TabsContent value="tenants" className="space-y-6">
            {/* Stats Cards */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Total Tenants</CardTitle>
                  <Building2 className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">{statsData.totalTenants || 0}</div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Tenants Ativos</CardTitle>
                  <Building2 className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">{statsData.activeTenants || 0}</div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Total Usuários</CardTitle>
                  <Users className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">{statsData.totalUsers || 0}</div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Usuários SOC</CardTitle>
                  <Shield className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">{statsData.socUsers || 0}</div>
                </CardContent>
              </Card>
            </div>

            {/* Tenants Management */}
            <div className="flex justify-between items-center">
              <h2 className="text-xl font-semibold">Tenants</h2>
              <Dialog open={createTenantDialogOpen} onOpenChange={setCreateTenantDialogOpen}>
                <DialogTrigger asChild>
                  <Button data-testid="button-create-tenant">
                    <Plus className="mr-2 h-4 w-4" />
                    Criar Tenant
                  </Button>
                </DialogTrigger>
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>Criar Novo Tenant</DialogTitle>
                    <DialogDescription>
                      Adicione um novo tenant ao sistema
                    </DialogDescription>
                  </DialogHeader>
                  
                  <Form {...form}>
                    <form onSubmit={form.handleSubmit((data) => createTenantMutation.mutate(data))} className="space-y-4">
                      <FormField
                        control={form.control}
                        name="name"
                        render={({ field }) => (
                          <FormItem>
                            <FormLabel>Nome</FormLabel>
                            <FormControl>
                              <Input 
                                placeholder="Nome do tenant" 
                                data-testid="input-tenant-name"
                                {...field} 
                              />
                            </FormControl>
                            <FormMessage />
                          </FormItem>
                        )}
                      />
                      
                      <FormField
                        control={form.control}
                        name="slug"
                        render={({ field }) => (
                          <FormItem>
                            <FormLabel>Slug</FormLabel>
                            <FormControl>
                              <Input 
                                placeholder="slug-do-tenant" 
                                data-testid="input-tenant-slug"
                                {...field} 
                              />
                            </FormControl>
                            <FormMessage />
                          </FormItem>
                        )}
                      />
                      
                      <FormField
                        control={form.control}
                        name="description"
                        render={({ field }) => (
                          <FormItem>
                            <FormLabel>Descrição</FormLabel>
                            <FormControl>
                              <Textarea 
                                placeholder="Descrição do tenant" 
                                data-testid="input-tenant-description"
                                {...field}
                                value={field.value || ""}
                              />
                            </FormControl>
                            <FormMessage />
                          </FormItem>
                        )}
                      />
                      
                      <DialogFooter>
                        <Button 
                          type="button" 
                          variant="outline" 
                          onClick={() => setCreateTenantDialogOpen(false)}
                          data-testid="button-cancel"
                        >
                          Cancelar
                        </Button>
                        <Button 
                          type="submit" 
                          disabled={createTenantMutation.isPending}
                          data-testid="button-submit-tenant"
                        >
                          {createTenantMutation.isPending ? "Criando..." : "Criar"}
                        </Button>
                      </DialogFooter>
                    </form>
                  </Form>
                </DialogContent>
              </Dialog>
            </div>

            <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
              {tenantList.map((tenant: any) => (
                <Card key={tenant.id} data-testid={`card-tenant-${tenant.id}`}>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <CardTitle className="flex items-center gap-2">
                        <Building2 className="h-5 w-5" />
                        {tenant.name}
                      </CardTitle>
                      <Badge variant={tenant.isActive ? "default" : "secondary"}>
                        {tenant.isActive ? "Ativo" : "Inativo"}
                      </Badge>
                    </div>
                    <CardDescription>{tenant.description || "Sem descrição"}</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <div className="space-y-2 text-sm">
                      <div className="flex justify-between">
                        <span className="text-muted-foreground">Slug:</span>
                        <span className="font-mono" data-testid={`text-tenant-slug-${tenant.id}`}>
                          {tenant.slug}
                        </span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-muted-foreground">Usuários:</span>
                        <span data-testid={`text-tenant-users-${tenant.id}`}>
                          {tenant._count?.tenantUsers || 0}
                        </span>
                      </div>
                    </div>
                    
                    <div className="flex gap-2 mt-4">
                      <Button 
                        variant="outline" 
                        size="sm" 
                        className="flex-1"
                        onClick={() => {
                          // Navegar para a aba de usuários do dashboard
                          const tabsElement = document.querySelector('[data-tabs-value="users"]');
                          if (tabsElement) {
                            (tabsElement as HTMLElement).click();
                          }
                        }}
                        data-testid={`button-users-${tenant.id}`}
                      >
                        <Users className="mr-2 h-4 w-4" />
                        Usuários
                      </Button>
                      <Button 
                        variant="outline" 
                        size="sm"
                        onClick={() => {
                          setSelectedTenant(tenant);
                          setDeleteDialogOpen(true);
                        }}
                        data-testid={`button-delete-${tenant.id}`}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </TabsContent>

          <TabsContent value="users">
            <div className="space-y-6">
              <div className="flex justify-between items-center">
                <h2 className="text-xl font-semibold">Usuários do Sistema</h2>
                <Button onClick={() => setLocation("/admin/users/create")} data-testid="button-create-user">
                  <Plus className="mr-2 h-4 w-4" />
                  Criar Usuário
                </Button>
              </div>
              <AdminUsersList />
            </div>
          </TabsContent>
        </Tabs>
      </div>

      {/* Delete Confirmation Dialog */}
      <Dialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confirmar Exclusão</DialogTitle>
            <DialogDescription>
              Tem certeza que deseja excluir o tenant "{selectedTenant?.name}"? 
              Esta ação não pode ser desfeita e todos os dados relacionados serão perdidos.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button 
              variant="outline" 
              onClick={() => setDeleteDialogOpen(false)}
              data-testid="button-cancel-delete"
            >
              Cancelar
            </Button>
            <Button 
              variant="destructive"
              onClick={() => selectedTenant && deleteTenantMutation.mutate(selectedTenant.id)}
              disabled={deleteTenantMutation.isPending}
              data-testid="button-confirm-delete"
            >
              {deleteTenantMutation.isPending ? "Excluindo..." : "Excluir"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}