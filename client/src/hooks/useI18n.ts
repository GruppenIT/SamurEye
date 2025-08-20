import { useState, useCallback } from 'react';

type Language = 'pt-BR' | 'en';

interface Translations {
  [key: string]: {
    'pt-BR': string;
    'en': string;
  };
}

const translations: Translations = {
  // Header
  'nav.dashboard': { 'pt-BR': 'Dashboard', 'en': 'Dashboard' },
  'nav.collectors': { 'pt-BR': 'Coletores', 'en': 'Collectors' },
  'nav.journeys': { 'pt-BR': 'Jornadas', 'en': 'Journeys' },
  'nav.intelligence': { 'pt-BR': 'Threat Intel', 'en': 'Threat Intel' },
  'nav.credentials': { 'pt-BR': 'Credenciais', 'en': 'Credentials' },

  // Dashboard
  'dashboard.title': { 'pt-BR': 'Dashboard de Segurança', 'en': 'Security Dashboard' },
  'dashboard.subtitle': { 'pt-BR': 'Visão geral das operações de simulação de ataques', 'en': 'Overview of attack simulation operations' },
  'dashboard.export': { 'pt-BR': 'Exportar', 'en': 'Export' },
  'dashboard.activeTenant': { 'pt-BR': 'Tenant Ativo', 'en': 'Active Tenant' },
  'dashboard.collectorsOnline': { 'pt-BR': 'Coletores Online', 'en': 'Collectors Online' },
  'dashboard.activeJobs': { 'pt-BR': 'Jobs Ativos', 'en': 'Active Jobs' },
  'dashboard.criticalAlerts': { 'pt-BR': 'Alertas Críticos', 'en': 'Critical Alerts' },
  'dashboard.newJourney': { 'pt-BR': 'Nova Jornada', 'en': 'New Journey' },
  'dashboard.addCollector': { 'pt-BR': 'Adicionar Coletor', 'en': 'Add Collector' },

  // Metrics
  'metrics.criticalVulns': { 'pt-BR': 'Vulnerabilidades Críticas', 'en': 'Critical Vulnerabilities' },
  'metrics.highVulns': { 'pt-BR': 'Vulnerabilidades Altas', 'en': 'High Vulnerabilities' },
  'metrics.assetsDiscovered': { 'pt-BR': 'Assets Descobertos', 'en': 'Assets Discovered' },
  'metrics.detectionRate': { 'pt-BR': 'Taxa de Detecção', 'en': 'Detection Rate' },

  // Journeys
  'journey.attackSurface': { 'pt-BR': 'Attack Surface', 'en': 'Attack Surface' },
  'journey.adHygiene': { 'pt-BR': 'Higiene AD/LDAP', 'en': 'AD/LDAP Hygiene' },
  'journey.edrTesting': { 'pt-BR': 'EDR/AV Testing', 'en': 'EDR/AV Testing' },
  'journey.lastExecution': { 'pt-BR': 'Última execução', 'en': 'Last execution' },

  // Status
  'status.online': { 'pt-BR': 'ONLINE', 'en': 'ONLINE' },
  'status.offline': { 'pt-BR': 'OFFLINE', 'en': 'OFFLINE' },
  'status.critical': { 'pt-BR': 'CRÍTICO', 'en': 'CRITICAL' },
  'status.high': { 'pt-BR': 'ALTO', 'en': 'HIGH' },
  'status.active': { 'pt-BR': 'ATIVO', 'en': 'ACTIVE' },
  'status.completed': { 'pt-BR': 'CONCLUÍDA', 'en': 'COMPLETED' },
  'status.running': { 'pt-BR': 'EM EXECUÇÃO', 'en': 'RUNNING' },

  // Time
  'time.ago': { 'pt-BR': 'atrás', 'en': 'ago' },
  'time.minutes': { 'pt-BR': 'min', 'en': 'min' },
  'time.hours': { 'pt-BR': 'h', 'en': 'h' },

  // Common
  'common.update': { 'pt-BR': 'Atualizar', 'en': 'Update' },
  'common.refresh': { 'pt-BR': 'Atualizar', 'en': 'Refresh' },
  'common.viewAll': { 'pt-BR': 'Ver todas', 'en': 'View all' },
  'common.loading': { 'pt-BR': 'Carregando...', 'en': 'Loading...' },
  'common.error': { 'pt-BR': 'Erro', 'en': 'Error' },
  'common.success': { 'pt-BR': 'Sucesso', 'en': 'Success' },

  // Welcome
  'welcome.title': { 'pt-BR': 'Bem-vindo ao SamurEye', 'en': 'Welcome to SamurEye' },
  'welcome.subtitle': { 'pt-BR': 'Plataforma de Simulação de Ataques e Validação de Superfície de Exposição', 'en': 'Attack Simulation and Exposure Surface Validation Platform' },
  'welcome.loginButton': { 'pt-BR': 'Fazer Login', 'en': 'Sign In' },
  'welcome.description': { 'pt-BR': 'Orquestre testes de segurança, monitore coletores e valide sua postura de segurança com nossa plataforma BAS multi-tenant.', 'en': 'Orchestrate security tests, monitor collectors, and validate your security posture with our multi-tenant BAS platform.' },
};

export function useI18n() {
  const [language, setLanguage] = useState<Language>(() => {
    const saved = localStorage.getItem('samureye-language');
    return (saved as Language) || 'pt-BR';
  });

  const t = useCallback((key: string, fallback?: string): string => {
    const translation = translations[key];
    if (translation && translation[language]) {
      return translation[language];
    }
    return fallback || key;
  }, [language]);

  const switchLanguage = useCallback((newLanguage: Language) => {
    setLanguage(newLanguage);
    localStorage.setItem('samureye-language', newLanguage);
  }, []);

  return {
    language,
    t,
    switchLanguage
  };
}
