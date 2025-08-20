import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";
import { apiRequest } from "@/lib/queryClient";
import { useToast } from "@/hooks/use-toast";
import { insertTenantSchema } from "@shared/schema";
import { z } from "zod";
import { Building2, Users, Plus, Activity } from "lucide-react";

const createTenantSchema = insertTenantSchema.extend({
  name: z.string().min(1, "Nome é obrigatório"),
  slug: z.string().min(1, "Slug é obrigatório").regex(/^[a-z0-9-]+$/, "Slug deve conter apenas letras minúsculas, números e hífens"),
});

type CreateTenantForm = z.infer<typeof createTenantSchema>;

export default function GlobalAdmin() {
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const form = useForm<CreateTenantForm>({
    resolver: zodResolver(createTenantSchema),
    defaultValues: {
      name: "",
      slug: "",
      description: "",
    },
  });

  const { data: tenants = [], isLoading } = useQuery({
    queryKey: ["/api/admin/tenants"],
    retry: false,
  });

  // Ensure tenants is always an array
  const tenantList = Array.isArray(tenants) ? tenants : [];

  const createTenantMutation = useMutation({
    mutationFn: async (data: CreateTenantForm) => {
      console.log("Sending tenant data:", data);
      return apiRequest("/api/admin/tenants", "POST", data);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/admin/tenants"] });
      setCreateDialogOpen(false);
      form.reset();
      toast({
        title: "Sucesso",
        description: "Tenant criado com sucesso",
      });
    },
    onError: (error: any) => {
      console.error("Tenant creation error:", error);
      toast({
        title: "Erro",
        description: error?.message || "Falha ao criar tenant",
        variant: "destructive",
      });
    },
  });

  const seedExampleData = async (tenantId: string) => {
    try {
      await apiRequest("/api/admin/seed-example-data", "POST", { tenantId });
      toast({
        title: "Sucesso",
        description: "Dados de exemplo criados com sucesso",
      });
    } catch (error) {
      toast({
        title: "Erro", 
        description: "Falha ao criar dados de exemplo",
        variant: "destructive",
      });
    }
  };

  const handleCreateTenant = (data: CreateTenantForm) => {
    createTenantMutation.mutate(data);
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
    <div className="container mx-auto py-6" data-testid="global-admin-page">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold tracking-tight" data-testid="page-title">
            Administração Global
          </h1>
          <p className="text-muted-foreground">
            Gerencie tenants e configurações do sistema
          </p>
        </div>
        
        <Dialog open={createDialogOpen} onOpenChange={setCreateDialogOpen}>
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
              <form onSubmit={form.handleSubmit(handleCreateTenant)} className="space-y-4">
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
                    onClick={() => setCreateDialogOpen(false)}
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
                  <span className="text-muted-foreground">Criado:</span>
                  <span data-testid={`text-tenant-created-${tenant.id}`}>
                    {new Date(tenant.createdAt).toLocaleDateString('pt-BR')}
                  </span>
                </div>
              </div>
              
              <div className="flex gap-2 mt-4">
                <Button 
                  variant="outline" 
                  size="sm" 
                  className="flex-1"
                  onClick={() => seedExampleData(tenant.id)}
                  data-testid={`button-seed-${tenant.id}`}
                >
                  <Plus className="mr-2 h-4 w-4" />
                  Dados Exemplo
                </Button>
                <Button variant="outline" size="sm" className="flex-1">
                  <Users className="mr-2 h-4 w-4" />
                  Usuários
                </Button>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {tenantList.length === 0 && (
        <div className="text-center py-12">
          <Building2 className="mx-auto h-12 w-12 text-muted-foreground" />
          <h3 className="mt-4 text-lg font-semibold">Nenhum tenant encontrado</h3>
          <p className="mt-2 text-muted-foreground">
            Comece criando seu primeiro tenant no sistema.
          </p>
        </div>
      )}
    </div>
  );
}