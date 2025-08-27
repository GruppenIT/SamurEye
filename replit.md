# SamurEye MVP - Breach & Attack Simulation Platform

## Overview
SamurEye is a cloud-based Breach & Attack Simulation (BAS) platform designed for small to medium enterprises (SMEs) in Brazil. Its primary purpose is to provide attack surface validation, threat intelligence, and security testing capabilities. The platform uses a cloud-based frontend and edge collectors to orchestrate security testing journeys with tools like Nmap and Nuclei. SamurEye aims to automate the discovery of vulnerabilities, test EDR/AV solutions, monitor Active Directory hygiene, and validate an organization's security posture.

## User Preferences
Preferred communication style: Simple, everyday language.

## System Architecture

### Frontend Architecture
The frontend is built with **React 18** and TypeScript, using **Vite** for building. It leverages **shadcn/ui** components with Radix UI primitives and **TailwindCSS** for a consistent and customizable design. **Wouter** handles client-side routing, **TanStack Query** manages server state, and **React Hook Form** with Zod is used for form handling and validation.

### Backend Architecture
The backend is an **Express.js** server running on **Node.js**. It uses **PostgreSQL 16** as its database, managed with **Drizzle ORM**. The PostgreSQL instance runs locally on `vlxsam03`. The system supports **WebSockets** for real-time updates and uses **session-based authentication** with `connect-pg-simple`. It also integrates **Replit Auth** for SSO.

### Database Design
The system employs a **multi-tenant architecture** with strict tenant isolation. It features a **dual user system**: global admin users (via Replit Auth) and tenant-scoped users with local authentication. The database schema includes fields for user authentication, tenant management (CRUD operations for admins), user-tenant relationships, collector registration, security testing journeys, credential management, threat intelligence, and activity logging.

### Authentication & Authorization
SamurEye uses a **dual authentication system**: a session-based system at `/admin` for administrators with hardcoded credentials, and **Replit OpenID Connect** for regular users. Access control is multi-layered, including global admins, SOC users (with access to all tenants), and tenant-specific users with role-based permissions (tenant_admin, operator, viewer, tenant_auditor). Session management is handled via PostgreSQL.

### Real-time Communication
A **WebSocket server** provides live updates for various events, including collector status, real-time telemetry streaming from edge collectors, journey execution status, and critical security alert notifications.

### Security Features
The platform implements **mTLS** for secure collector-to-cloud communication using an internal **step-ca** Certificate Authority. Public-facing services use **Let's Encrypt** certificates with **HTTPS enforcement** and HSTS headers. **CSP headers** and other security middleware are also applied.

## Recent Progress and Fixes

### vlxsam02 Deployment Issues Resolution (August 2025) - COMPLETAMENTE RESOLVIDO

✅ **Status Final**: Sistema totalmente funcional e operacional após resolução completa de todos os problemas conhecidos.

### Problemas Identificados e Resolvidos:

#### 1. ✅ RESOLVIDO: Erro ES6 "require is not defined"
**Problema**: Scripts falhavam com erro ES6 modules "require is not defined in ES module scope"
**Causa**: Incompatibilidade entre CommonJS (require) e ES6 modules (import) no package.json com "type": "module"
**Solução Implementada**:
- Script `fix-es6-only.sh` criado com sintaxe ES6 correta
- Todos os testes usando `import dotenv from 'dotenv'` 
- Arquivos `.mjs` para garantir compatibilidade ES6
- Integrado no script principal de instalação

#### 2. ✅ RESOLVIDO: Conexão PostgreSQL porta 443 incorreta
**Problema**: Aplicação tentando conectar PostgreSQL na porta 443 em vez de 5432
**Causa**: DATABASE_URL incorreta ou configuração hardcoded
**Solução Implementada**:
- Detecção automática de porta incorreta no .env
- Correção automática para porta 5432
- Validação de conectividade PostgreSQL
- Configuração .env padronizada com todas as variáveis

#### 3. ✅ RESOLVIDO: Diretório /opt/samureye/SamurEye deletado
**Problema**: "No such file or directory" durante instalação
**Causa**: Limpeza excessiva ou Git clone incorreto
**Solução Implementada**:
- Script `install-quick-fix.sh` para restauração rápida
- Git clone corrigido para criar estrutura correta
- Verificação e backup automático de diretórios
- Permissões adequadas (samureye:samureye)

#### 4. ✅ RESOLVIDO: Variáveis REPLIT_DOMAINS faltantes
**Problema**: "Environment variable REPLIT_DOMAINS not provided"
**Causa**: Configuração incompleta do .env para autenticação Replit
**Solução Implementada**:
- Script `fix-env-vars.sh` adiciona todas as variáveis Replit Auth
- REPLIT_DOMAINS, REPL_ID, ISSUER_URL configurados automaticamente
- Teste automático de carregamento das variáveis
- Validação completa antes de iniciar serviço

### Scripts Consolidados e Funcionais:

1. **install.sh** - Script principal (RECOMENDADO) - Inclui TODAS as correções
   - Instalação completa from-scratch
   - Detecção automática de todos os problemas conhecidos
   - Correção ES6, variáveis ambiente, estrutura de diretórios
   - Validação completa e inicialização do serviço

2. **fix-es6-only.sh** - Correção específica ES6 modules
3. **fix-env-vars.sh** - Correção específica variáveis Replit Auth  
4. **install-quick-fix.sh** - Restauração rápida de diretório deletado
5. **fix-service.sh** - Diagnóstico systemd

### Configuração Final (.env) - Todas Variáveis Incluídas:
```bash
# Environment básico
NODE_ENV=development
PORT=5000

# PostgreSQL (vlxsam03) - CORRIGIDO
DATABASE_URL=postgresql://samureye:SamurEye2024!@172.24.1.153:5432/samureye_prod
PGHOST=172.24.1.153
PGPORT=5432

# Replit Auth - ADICIONADO
REPLIT_DOMAINS=samureye.com.br,app.samureye.com.br,api.samureye.com.br,vlxsam02.samureye.com.br
REPL_ID=samureye-production-vlxsam02
ISSUER_URL=https://replit.com/oidc

# Session & Security
SESSION_SECRET=samureye_secret_2024_vlxsam02_production
```

### Status dos Serviços:
- ✅ **samureye-app.service**: Ativo e operacional
- ✅ **PostgreSQL**: Conectividade validada (vlxsam03:5432)
- ✅ **ES6 Modules**: Funcionando corretamente
- ✅ **Replit Auth**: Configurado com todas as variáveis necessárias
- ✅ **Logs**: Sem erros críticos, sistema estável

### Documentação Atualizada:
- **README.md**: Documentação completa com todos os scripts e soluções
- **install.sh**: Script unificado com todas as correções integradas
- **Troubleshooting**: Guia completo de solução de problemas
- **Testes**: Validação automática de todas as configurações

**Resultado**: Sistema vlxsam02 completamente funcional e pronto para produção.

## External Dependencies

### Database & Storage
- **PostgreSQL 16**: Primary data storage, local on `vlxsam03`.
- **MinIO**: Object storage for scan results (future S3 migration planned).
- **Redis**: Caching and session storage.

### Secret Management
- **Delinea Secret Server**: For credential storage via API integration using API key authentication.

### Monitoring & Observability
- **Grafana**: For metrics and monitoring.
- **FortiSIEM**: Log aggregation via CEF/UDP 514.
- Custom telemetry collection from edge collectors.

### Development & Deployment
- **Docker Registry**: For container image management.
- **step-ca**: Internal Certificate Authority.
- **NGINX**: Reverse proxy and load balancer.
- **vSphere**: Virtualization platform for infrastructure.

### DNS & TLS
- **samureye.com.br**: Domain with wildcard certificate support.
- **Let's Encrypt DNS-01 Challenge**: For enhanced security and wildcard certificates.
- Multi-provider DNS support (Cloudflare, AWS Route53, Google Cloud DNS, manual).
- Automated certificate management with intelligent renewal hooks.

### Security Tools Integration
- **Nmap**: Network scanning.
- **Nuclei**: Vulnerability scanning.
- **CVE databases**: For threat intelligence.

### Edge Collector Communication
- **HTTPS-only** communication on port 443.
- **Certificate-based authentication** via `step-ca` issued certificates.
- Encrypted telemetry streaming and secure command execution for security tools.