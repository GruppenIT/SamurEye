# SamurEye MVP - Breach & Attack Simulation Platform

## Overview
SamurEye is a cloud-based Breach & Attack Simulation (BAS) platform designed for SMEs in Brazil. Its primary purpose is to validate attack surfaces, provide threat intelligence, and offer robust security testing capabilities. The platform automates vulnerability discovery, assesses EDR/AV solution effectiveness, monitors Active Directory hygiene, and validates overall security posture. This is achieved through a cloud-based frontend that orchestrates security testing via edge collectors utilizing tools like Nmap and Nuclei.

## User Preferences
Preferred communication style: Simple, everyday language.

## Recent Changes
- **29/08/2025**: Gateway vlxsam01 totalmente funcional com NGINX proxy SSL e step-ca CA
- **29/08/2025**: URLs operacionais: https://app.samureye.com.br, https://api.samureye.com.br, https://ca.samureye.com.br
- **29/08/2025**: Collector vlxsam04 instalado e registrado com sucesso usando método simplificado
- **29/08/2025**: Endpoint `/collector-api/heartbeat` implementado e funcionando para bypass do Vite middleware
- **29/08/2025**: Collector enviando telemetria corretamente (CPU, Memory, Disk, Processes)
- **29/08/2025**: Scripts de correção on-premise criados para todos os servidores (vlxsam01, vlxsam02, vlxsam04)
- **29/08/2025**: Sistema SamurEye completamente operacional no ambiente on-premise
- **29/08/2025**: Interface de Gestão de Coletores implementada no painel admin
- **29/08/2025**: Rota `/admin/collectors` adicionada e funcional
- **29/08/2025**: Scripts corrigidos para PostgreSQL no vlxsam03 (não vlxsam02)
- **29/08/2025**: Estatísticas de coletores integradas no AdminDashboard
- **29/08/2025**: Script de teste de banco de dados criado para diagnóstico
- **29/08/2025**: Todos os install.sh atualizados com informações de Gestão de Coletores
- **29/08/2025**: vlxsam03/install.sh criado com PostgreSQL 16 e correções automáticas
- **29/08/2025**: Scripts include cron job para limpeza automática ENROLLING
- **29/08/2025**: Informações de acesso admin integradas em todos os install.sh
- **30/08/2025**: vlxsam01/install.sh otimizado para preservar certificados SSL existentes
- **30/08/2025**: Sistema de backup automático de certificados antes de reinstalação
- **30/08/2025**: Detecção inteligente de certificados válidos vs expirados
- **30/08/2025**: Configuração dinâmica NGINX baseada em certificados disponíveis
- **31/08/2025**: Scripts locais corrigidos para execução sem SSH entre servidores
- **31/08/2025**: vlxsam04 configurado para usar apenas HTTPS/443 (sem acesso direto vlxsam02)
- **31/08/2025**: fix-vlxsam03-local.sh funcionando - todas tabelas criadas com sucesso
- **31/08/2025**: Scripts de correção específicos para cada servidor criados

## System Architecture

### Frontend Architecture
The frontend is built with React 18 and TypeScript, using Vite for development. It leverages `shadcn/ui` components, Radix UI primitives, and TailwindCSS for styling. Wouter handles routing, TanStack Query manages server state, and React Hook Form with Zod is used for form validation and handling.

### Backend Architecture
The backend is an Express.js server running on Node.js, with PostgreSQL 16 managed by Drizzle ORM. It incorporates WebSockets for real-time communication and uses session-based authentication with `connect-pg-simple`, integrating Replit Auth for Single Sign-On (SSO).

### Database Design
The system employs a multi-tenant architecture to ensure strict tenant isolation. It supports a dual-user system: global admin users authenticated via Replit Auth, and tenant-scoped users with local authentication. The database schema is designed to manage user authentication, tenant information, user-tenant relationships, collector registration, security testing workflows, credential management, threat intelligence, and activity logging.

### Authentication & Authorization
SamurEye implements a dual authentication mechanism: session-based for administrators accessing the `/admin` path, and Replit OpenID Connect for regular users. Access control is multi-layered, defining roles such as global administrators, SOC users (with access to all tenants), and tenant-specific roles (tenant_admin, operator, viewer, tenant_auditor).

### Real-time Communication
A dedicated WebSocket server provides live updates for critical operational data, including collector status, telemetry streams from edge collectors, security journey execution status, and real-time security alerts.

### Security Features
Communication between collectors and the cloud platform is secured using mTLS, facilitated by an internal `step-ca` Certificate Authority. Public-facing services are secured with Let's Encrypt certificates, enforced HTTPS, and HSTS headers. Additional security measures include Content Security Policy (CSP) headers and various security middleware.

### NGINX Configuration
NGINX functions as a reverse proxy, forwarding traffic to the SamurEye application. It handles SSL termination using Let's Encrypt certificates and implements rate limiting to protect against abuse.

## External Dependencies

### Database & Storage
- **PostgreSQL 16**: Primary relational database.
- **MinIO**: Object storage (planned migration to S3).
- **Redis**: Used for caching and session management.

### Secret Management
- **Delinea Secret Server**: Integrated for secure credential storage and retrieval via API.

### Monitoring & Observability
- **Grafana**: Utilized for metrics visualization and system monitoring.
- **FortiSIEM**: For centralized log aggregation via CEF/UDP 514.

### Development & Deployment
- **Docker Registry**: Manages and stores container images.
- **step-ca**: Internal Certificate Authority for mTLS.
- **NGINX**: Acts as a reverse proxy and load balancer.
- **vSphere**: Virtualization platform for infrastructure.

### DNS & TLS
- **samureye.com.br**: Primary domain, supporting wildcard certificates.
- **Let's Encrypt DNS-01 Challenge**: For automated wildcard certificate issuance and renewal.
- Multi-provider DNS support: Cloudflare, AWS Route53, Google Cloud DNS.

### Security Tools Integration
- **Nmap**: Network scanning utility.
- **Nuclei**: Vulnerability scanning tool.
- **CVE databases**: Integrated for threat intelligence feeds.

### Edge Collector Communication
- **HTTPS-only**: Communication restricted to port 443.
- **Certificate-based authentication**: Uses certificates issued by `step-ca`.
- Encrypted telemetry streaming and secure command execution.