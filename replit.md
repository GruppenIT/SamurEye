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

### vlxsam02 Deployment Issues Resolution (August 2025)
Successfully identified and resolved critical port 443 connection issues affecting vlxsam02 application server:

**Problem**: Application attempting HTTPS connections to PostgreSQL server on port 443 instead of port 5432.

**Root Cause**: 
- Missing dotenv configuration in server startup
- Potential hardcoded URL configurations in codebase
- Environment variable loading issues in production environment

**Solutions Implemented**:
1. **Enhanced server/index.ts** - Added `import "dotenv/config"` to ensure environment variables load correctly
2. **Consolidated install.sh** - Created unified installation script with comprehensive automation:
   - Automatic detection of port 443 issues and other problems
   - Complete diagnostic and correction capabilities built-in
   - Automatic cleanup of previous installations
   - Hardcoded configuration detection and correction
   - Environment file creation with correct PostgreSQL settings
   - Systemd service configuration and startup
   - Full validation and testing of the installation
3. **Streamlined approach** - Removed separate diagnostic scripts in favor of single automated installer
4. **Documentation** - Updated README.md to reflect unified installation approach

**Current Status**: Multiple installation scripts available to handle different scenarios:

1. **install-final.sh** - Script principal recomendado que resolve problemas de dotenv e execução no contexto correto
2. **fix-env-test.sh** - Correção específica para erro "Cannot find module 'dotenv'"  
3. **install-simple.sh** - Instalação simplificada focada em problemas .env
4. **install.sh** - Script original completo (pode ter problemas de contexto)

**Principais Problemas Resolvidos**:
- Erro "Cannot find module 'dotenv'" - Scripts executavam fora do contexto do projeto
- Erro "require is not defined" - Problemas de execução em diretórios temporários
- Links simbólicos .env não funcionando corretamente
- Carregamento de variáveis de ambiente falhando

**Solução Final**: Scripts agora:
1. Executam testes dentro do diretório `/opt/samureye/SamurEye` onde está o `node_modules`
2. Usam sintaxe ES6 modules (import/export) em vez de CommonJS (require)
3. Utilizam arquivos `.mjs` para compatibilidade com `"type": "module"` no package.json
4. Garantem carregamento correto do dotenv com sintaxe ES6

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