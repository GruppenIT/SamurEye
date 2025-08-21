import { storage } from "./storage";

// Seed different data for each tenant to demonstrate tenant switching
export async function seedTenantSpecificData() {
  try {
    console.log("Seeding tenant-specific data...");
    
    // Get all tenants
    const tenants = await storage.getAllTenants();
    
    for (const tenant of tenants) {
      console.log(`Seeding data for tenant: ${tenant.name}`);
      
      if (tenant.name === "Rodrigo's Organization") {
        await seedRodrigoOrganization(tenant.id);
      } else if (tenant.name === "PoC") {
        await seedPoCTenant(tenant.id);
      }
    }
    
    console.log("Tenant-specific seeding completed!");
  } catch (error) {
    console.error("Error seeding tenant data:", error);
  }
}

async function seedRodrigoOrganization(tenantId: string) {
  // Clear existing data
  await storage.clearTenantData(tenantId);
  
  // Create collectors for Rodrigo's Organization - Enterprise setup
  const collector1 = await storage.createCollector({
    tenantId,
    name: "RodrigoCorp-DC-01",
    hostname: "dc01.rodrigocorp.com.br",
    ipAddress: "10.0.1.10",
    status: "online",
    version: "2.1.0",
    lastSeen: new Date(),
    metadata: {
      os: "Windows Server 2022",
      location: "São Paulo Data Center - Rack A1",
      capabilities: ["nmap", "nuclei", "ad_hygiene", "edr_testing"]
    }
  });

  const collector2 = await storage.createCollector({
    tenantId,
    name: "RodrigoCorp-Branch-SP",
    hostname: "branch-sp.rodrigocorp.com.br", 
    ipAddress: "10.1.1.5",
    status: "online",
    version: "2.1.0",
    lastSeen: new Date(Date.now() - 2 * 60 * 1000),
    metadata: {
      os: "Ubuntu 22.04 LTS",
      location: "Filial São Paulo - Pinheiros",
      capabilities: ["nmap", "nuclei", "external_scan"]
    }
  });

  const collector3 = await storage.createCollector({
    tenantId,
    name: "RodrigoCorp-Branch-RJ",
    hostname: "branch-rj.rodrigocorp.com.br",
    ipAddress: "10.2.1.5", 
    status: "offline",
    version: "2.0.8",
    lastSeen: new Date(Date.now() - 45 * 60 * 1000),
    metadata: {
      os: "Windows Server 2019",
      location: "Filial Rio de Janeiro - Copacabana",
      capabilities: ["nmap", "ad_hygiene"]
    }
  });

  // Create journeys for enterprise environment
  await storage.createJourney({
    tenantId,
    name: "Enterprise Network Discovery",
    description: "Comprehensive network mapping for enterprise infrastructure",
    type: "attack_surface",
    config: {
      targets: ["10.0.0.0/16", "10.1.0.0/24", "10.2.0.0/24"],
      tools: ["nmap", "nuclei"],
      schedule: "daily",
      notifications: true
    },
    status: "active"
  });

  await storage.createJourney({
    tenantId,
    name: "AD Hygiene - Corporate Domain",
    description: "Active Directory security validation for rodrigocorp.com.br domain",
    type: "ad_hygiene", 
    config: {
      domain: "rodrigocorp.com.br",
      checkPasswordPolicy: true,
      checkPrivilegedAccounts: true,
      checkGPOSecurity: true
    },
    status: "active"
  });

  // Create credentials for enterprise
  await storage.createCredential({
    tenantId,
    name: "Domain Admin - Production",
    type: "domain_admin",
    username: "admin.rodrigo",
    description: "Production domain administrator account",
    metadata: {
      domain: "rodrigocorp.com.br",
      environment: "production"
    }
  });

  await storage.createCredential({
    tenantId,
    name: "Service Account - Backup",
    type: "service_account", 
    username: "svc-backup",
    description: "Service account for backup operations",
    metadata: {
      service: "Veeam Backup",
      permissions: "backup_operator"
    }
  });

  // Add telemetry for online collectors
  await storage.addCollectorTelemetry({
    collectorId: collector1.id,
    cpuUsage: 23.5,
    memoryUsage: 45.2,
    diskUsage: 67.8,
    networkThroughput: { inbound: 125.5, outbound: 89.3 },
    processes: [
      { name: "samureye-agent", cpu: 3.2, memory: 256 },
      { name: "nmap", cpu: 12.1, memory: 512 },
      { name: "nuclei", cpu: 8.2, memory: 384 }
    ]
  });

  await storage.addCollectorTelemetry({
    collectorId: collector2.id,
    cpuUsage: 15.8,
    memoryUsage: 32.1,
    diskUsage: 45.3,
    networkThroughput: { inbound: 67.2, outbound: 34.8 },
    processes: [
      { name: "samureye-agent", cpu: 2.1, memory: 128 },
      { name: "nmap", cpu: 8.7, memory: 256 }
    ]
  });

  // Create activities for this tenant
  await storage.createActivity({
    tenantId,
    userId: "94b366ae-6774-4481-b240-a9836a908a20", // Rodrigo's ID
    type: "collector_enrolled",
    description: "Collector RodrigoCorp-DC-01 successfully enrolled",
    metadata: { collectorId: collector1.id }
  });

  await storage.createActivity({
    tenantId,
    userId: "94b366ae-6774-4481-b240-a9836a908a20",
    type: "journey_started",
    description: "Started Enterprise Network Discovery journey",
    metadata: { journeyName: "Enterprise Network Discovery" }
  });
}

async function seedPoCTenant(tenantId: string) {
  // Clear existing data
  await storage.clearTenantData(tenantId);
  
  // Create collectors for PoC - Smaller test environment
  const collector1 = await storage.createCollector({
    tenantId,
    name: "PoC-Test-01",
    hostname: "test01.poc.local",
    ipAddress: "192.168.100.10",
    status: "online",
    version: "1.9.5",
    lastSeen: new Date(),
    metadata: {
      os: "Ubuntu 20.04 LTS",
      location: "PoC Lab - Virtual Environment", 
      capabilities: ["nmap", "nuclei"]
    }
  });

  const collector2 = await storage.createCollector({
    tenantId,
    name: "PoC-Win-01",
    hostname: "win01.poc.local",
    ipAddress: "192.168.100.20",
    status: "enrolling",
    version: "1.9.5", 
    lastSeen: new Date(Date.now() - 10 * 60 * 1000),
    metadata: {
      os: "Windows 10 Pro",
      location: "PoC Lab - Physical Machine",
      capabilities: ["nmap", "ad_hygiene"]
    }
  });

  // Create simple journeys for PoC
  await storage.createJourney({
    tenantId,
    name: "PoC Network Scan",
    description: "Basic network scanning for proof of concept",
    type: "attack_surface",
    config: {
      targets: ["192.168.100.0/24"],
      tools: ["nmap"],
      schedule: "manual",
      notifications: false
    },
    status: "draft"
  });

  await storage.createJourney({
    tenantId, 
    name: "Vulnerability Assessment - PoC",
    description: "Basic vulnerability scanning for demo purposes",
    type: "attack_surface",
    config: {
      targets: ["192.168.100.10-50"],
      tools: ["nuclei"],
      templates: ["basic", "cve-2024"],
      schedule: "weekly"
    },
    status: "active"
  });

  // Create basic credentials for PoC
  await storage.createCredential({
    tenantId,
    name: "Test Admin",
    type: "local_admin",
    username: "admin",
    description: "Local administrator for PoC environment",
    metadata: {
      environment: "test",
      scope: "local"
    }
  });

  // Add telemetry for PoC collector
  await storage.addCollectorTelemetry({
    collectorId: collector1.id,
    cpuUsage: 8.2,
    memoryUsage: 24.1,
    diskUsage: 15.7,
    networkThroughput: { inbound: 12.3, outbound: 8.9 },
    processes: [
      { name: "samureye-agent", cpu: 1.2, memory: 64 },
      { name: "nmap", cpu: 5.1, memory: 128 }
    ]
  });

  // Create activities for PoC tenant
  await storage.createActivity({
    tenantId,
    userId: "94b366ae-6774-4481-b240-a9836a908a20", // Rodrigo's ID (SOC user)
    type: "tenant_created", 
    description: "PoC tenant environment initialized",
    metadata: { environment: "poc" }
  });

  await storage.createActivity({
    tenantId,
    userId: "94b366ae-6774-4481-b240-a9836a908a20",
    type: "collector_enrolling",
    description: "Collector PoC-Win-01 enrollment in progress",
    metadata: { collectorId: collector2.id }
  });
}