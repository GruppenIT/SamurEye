import { Eye, Shield, Network, Users } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useI18n } from '@/hooks/useI18n';

export default function Landing() {
  const { t, language, switchLanguage } = useI18n();

  const handleLogin = () => {
    window.location.href = '/api/login';
  };

  const features = [
    {
      icon: Shield,
      title: 'Attack Surface Validation',
      description: 'Descubra e valide superfícies de ataque internas e externas'
    },
    {
      icon: Users,
      title: 'AD/LDAP Hygiene',
      description: 'Monitore higiene de Active Directory e políticas de segurança'
    },
    {
      icon: Network,
      title: 'EDR/AV Testing',
      description: 'Teste eficácia de soluções EDR e antivírus'
    }
  ];

  return (
    <div className="min-h-screen bg-samur-primary text-samur-text-primary" data-testid="landing-page">
      {/* Header */}
      <header className="border-b border-border">
        <div className="max-w-7xl mx-auto px-6 py-4 flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <div className="w-8 h-8 bg-accent rounded-lg flex items-center justify-center">
              <Eye className="text-white" size={20} />
            </div>
            <h1 className="text-2xl font-bold text-white">SamurEye</h1>
            <Badge variant="secondary" className="bg-info text-white">
              MVP
            </Badge>
          </div>
          
          {/* Language Toggle */}
          <div className="flex items-center bg-muted rounded-lg p-1">
            <Button
              size="sm"
              variant={language === 'pt-BR' ? 'default' : 'ghost'}
              className="px-3 py-1 text-sm h-auto"
              onClick={() => switchLanguage('pt-BR')}
              data-testid="lang-pt"
            >
              PT
            </Button>
            <Button
              size="sm"
              variant={language === 'en' ? 'default' : 'ghost'}
              className="px-3 py-1 text-sm h-auto"
              onClick={() => switchLanguage('en')}
              data-testid="lang-en"
            >
              EN
            </Button>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="relative py-20 overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-accent/10 to-samur-secondary/50"></div>
        <div className="relative max-w-7xl mx-auto px-6 text-center">
          <div className="max-w-4xl mx-auto">
            <h1 className="text-5xl md:text-6xl font-bold text-white mb-6" data-testid="hero-title">
              {t('welcome.title')}
            </h1>
            <p className="text-xl md:text-2xl text-samur-text-muted mb-8" data-testid="hero-subtitle">
              {t('welcome.subtitle')}
            </p>
            <p className="text-lg text-samur-text-muted mb-10 max-w-2xl mx-auto" data-testid="hero-description">
              {t('welcome.description')}
            </p>
            
            <Button 
              size="lg" 
              className="bg-accent hover:bg-accent/90 text-white px-8 py-4 text-lg"
              onClick={handleLogin}
              data-testid="login-button"
            >
              {t('welcome.loginButton')}
            </Button>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-20 bg-samur-secondary">
        <div className="max-w-7xl mx-auto px-6">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
              Jornadas de Teste Especializadas
            </h2>
            <p className="text-lg text-samur-text-muted max-w-2xl mx-auto">
              Três jornadas específicas para validação completa da sua postura de segurança
            </p>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {features.map((feature, index) => {
              const IconComponent = feature.icon;
              
              return (
                <Card key={index} className="bg-card border-border hover:border-accent/50 transition-colors" data-testid={`feature-card-${index}`}>
                  <CardContent className="p-8 text-center">
                    <div className="w-16 h-16 bg-accent/20 rounded-full flex items-center justify-center mx-auto mb-6">
                      <IconComponent className="text-accent" size={32} />
                    </div>
                    <h3 className="text-xl font-semibold text-white mb-4">
                      {feature.title}
                    </h3>
                    <p className="text-samur-text-muted">
                      {feature.description}
                    </p>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="py-16 bg-samur-primary">
        <div className="max-w-7xl mx-auto px-6">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
            <div className="text-center">
              <div className="text-3xl md:text-4xl font-bold text-accent mb-2">99.9%</div>
              <div className="text-samur-text-muted">Uptime</div>
            </div>
            <div className="text-center">
              <div className="text-3xl md:text-4xl font-bold text-accent mb-2">24/7</div>
              <div className="text-samur-text-muted">Monitoramento</div>
            </div>
            <div className="text-center">
              <div className="text-3xl md:text-4xl font-bold text-accent mb-2">Multi</div>
              <div className="text-samur-text-muted">Tenant</div>
            </div>
            <div className="text-center">
              <div className="text-3xl md:text-4xl font-bold text-accent mb-2">SOC</div>
              <div className="text-samur-text-muted">Integration</div>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border py-8">
        <div className="max-w-7xl mx-auto px-6 text-center">
          <div className="flex items-center justify-center space-x-3 mb-4">
            <div className="w-6 h-6 bg-accent rounded-lg flex items-center justify-center">
              <Eye className="text-white" size={14} />
            </div>
            <span className="text-white font-semibold">SamurEye</span>
          </div>
          <p className="text-samur-text-muted text-sm">
            © 2025 SamurEye. Plataforma de Simulação de Ataques.
          </p>
        </div>
      </footer>
    </div>
  );
}
