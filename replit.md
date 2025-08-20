# SamurEye MVP - Breach & Attack Simulation Platform

## Overview

SamurEye is a comprehensive Breach & Attack Simulation (BAS) platform designed for small to medium enterprises (SMEs) in Brazil. The platform provides attack surface validation, threat intelligence, and security testing capabilities through a cloud-based frontend and edge collectors. This MVP focuses on internal testing environments and orchestrates security testing journeys using tools like Nmap and Nuclei.

The system enables security teams to discover vulnerabilities, test EDR/AV solutions, monitor Active Directory hygiene, and validate their organization's security posture through automated testing scenarios.

## User Preferences

Preferred communication style: Simple, everyday language.

## Recent Changes

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
- **PostgreSQL** database with Drizzle ORM for type-safe database operations
- **Neon Database** as the serverless PostgreSQL provider
- **WebSocket** support for real-time updates (collector status, journey progress)
- **Session-based authentication** with connect-pg-simple for session storage
- **Replit Auth** integration for SSO capabilities

### Database Design
- **Multi-tenant architecture** with tenant isolation
- **User management** with role-based access (admin/operator/viewer)
- **Collectors** table for edge device registration and management
- **Journeys** for security testing scenarios and configurations
- **Credentials** management with Delinea Secret Server integration
- **Threat Intelligence** storage for vulnerability data
- **Activities** logging for audit trails

### Authentication & Authorization
- **Replit OpenID Connect** for admin authentication
- **Local authentication** with MFA (TOTP/Email) for tenant users
- **Session management** with PostgreSQL session store
- **Tenant-based authorization** with currentTenantId tracking

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
- **Neon Database** (PostgreSQL) - Primary data storage with connection pooling
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