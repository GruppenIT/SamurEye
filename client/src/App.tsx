import { Switch, Route } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useAuth } from "@/hooks/useAuth";
import { TenantProvider } from "@/contexts/TenantContext";
import NotFound from "@/pages/not-found";
import Landing from "@/pages/Landing";
import Dashboard from "@/pages/Dashboard";
import Collectors from "@/pages/Collectors";
import Journeys from "@/pages/Journeys";
import Credentials from "@/pages/Credentials";
import ThreatIntelligence from "@/pages/ThreatIntelligence";

function Router() {
  const { isAuthenticated, isLoading } = useAuth();

  return (
    <Switch>
      {isLoading || !isAuthenticated ? (
        <Route path="/" component={Landing} />
      ) : (
        <TenantProvider>
          <Route path="/" component={Dashboard} />
          <Route path="/collectors" component={Collectors} />
          <Route path="/journeys" component={Journeys} />
          <Route path="/credentials" component={Credentials} />
          <Route path="/intelligence" component={ThreatIntelligence} />
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
