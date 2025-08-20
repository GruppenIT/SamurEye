import { useState } from 'react';
import { AlertTriangle, Shield, Info, TrendingUp, Target, Search, Filter } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MainLayout } from '@/components/layout/MainLayout';
import { JourneyForm } from '@/components/journeys/JourneyForm';
import { CollectorEnrollment } from '@/components/collectors/CollectorEnrollment';
import { useQuery } from '@tanstack/react-query';
import { useLocation } from 'wouter';
import { useI18n } from '@/hooks/useI18n';

export default function ThreatIntelligence() {
  const { t } = useI18n();
  const [, setLocation] = useLocation();
  const [showJourneyForm, setShowJourneyForm] = useState(false);
  const [showCollectorForm, setShowCollectorForm] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');

  const { data: threatIntel, isLoading } = useQuery({
    queryKey: ['/api/threat-intelligence'],
  });

  const handleTabChange = (tab: string) => {
    if (tab === 'intelligence') return;
    setLocation(tab === 'dashboard' ? '/' : `/${tab}`);
  };

  const handleNewJourney = () => {
    setShowJourneyForm(true);
  };

  const handleAddCollector = () => {
    setShowCollectorForm(true);
  };

  const getSeverityIcon = (severity: string) => {
    switch (severity) {
      case 'critical':
        return AlertTriangle;
      case 'high':
        return Shield;
      case 'medium':
        return Target;
      case 'low':
        return Info;
      default:
        return Info;
    }
  };

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'critical':
        return 'bg-red-500/20 text-red-500 border-red-500/30';
      case 'high':
        return 'bg-orange-500/20 text-orange-500 border-orange-500/30';
      case 'medium':
        return 'bg-yellow-500/20 text-yellow-500 border-yellow-500/30';
      case 'low':
        return 'bg-green-500/20 text-green-500 border-green-500/30';
      case 'info':
        return 'bg-blue-500/20 text-blue-500 border-blue-500/30';
      default:
        return 'bg-gray-500/20 text-gray-500 border-gray-500/30';
    }
  };

  // Mock threat intelligence data for demo
  const mockThreatIntel = [
    {
      id: '1',
      type: 'cve',
      source: 'NVD',
      severity: 'critical',
      title: 'CVE-2024-1234: Remote Code Execution in SSH Service',
      description: 'A critical vulnerability allowing remote code execution through malformed SSH packets.',
      data: { cvss: 9.8, vector: 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H' },
      score: 98,
      createdAt: new Date().toISOString()
    },
    {
      id: '2',
      type: 'ioc',
      source: 'SamurEye Intel',
      severity: 'high',
      title: 'Malicious IP Address: 192.168.1.100',
      description: 'IP address observed in multiple attack campaigns targeting RDP services.',
      data: { ip: '192.168.1.100', ports: [3389, 22], campaigns: ['Operation Shadow'] },
      score: 85,
      createdAt: new Date(Date.now() - 60 * 60 * 1000).toISOString()
    },
    {
      id: '3',
      type: 'signature',
      source: 'Nuclei',
      severity: 'medium',
      title: 'Exposed Database Management Interface',
      description: 'Database management interface accessible without authentication.',
      data: { template: 'phpmyadmin-panel', paths: ['/phpmyadmin/', '/dbadmin/'] },
      score: 65,
      createdAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString()
    },
    {
      id: '4',
      type: 'vulnerability',
      source: 'Nmap',
      severity: 'low',
      title: 'Outdated SSH Banner Information',
      description: 'SSH service banner reveals potentially outdated version information.',
      data: { service: 'ssh', version: 'OpenSSH 7.4', recommendation: 'Update to latest version' },
      score: 30,
      createdAt: new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString()
    }
  ];

  const displayThreatIntel = threatIntel || mockThreatIntel;

  const filteredThreatIntel = displayThreatIntel.filter((item: any) =>
    item.title.toLowerCase().includes(searchTerm.toLowerCase()) ||
    item.description.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const threatIntelByType = filteredThreatIntel.reduce((acc: any, item: any) => {
    const type = item.type;
    if (!acc[type]) acc[type] = [];
    acc[type].push(item);
    return acc;
  }, {});

  const severityCounts = displayThreatIntel.reduce((acc: any, item: any) => {
    acc[item.severity] = (acc[item.severity] || 0) + 1;
    return acc;
  }, {});

  const formatTimeAgo = (timestamp: string) => {
    const now = new Date();
    const time = new Date(timestamp);
    const diffMs = now.getTime() - time.getTime();
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    
    if (diffHours < 1) return 'há poucos minutos';
    if (diffHours < 24) return `há ${diffHours}h`;
    const diffDays = Math.floor(diffHours / 24);
    return `há ${diffDays} dias`;
  };

  return (
    <>
      <MainLayout
        activeTab="intelligence"
        onTabChange={handleTabChange}
        onNewJourney={handleNewJourney}
        onAddCollector={handleAddCollector}
      >
        <div className="space-y-6" data-testid="threat-intelligence-page">
          {/* Header */}
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-3xl font-bold text-white mb-2">Threat Intelligence</h2>
              <p className="text-muted-foreground">
                Console de inteligência de ameaças com sistema de pontuação
              </p>
            </div>
            <div className="flex items-center space-x-3">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground" size={16} />
                <Input
                  placeholder="Buscar ameaças..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10 w-64"
                  data-testid="threat-search"
                />
              </div>
              <Button variant="outline" data-testid="filter-threats">
                <Filter className="mr-2 h-4 w-4" />
                Filtros
              </Button>
            </div>
          </div>

          {/* Severity Overview */}
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            {[
              { severity: 'critical', label: 'Críticas', icon: AlertTriangle },
              { severity: 'high', label: 'Altas', icon: Shield },
              { severity: 'medium', label: 'Médias', icon: Target },
              { severity: 'low', label: 'Baixas', icon: Info },
              { severity: 'info', label: 'Informativas', icon: TrendingUp }
            ].map(({ severity, label, icon: IconComponent }) => (
              <Card key={severity} className="bg-secondary">
                <CardContent className="p-4 text-center">
                  <div className={`w-12 h-12 mx-auto mb-3 rounded-lg flex items-center justify-center ${getSeverityColor(severity)}`}>
                    <IconComponent size={24} />
                  </div>
                  <div className="text-2xl font-bold text-white mb-1">
                    {severityCounts[severity] || 0}
                  </div>
                  <div className="text-sm text-muted-foreground">{label}</div>
                </CardContent>
              </Card>
            ))}
          </div>

          {/* Threat Intelligence Tabs */}
          <Tabs defaultValue="all" className="w-full">
            <TabsList className="grid w-full grid-cols-5">
              <TabsTrigger value="all">Todas</TabsTrigger>
              <TabsTrigger value="cve">CVEs</TabsTrigger>
              <TabsTrigger value="ioc">IoCs</TabsTrigger>
              <TabsTrigger value="signature">Assinaturas</TabsTrigger>
              <TabsTrigger value="vulnerability">Vulnerabilidades</TabsTrigger>
            </TabsList>

            <TabsContent value="all" className="space-y-4">
              {isLoading ? (
                <div className="space-y-4">
                  {[...Array(4)].map((_, i) => (
                    <Card key={i} className="bg-secondary animate-pulse">
                      <CardContent className="p-6">
                        <div className="h-4 bg-muted rounded mb-4"></div>
                        <div className="h-3 bg-muted rounded mb-2"></div>
                        <div className="h-3 bg-muted rounded w-3/4"></div>
                      </CardContent>
                    </Card>
                  ))}
                </div>
              ) : filteredThreatIntel.length === 0 ? (
                <Card className="bg-secondary">
                  <CardContent className="p-12 text-center">
                    <Shield className="mx-auto h-12 w-12 text-muted-foreground mb-4" />
                    <h3 className="text-lg font-semibold text-white mb-2">
                      Nenhuma ameaça encontrada
                    </h3>
                    <p className="text-muted-foreground">
                      {searchTerm ? 'Tente ajustar os termos de busca' : 'Execute jornadas para descobrir ameaças'}
                    </p>
                  </CardContent>
                </Card>
              ) : (
                <div className="space-y-4">
                  {filteredThreatIntel.map((threat: any) => {
                    const IconComponent = getSeverityIcon(threat.severity);
                    
                    return (
                      <Card key={threat.id} className="bg-secondary hover:bg-secondary/80 transition-colors" data-testid={`threat-${threat.id}`}>
                        <CardContent className="p-6">
                          <div className="flex items-start justify-between">
                            <div className="flex items-start space-x-4 flex-1">
                              <div className={`w-12 h-12 rounded-lg flex items-center justify-center ${getSeverityColor(threat.severity)}`}>
                                <IconComponent size={24} />
                              </div>
                              <div className="flex-1">
                                <div className="flex items-center space-x-3 mb-2">
                                  <h3 className="text-lg font-semibold text-white">{threat.title}</h3>
                                  <Badge className={`text-xs border ${getSeverityColor(threat.severity)}`}>
                                    {threat.severity.toUpperCase()}
                                  </Badge>
                                  <Badge variant="outline" className="text-xs">
                                    {threat.type.toUpperCase()}
                                  </Badge>
                                </div>
                                <p className="text-muted-foreground mb-3">{threat.description}</p>
                                
                                <div className="flex items-center space-x-4 text-sm">
                                  <span className="text-muted-foreground">
                                    Fonte: <span className="text-white">{threat.source}</span>
                                  </span>
                                  <span className="text-muted-foreground">
                                    Score: <span className="text-accent font-medium">{threat.score}</span>
                                  </span>
                                  <span className="text-muted-foreground">
                                    {formatTimeAgo(threat.createdAt)}
                                  </span>
                                </div>
                                
                                {/* Additional Data */}
                                {threat.data && (
                                  <div className="mt-3 p-3 bg-card rounded-lg">
                                    <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-xs">
                                      {Object.entries(threat.data).slice(0, 4).map(([key, value]: [string, any]) => (
                                        <div key={key} className="flex justify-between">
                                          <span className="text-muted-foreground">{key}:</span>
                                          <span className="text-white font-mono">
                                            {Array.isArray(value) ? value.join(', ') : String(value)}
                                          </span>
                                        </div>
                                      ))}
                                    </div>
                                  </div>
                                )}
                              </div>
                            </div>
                          </div>
                        </CardContent>
                      </Card>
                    );
                  })}
                </div>
              )}
            </TabsContent>

            {/* Type-specific tabs */}
            {Object.entries(threatIntelByType).map(([type, threats]) => (
              <TabsContent key={type} value={type} className="space-y-4">
                <div className="space-y-4">
                  {(threats as any[]).map((threat: any) => {
                    const IconComponent = getSeverityIcon(threat.severity);
                    
                    return (
                      <Card key={threat.id} className="bg-secondary hover:bg-secondary/80 transition-colors">
                        <CardContent className="p-6">
                          <div className="flex items-start space-x-4">
                            <div className={`w-12 h-12 rounded-lg flex items-center justify-center ${getSeverityColor(threat.severity)}`}>
                              <IconComponent size={24} />
                            </div>
                            <div className="flex-1">
                              <div className="flex items-center space-x-3 mb-2">
                                <h3 className="text-lg font-semibold text-white">{threat.title}</h3>
                                <Badge className={`text-xs border ${getSeverityColor(threat.severity)}`}>
                                  {threat.severity.toUpperCase()}
                                </Badge>
                              </div>
                              <p className="text-muted-foreground mb-3">{threat.description}</p>
                              
                              <div className="flex items-center space-x-4 text-sm">
                                <span className="text-muted-foreground">
                                  Fonte: <span className="text-white">{threat.source}</span>
                                </span>
                                <span className="text-muted-foreground">
                                  Score: <span className="text-accent font-medium">{threat.score}</span>
                                </span>
                                <span className="text-muted-foreground">
                                  {formatTimeAgo(threat.createdAt)}
                                </span>
                              </div>
                            </div>
                          </div>
                        </CardContent>
                      </Card>
                    );
                  })}
                </div>
              </TabsContent>
            ))}
          </Tabs>
        </div>
      </MainLayout>

      {/* Modals */}
      {showJourneyForm && (
        <JourneyForm
          isOpen={showJourneyForm}
          onClose={() => setShowJourneyForm(false)}
        />
      )}

      {showCollectorForm && (
        <CollectorEnrollment 
          isOpen={showCollectorForm}
          onClose={() => setShowCollectorForm(false)}
        />
      )}
    </>
  );
}
