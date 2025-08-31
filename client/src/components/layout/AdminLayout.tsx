import { ReactNode } from 'react';
import { AdminHeader } from './AdminHeader';

interface AdminLayoutProps {
  children: ReactNode;
  title?: string;
}

export function AdminLayout({ children, title = "Administração" }: AdminLayoutProps) {
  return (
    <div className="min-h-screen bg-background">
      <AdminHeader title={title} />
      <main className="flex-1 p-6 overflow-y-auto" data-testid="admin-main-content">
        {children}
      </main>
    </div>
  );
}