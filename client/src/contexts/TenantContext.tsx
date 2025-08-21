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
  
  const { data: currentUser, isLoading } = useQuery({
    queryKey: ['/api/user'],
    retry: false,
  });

  const switchTenantMutation = useMutation({
    mutationFn: async (tenantId: string) => {
      await apiRequest('POST', '/api/switch-tenant', { tenantId });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['/api/user'] });
      queryClient.invalidateQueries(); // Invalidate all queries since tenant context changed
    },
  });

  const switchTenant = async (tenantId: string) => {
    await switchTenantMutation.mutateAsync(tenantId);
  };

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
