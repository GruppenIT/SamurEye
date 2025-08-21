import { Switch, Route } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useAuth } from "@/hooks/useAuth";
import { TenantProvider } from "@/contexts/TenantContext";
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

function Router() {
  const { isAuthenticated, isLoading } = useAuth();

  return (
    <Switch>
      {/* Admin routes - no authentication needed */}
      <Route path="/admin" component={AdminLogin} />
      <Route path="/admin/dashboard" component={AdminDashboard} />
      <Route path="/admin/users/create" component={AdminUserCreate} />
      <Route path="/admin/tenants/:tenantId/users" component={TenantUsers} />
      
      {/* Regular user routes */}
      {isLoading || !isAuthenticated ? (
        <Route path="/" component={Login} />
      ) : (
        <TenantProvider>
          <Route path="/" component={Dashboard} />
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
        <Router />
      </TooltipProvider>
    </QueryClientProvider>
  );
}

export default App;
