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