# SamurEye MVP - Breach & Attack Simulation Platform

## Overview
SamurEye is a cloud-based Breach & Attack Simulation (BAS) platform for SMEs in Brazil. It provides attack surface validation, threat intelligence, and security testing capabilities. The platform automates vulnerability discovery, tests EDR/AV solutions, monitors Active Directory hygiene, and validates security posture using a cloud-based frontend and edge collectors to orchestrate security testing with tools like Nmap and Nuclei.

## User Preferences
Preferred communication style: Simple, everyday language.

## System Architecture

### Frontend Architecture
The frontend uses React 18 with TypeScript, built with Vite. It features shadcn/ui components, Radix UI primitives, and TailwindCSS for styling. Wouter is used for routing, TanStack Query for server state management, and React Hook Form with Zod for form handling.

### Backend Architecture
The backend is an Express.js server on Node.js, with PostgreSQL 16 managed by Drizzle ORM. It supports WebSockets for real-time updates and uses session-based authentication with connect-pg-simple, integrating Replit Auth for SSO.

### Database Design
A multi-tenant architecture ensures strict tenant isolation. It includes a dual user system: global admin users via Replit Auth and tenant-scoped users with local authentication. The schema supports user authentication, tenant management, user-tenant relationships, collector registration, security testing journeys, credential management, threat intelligence, and activity logging.

### Authentication & Authorization
SamurEye employs a dual authentication system: session-based for administrators at `/admin` and Replit OpenID Connect for regular users. Access control is multi-layered, including global admins, SOC users (all tenants), and tenant-specific roles (tenant_admin, operator, viewer, tenant_auditor).

### Real-time Communication
A WebSocket server provides live updates for collector status, telemetry streaming from edge collectors, journey execution status, and security alerts.

### Security Features
mTLS secures collector-to-cloud communication via an internal step-ca Certificate Authority. Public services use Let's Encrypt certificates with HTTPS enforcement and HSTS headers. CSP headers and other security middleware are applied.

### NGINX Configuration
NGINX acts as a reverse proxy on `vlxsam01`, forwarding traffic to the SamurEye application on `vlxsam02`. It handles SSL termination with Let's Encrypt certificates and supports rate limiting.

## External Dependencies

### Database & Storage
- **PostgreSQL 16**: Primary data storage.
- **MinIO**: Object storage for scan results (planned S3 migration).
- **Redis**: Caching and session storage.

### Secret Management
- **Delinea Secret Server**: Credential storage via API integration.

### Monitoring & Observability
- **Grafana**: Metrics and monitoring.
- **FortiSIEM**: Log aggregation (CEF/UDP 514).

### Development & Deployment
- **Docker Registry**: Container image management.
- **step-ca**: Internal Certificate Authority.
- **NGINX**: Reverse proxy and load balancer.
- **vSphere**: Virtualization platform.

### DNS & TLS
- **samureye.com.br**: Domain with wildcard certificate support.
- **Let's Encrypt DNS-01 Challenge**: For wildcard certificates and automated renewal.
- Multi-provider DNS support (Cloudflare, AWS Route53, Google Cloud DNS).

### Security Tools Integration
- **Nmap**: Network scanning.
- **Nuclei**: Vulnerability scanning.
- **CVE databases**: Threat intelligence.

### Edge Collector Communication
- **HTTPS-only** communication on port 443.
- **Certificate-based authentication** via `step-ca` issued certificates.
- Encrypted telemetry streaming and secure command execution.

## Recent Updates

### vlxsam04 Collector Agent - Complete Installation (August 28, 2025)
Successfully completed full collector agent installation with all required components:

**Infrastructure Setup:**
1. **Ubuntu 24.04 PEP 668 Compatibility**: Implemented `--break-system-packages` flag for Python package installation
2. **Robust Package Installation**: Automatic fallback mechanisms for masscan source compilation when apt repositories fail
3. **Silent Operations**: Non-interactive downloads using `-q -o` flags preventing script interruption
4. **Directory Structure Fix**: Corrected scripts directory creation order to prevent file write failures

**Security Tools Integration:**
5. **Nuclei 3.1.0 Compatibility**: Fixed flag compatibility by using environment variable `NUCLEI_TEMPLATES_DIR` instead of deprecated `-templates-dir` flag
6. **Multi-tool Support**: Complete integration of nmap, nuclei, masscan, gobuster with proper template management

**Collector Agent Components:**
7. **Multi-tenant Python Agent**: Complete async agent with API client, WebSocket client, telemetry collector, and command executor
8. **mTLS Security**: Full certificate-based authentication system with step-ca integration
9. **Systemd Services**: Production-ready service configuration with health monitoring and automatic restart
10. **Logging & Monitoring**: Comprehensive logging system with log rotation and health checks
11. **Environment Configuration**: Complete .env setup with all required variables

**Production Features:**
- Multi-tenant isolation with workspace separation
- Resource limits and security restrictions
- Automated backup and cleanup scripts
- Comprehensive validation and error handling
- Fixed auxiliary scripts creation with proper directory structure

The vlxsam04 install.sh is now a complete, production-ready collector agent installer that concentrates ALL solutions in a single file without external dependencies. Directory creation bug fixed, permission issues resolved with integrated final permission correction - ready for manual collector registration process.

**Critical Permission Fix Integrated (August 28, 2025):**
- Fixed .env file permissions: 644 instead of 640/600 (readable by samureye-collector user)
- Fixed .env ownership: samureye-collector:samureye-collector instead of root:samureye-collector
- Added comprehensive final permission validation ensuring collector user can access all required files
- Integrated permission test verification before service startup to prevent PermissionError failures

**Script Duplication Bug Fixed (August 28, 2025):**
- **CRITICAL FIX**: Removed complete script duplication in vlxsam04 install.sh causing double execution
- Eliminated duplicate sections 13.1, 13.2, 13.3 causing chown errors with undefined variables
- Reduced script from 1,807 to 1,185 lines (622 duplicate lines removed)
- Fixed double execution of configuration steps preventing installation errors
- Script now has clean single execution path with proper exit handling

**SystemD Service Configuration Fixed (August 28, 2025):**
- **CRITICAL SYSTEMD FIX**: Added missing .env file creation in section 8 of install.sh
- Added collector_agent.py functional Python agent in /opt/samureye-collector/
- Corrected systemd service paths: EnvironmentFile now points to $CONFIG_DIR/.env
- Fixed ExecStart path to point to $COLLECTOR_DIR/collector_agent.py  
- SystemD service now starts without "Failed to load environment files" errors
- Collector agent ready for production with proper configuration and startup

**vlxsam04 SystemD Service - PROBLEMA RESOLVIDO COMPLETAMENTE (August 28, 2025):**
- **SUCCESS CONFIRMED**: SystemD service starting successfully after all corrections applied
- Service status: "Started samureye-collector.service - SamurEye Collector Agent - vlxsam04"
- Agent running: "Starting SamurEye Collector Agent c0355198-b952-4630-a00c-2934344bc2ba"
- Restart counter reset from 207+ to normal operation levels
- Environment files loading correctly, no more "No such file or directory" errors
- Functional Python agent with heartbeat, logging, and configuration management
- Ready for manual collector registration with mTLS certificate setup