# SamurEye MVP - Breach & Attack Simulation Platform

## Overview

SamurEye is a comprehensive Breach & Attack Simulation (BAS) platform designed for small to medium enterprises (SMEs) in Brazil. The platform provides attack surface validation, threat intelligence, and security testing capabilities through a cloud-based frontend and edge collectors. This MVP focuses on internal testing environments and orchestrates security testing journeys using tools like Nmap and Nuclei.

The system enables security teams to discover vulnerabilities, test EDR/AV solutions, monitor Active Directory hygiene, and validate their organization's security posture through automated testing scenarios.

## User Preferences

Preferred communication style: Simple, everyday language.

## Recent Changes

**August 26, 2025 - vlxsam03 Install Script Enhanced with Auto-Reset and Detection**
- Enhanced vlxsam03 install.sh script to function as reliable "reset" mechanism for server
- Added auto-detection of PostgreSQL connection (postgres user → localhost → vlxsam03 IP)
- Implemented automatic cluster corruption detection and complete PostgreSQL reinstallation
- Created reset-postgres.sh emergency script with full database recreation from scratch
- Database reset now includes: DROP DATABASE/ROLE IF EXISTS + clean recreation + extensions
- Added connection testing with multiple fallback methods for environment compatibility
- Script works as complete server reset - can be re-run safely multiple times
- Created symlink samureye-reset-postgres for easy emergency PostgreSQL recovery
- Updated vlxsam03 README with comprehensive troubleshooting and reset procedures
- Migration from vlxsam03 PostgreSQL (172.24.1.153:5432) to Replit PostgreSQL completed successfully

**August 22, 2025 - Complete Dashboard Components Migration to API Data**
- Created tenant-specific dashboard endpoints: /api/dashboard/attack-surface, /api/dashboard/edr-events, /api/dashboard/journey-results
- Migrated all dashboard components (AttackSurfaceHeatmap, EDRTimeline, JourneyResults) from static mock data to real API data
- Implemented complete data isolation between tenants across all dashboard components
- Tenant data verification successful:
  - "Rodrigo's Organization": 847 hosts scanned, 142 inactive accounts, 94.2% EDR detection rate
  - "PoC": 127 hosts scanned, 23 inactive accounts, 78.3% EDR detection rate
- Enhanced TenantContext cache invalidation to include all new dashboard endpoints
- Dashboard now fully responsive to tenant switching with real-time data updates

**August 22, 2025 - Tenant Switching Functionality Completed**
- Fixed critical issue with tenant switching for SOC users 
- Enhanced switch-tenant endpoint to properly handle SOC user permissions for all tenants
- Corrected requireLocalUserTenant middleware to respect user.currentTenantId for SOC users
- Successfully implemented data isolation between tenants with correct metrics display
- Tenant "Rodrigo's Organization": 3 collectors (2 online), 2 journeys (1 active)  
- Tenant "PoC": 2 collectors (1 online), 1 journey (0 active)
- ActivityFeed component created to replace problematic RecentActivities component
- Dashboard now loads correctly with proper tenant-specific data filtering

**August 20, 2025 - Complete Access Control System Restructuring**
- Completely restructured access control system with dedicated admin interface at `/admin`
- Created separate admin authentication system with hardcoded credentials (admin@samureye.com.br / SamurEye2024!)
- Implemented comprehensive admin dashboard for tenant and user management
- Added SOC user concept - users with access to all tenants marked with isSocUser flag
- New admin routes: `/admin` (login), `/admin/dashboard` (main), `/admin/users/create` (user creation)
- Admin can create/delete tenants and create users with tenant-role assignments
- Updated database schema with new user fields: password, isSocUser, isActive, lastLoginAt
- Separated admin functionality from regular user system for better security isolation
- Admin system uses session-based authentication independent of Replit Auth

**August 20, 2025 - Complete Documentation and Installation Refactoring**
- Refactored all deployment documentation and scripts for production-ready installation
- Created comprehensive README files for each server (vlxsam01-04) with step-by-step instructions
- Removed all temporary "fix" scripts in favor of clean installation from scratch
- Updated main deployment README with proper server installation order and dependencies
- Created consolidated verification script for complete multi-server installation testing
- Standardized all installation scripts with proper error handling, logging, and security
- Documentation now matches exactly what the installation scripts perform

**August 20, 2025 - SSL Certificate System Complete with Manual Renewal**
- Successfully resolved SSL certificate rate limiting issues with comprehensive improvements  
- Implemented "DNS Manual Assistido" option with two-stage validation (staging → production)
- Added automatic rate limit detection to prevent "Service busy" errors
- Created complete certificate management system with verification scripts and renewal reminders
- Fixed certificate renewal process for manual certificates with proper cron configuration
- Added comprehensive troubleshooting documentation for all SSL-related issues
- Wildcard certificate (*.samureye.com.br) now active with 90-day manual renewal cycle

**December 20, 2024 - Enhanced SSL/TLS Security with DNS Challenge**
- Migrated SSL certificate system from HTTP-01 to DNS-01 challenge for enhanced security
- Updated certificate setup to support wildcard certificates (*.samureye.com.br)
- Added automated certificate configuration for multiple DNS providers (Cloudflare, Route53, Google Cloud DNS)
- Created comprehensive DNS configuration documentation with provider-specific guides
- Enhanced certificate renewal automation with improved hooks and error handling
- Added migration functionality for existing HTTP-based certificates to DNS wildcard
- Improved security posture by eliminating need to stop web services during certificate operations

**December 20, 2024 - Comprehensive Deployment Documentation with Specific IPs**
- Created complete infrastructure deployment documentation for all four servers with specific IP addresses
- vlxsam01 (172.24.1.151): Gateway/NGINX with SSL termination and DNS-based certificate management
- vlxsam02 (172.24.1.152): Frontend+Backend Node.js application with scanner service
- vlxsam03 (172.24.1.153): Database cluster with PostgreSQL, Redis, and MinIO
- vlxsam04 (192.168.100.151): Collector agent with outbound-only communication
- Automated installation scripts with DNS certificate plugin support
- Network architecture documentation emphasizing collector's outbound-only design
- Fixed tenant auto-creation issue for new users to resolve "No active tenant selected" error

## System Architecture

### Frontend Architecture
- **React 18** with TypeScript for the web application
- **Vite** as the build tool and development server
- **shadcn/ui** components with Radix UI primitives for consistent UI
- **TailwindCSS** for styling with custom design tokens
- **Wouter** for client-side routing
- **TanStack Query** for server state management and API interactions
- **React Hook Form** with Zod validation for form handling

### Backend Architecture
- **Express.js** server with TypeScript
- **Node.js** runtime environment
- **PostgreSQL 16** database with Drizzle ORM for type-safe database operations
- **Local PostgreSQL** server running on vlxsam03 (172.24.1.153:5432)
- **WebSocket** support for real-time updates (collector status, journey progress)
- **Session-based authentication** with connect-pg-simple for session storage
- **Replit Auth** integration for SSO capabilities

### Database Design
- **Multi-tenant architecture** with tenant isolation
- **Dual user system**:
  - **Admin users**: Global system administrators (via Replit Auth)
  - **Tenant users**: Scoped to specific tenants with local authentication
- **Enhanced user table** with password, isSocUser, isActive, lastLoginAt fields
- **Tenant management** with full CRUD operations for admins
- **User-tenant relationships** via tenantUsers table with role assignments
- **Collectors** table for edge device registration and management
- **Journeys** for security testing scenarios and configurations
- **Credentials** management with Delinea Secret Server integration
- **Threat Intelligence** storage for vulnerability data
- **Activities** logging for audit trails

### Authentication & Authorization
- **Dual Authentication System**:
  - **Admin System**: Session-based authentication at `/admin` with hardcoded credentials
  - **User System**: Replit OpenID Connect for regular users
- **Multi-level Access Control**:
  - **Global Admins**: Full system access via `/admin` interface
  - **SOC Users**: Access to all tenants (isSocUser = true)
  - **Tenant Users**: Limited to specific tenant access with role-based permissions
- **Session management** with PostgreSQL session store
- **Tenant-based authorization** with currentTenantId tracking
- **Role-based permissions**: tenant_admin, operator, viewer, tenant_auditor

### Real-time Communication
- **WebSocket server** for live updates of collector status
- **Real-time telemetry** streaming from edge collectors
- **Journey execution** status updates
- **Alert notifications** for critical security findings

### Security Features
- **mTLS** for collector-to-cloud communication
- **step-ca** internal Certificate Authority for collector certificates
- **Let's Encrypt** certificates for public-facing services
- **HTTPS enforcement** with HSTS headers
- **CSP headers** and security middleware

## External Dependencies

### Database & Storage
- **PostgreSQL 16** (Local) - Primary data storage on vlxsam03 with connection pooling
- **MinIO** - Object storage for scan results and evidence files (future S3 migration planned)
- **Redis** - Caching and session storage

### Secret Management
- **Delinea Secret Server** (gruppenztna.secretservercloud.com) - Credential storage via API integration
- **API Key authentication** for Delinea integration

### Monitoring & Observability
- **Grafana** stack for metrics and monitoring
- **FortiSIEM** integration for log aggregation via CEF/UDP 514
- **Custom telemetry** collection from edge collectors

### Development & Deployment
- **Docker Registry** for container image management
- **step-ca** for internal certificate management
- **NGINX** as reverse proxy and load balancer
- **vSphere** virtualization platform for infrastructure

### DNS & TLS
- **samureye.com.br** domain with wildcard certificate support (*.samureye.com.br)
- **Let's Encrypt DNS-01 Challenge** for enhanced security and wildcard certificates
- **Multi-provider DNS support**: Cloudflare, AWS Route53, Google Cloud DNS, manual configuration
- **Automated certificate management** with intelligent renewal hooks and migration capabilities
- **Enhanced security posture** with no service interruption during certificate operations

### Security Tools Integration
- **Nmap** for network scanning and discovery
- **Nuclei** for vulnerability scanning and testing
- **CVE databases** for threat intelligence correlation
- **Custom security frameworks** for testing methodologies

### Edge Collector Communication
- **HTTPS-only** communication on port 443
- **Certificate-based authentication** with step-ca issued certificates
- **Encrypted telemetry** streaming for system metrics
- **Secure command execution** for security testing tools