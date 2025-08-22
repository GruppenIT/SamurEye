import { createContext, useContext, ReactNode } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import type { User, Tenant, TenantUser } from '@shared/schema';

interface TenantContextType {
  currentUser: any;
  isLoading: boolean;
  switchTenant: (tenantId: string) => Promise<void>;
}

const TenantContext = createContext<TenantContextType | null>(null);

export function TenantProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  
  const { data: currentUser, isLoading, error } = useQuery({
    queryKey: ['/api/user'],
    retry: false,
  });



  const switchTenantMutation = useMutation({
    mutationFn: async (tenantId: string) => {
      await apiRequest('POST', '/api/switch-tenant', { tenantId });
    },
    onSuccess: async () => {
      // First, refresh user data to get updated current tenant
      await queryClient.refetchQueries({ queryKey: ['/api/user'] });
      
      // Then invalidate all data queries that depend on tenant context
      queryClient.invalidateQueries({ queryKey: ['/api/dashboard/metrics'] });
      queryClient.invalidateQueries({ queryKey: ['/api/collectors'] });
      queryClient.invalidateQueries({ queryKey: ['/api/journeys'] });
      queryClient.invalidateQueries({ queryKey: ['/api/activities'] });
      queryClient.invalidateQueries({ queryKey: ['/api/threat-intelligence'] });
      queryClient.invalidateQueries({ queryKey: ['/api/credentials'] });
    },
  });

  const switchTenant = async (tenantId: string) => {
    await switchTenantMutation.mutateAsync(tenantId);
  };

  // Show loading state if still loading
  if (isLoading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-accent mx-auto"></div>
          <p className="text-muted-foreground mt-2">Carregando dados do usuário...</p>
        </div>
      </div>
    );
  }

  // Show error state if user data failed to load
  if (error || !currentUser) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center p-4">
        <div className="max-w-md text-center">
          <h1 className="text-2xl font-bold text-destructive mb-4">Erro ao carregar dados</h1>
          <p className="text-muted-foreground mb-4">
            Não foi possível carregar os dados do usuário. Por favor, faça login novamente.
          </p>
          <button 
            onClick={() => window.location.href = '/'} 
            className="bg-primary text-primary-foreground px-4 py-2 rounded-md"
          >
            Voltar ao Login
          </button>
        </div>
      </div>
    );
  }

  return (
    <TenantContext.Provider value={{ currentUser, isLoading, switchTenant }}>
      {children}
    </TenantContext.Provider>
  );
}

export function useTenant() {
  const context = useContext(TenantContext);
  if (!context) {
    throw new Error('useTenant must be used within a TenantProvider');
  }
  return context;
}
