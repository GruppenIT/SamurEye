import { ReactNode } from 'react';
import { AppHeader } from './AppHeader';
import { Sidebar } from './Sidebar';

interface MainLayoutProps {
  children: ReactNode;
  activeTab: string;
  onTabChange: (tab: string) => void;
  onNewJourney: () => void;
  onAddCollector: () => void;
}

export function MainLayout({ 
  children, 
  activeTab, 
  onTabChange, 
  onNewJourney, 
  onAddCollector 
}: MainLayoutProps) {
  return (
    <div className="min-h-screen bg-background">
      <AppHeader activeTab={activeTab} onTabChange={onTabChange} />
      <div className="flex">
        <Sidebar onNewJourney={onNewJourney} onAddCollector={onAddCollector} />
        <main className="flex-1 p-6 overflow-y-auto" data-testid="main-content">
          {children}
        </main>
      </div>
    </div>
  );
}
