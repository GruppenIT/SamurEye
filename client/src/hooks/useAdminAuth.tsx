import { useQuery } from '@tanstack/react-query';

interface AdminAuthData {
  isAuthenticated: boolean;
  email?: string;
  isAdmin?: boolean;
}

export function useAdminAuth() {
  const { data, isLoading, error, refetch } = useQuery<AdminAuthData>({
    queryKey: ['/api/admin/me'],
    retry: false,
    staleTime: 30000, // 30 seconds
    gcTime: 60000, // 1 minute
  });

  return {
    isAuthenticated: data?.isAuthenticated || false,
    isLoading,
    error,
    adminUser: data,
    refetch,
  };
}