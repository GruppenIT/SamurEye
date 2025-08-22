import { Switch, Route } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useAuth } from "@/hooks/useAuth";
import { TenantProvider } from "@/contexts/TenantContext";
import { Component, ReactNode } from 'react';
import NotFound from "@/pages/not-found";
import Login from "@/pages/Login";
import Dashboard from "@/pages/Dashboard";
import Collectors from "@/pages/Collectors";
import Journeys from "@/pages/Journeys";
import Credentials from "@/pages/Credentials";
import ThreatIntelligence from "@/pages/ThreatIntelligence";
import GlobalAdmin from "@/pages/GlobalAdmin";
import TenantUsers from "@/pages/TenantUsers";
import AdminLogin from "@/pages/AdminLogin";
import AdminDashboard from "@/pages/AdminDashboard";
import AdminUserCreate from "@/pages/AdminUserCreate";
import AdminSettings from "@/pages/AdminSettings";
import AdminUserEdit from "@/pages/AdminUserEdit";

function Router() {
  const { isAuthenticated, isLoading, error } = useAuth();



  return (
    <Switch>
      {/* Admin routes - no authentication needed */}
      <Route path="/admin" component={AdminLogin} />
      <Route path="/admin/dashboard" component={AdminDashboard} />
      <Route path="/admin/settings" component={AdminSettings} />
      <Route path="/admin/users/create" component={AdminUserCreate} />
      <Route path="/admin/users/:id/edit" component={AdminUserEdit} />
      <Route path="/admin/tenants/:tenantId/users" component={TenantUsers} />
      
      {/* Regular user routes */}
      {isLoading ? (
        <div className="min-h-screen bg-background flex items-center justify-center">
          <div className="text-center">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-accent mx-auto"></div>
            <p className="text-muted-foreground mt-2">Verificando autenticação...</p>
          </div>
        </div>
      ) : !isAuthenticated ? (
        <Route path="/" component={Login} />
      ) : (
        <TenantProvider>
          <Route path="/" component={Dashboard} />
          <Route path="/dashboard" component={Dashboard} />
          <Route path="/collectors" component={Collectors} />
          <Route path="/journeys" component={Journeys} />
          <Route path="/credentials" component={Credentials} />
          <Route path="/intelligence" component={ThreatIntelligence} />
          <Route path="/users" component={TenantUsers} />
        </TenantProvider>
      )}
      <Route component={NotFound} />
    </Switch>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <Toaster />
        <ErrorBoundary>
          <Router />
        </ErrorBoundary>
      </TooltipProvider>
    </QueryClientProvider>
  );
}

// Error boundary to catch React errors and prevent blank screen

interface ErrorBoundaryState {
  hasError: boolean;
  error?: Error;
}

class ErrorBoundary extends Component<{ children: ReactNode }, ErrorBoundaryState> {
  constructor(props: { children: ReactNode }) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: any) {
    console.error('React Error Boundary caught an error:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-background flex items-center justify-center p-4">
          <div className="max-w-md text-center">
            <h1 className="text-2xl font-bold text-destructive mb-4">Something went wrong</h1>
            <p className="text-muted-foreground mb-4">
              A aplicação encontrou um erro inesperado. Por favor, recarregue a página.
            </p>
            <button 
              onClick={() => window.location.reload()} 
              className="bg-primary text-primary-foreground px-4 py-2 rounded-md"
            >
              Recarregar Página
            </button>
            {this.state.error && (
              <details className="mt-4 text-left">
                <summary className="cursor-pointer text-sm text-muted-foreground">
                  Detalhes do erro (para desenvolvedores)
                </summary>
                <pre className="text-xs bg-muted p-2 rounded mt-2 overflow-auto">
                  {this.state.error.stack}
                </pre>
              </details>
            )}
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

export default App;
