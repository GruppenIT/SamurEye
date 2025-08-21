import { storage } from "./storage";

// Simple script to add different data to each tenant
export async function seedDifferentTenantData() {
  try {
    console.log("Seeding different data for each tenant...");
    
    const tenants = await storage.getAllTenants();
    
    for (const tenant of tenants) {
      // Clear existing data first
      await storage.clearTenantData(tenant.id);
      
      if (tenant.name === "Rodrigo's Organization") {
        await seedRodrigoOrg(tenant.id);
      } else if (tenant.name === "PoC") {
        await seedPoCEnvironment(tenant.id);
      }
    }
    
    console.log("Seeding completed successfully!");
  } catch (error) {
    console.error("Error seeding data:", error);
  }
}

async function seedRodrigoOrg(tenantId: string) {
  console.log("Seeding Rodrigo's Organization...");
  
  // Create enterprise collectors
  const collector1 = await storage.createCollector({
    tenantId,
    name: "Enterprise-DC-01",
    hostname: "dc01.rodrigocorp.com.br",
    ipAddress: "10.0.1.10",
    status: "online",
    version: "2.1.0",
    lastSeen: new Date(),
    metadata: {
      os: "Windows Server 2022",
      location: "São Paulo Data Center",
      capabilities: ["nmap", "nuclei", "ad_hygiene"]
    }
  });

  const collector2 = await storage.createCollector({
    tenantId,
    name: "Enterprise-Branch-SP",
    hostname: "branch-sp.rodrigocorp.com.br",
    ipAddress: "10.1.1.5",
    status: "online",
    version: "2.1.0",
    lastSeen: new Date(Date.now() - 2 * 60 * 1000),
    metadata: {
      os: "Ubuntu 22.04 LTS",
      location: "Filial São Paulo",
      capabilities: ["nmap", "nuclei"]
    }
  });

  const collector3 = await storage.createCollector({
    tenantId,
    name: "Enterprise-Branch-RJ",
    hostname: "branch-rj.rodrigocorp.com.br",
    ipAddress: "10.2.1.5",
    status: "offline",
    version: "2.0.8",
    lastSeen: new Date(Date.now() - 45 * 60 * 1000),
    metadata: {
      os: "Windows Server 2019",
      location: "Filial Rio de Janeiro",
      capabilities: ["nmap", "ad_hygiene"]
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
      { name: "nmap", cpu: 12.1, memory: 512 }
    ]
  });

  await storage.addCollectorTelemetry({
    collectorId: collector2.id,
    cpuUsage: 15.8,
    memoryUsage: 32.1,
    diskUsage: 45.3,
    networkThroughput: { inbound: 67.2, outbound: 34.8 },
    processes: [
      { name: "samureye-agent", cpu: 2.1, memory: 128 }
    ]
  });

  // Create enterprise journeys
  await storage.createJourney({
    tenantId,
    name: "Enterprise Network Discovery",
    type: "attack_surface",
    status: "running",
    config: {
      targets: ["10.0.0.0/16", "10.1.0.0/24"],
      tools: ["nmap", "nuclei"],
      schedule: "daily"
    },
    createdBy: "94b366ae-6774-4481-b240-a9836a908a20"
  });

  await storage.createJourney({
    tenantId,
    name: "AD Security Validation",
    type: "ad_hygiene",
    status: "completed",
    config: {
      domain: "rodrigocorp.com.br",
      checks: ["password_policy", "privileged_accounts"]
    },
    createdBy: "94b366ae-6774-4481-b240-a9836a908a20"
  });

  // Create enterprise credentials
  await storage.createCredential({
    tenantId,
    name: "Domain Admin Production",
    type: "ldap",
    description: "Production domain administrator",
    credentialData: {
      username: "admin.rodrigo",
      domain: "rodrigocorp.com.br"
    },
    createdBy: "94b366ae-6774-4481-b240-a9836a908a20"
  });

  // Create activities
  await storage.createActivity({
    tenantId,
    userId: "94b366ae-6774-4481-b240-a9836a908a20",
    action: "collector_enrolled",
    resource: "collector",
    resourceId: collector1.id,
    metadata: { collectorName: "Enterprise-DC-01" }
  });

  await storage.createActivity({
    tenantId,
    userId: "94b366ae-6774-4481-b240-a9836a908a20",
    action: "journey_started",
    resource: "journey",
    metadata: { journeyName: "Enterprise Network Discovery" }
  });

  console.log("✓ Rodrigo's Organization seeded with 3 collectors, 2 journeys, 1 credential");
}

async function seedPoCEnvironment(tenantId: string) {
  console.log("Seeding PoC environment...");
  
  // Create simple PoC collectors
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
      location: "PoC Lab Virtual",
      capabilities: ["nmap"]
    }
  });

  const collector2 = await storage.createCollector({
    tenantId,
    name: "PoC-Demo-01",
    hostname: "demo01.poc.local",
    ipAddress: "192.168.100.20",
    status: "enrolling",
    version: "1.9.5",
    lastSeen: new Date(Date.now() - 10 * 60 * 1000),
    metadata: {
      os: "Windows 10 Pro",
      location: "PoC Lab Physical",
      capabilities: ["nmap"]
    }
  });

  // Add telemetry
  await storage.addCollectorTelemetry({
    collectorId: collector1.id,
    cpuUsage: 8.2,
    memoryUsage: 24.1,
    diskUsage: 15.7,
    networkThroughput: { inbound: 12.3, outbound: 8.9 },
    processes: [
      { name: "samureye-agent", cpu: 1.2, memory: 64 }
    ]
  });

  // Create simple PoC journey
  await storage.createJourney({
    tenantId,
    name: "PoC Basic Scan",
    type: "attack_surface",
    status: "pending",
    config: {
      targets: ["192.168.100.0/24"],
      tools: ["nmap"]
    },
    createdBy: "94b366ae-6774-4481-b240-a9836a908a20"
  });

  // Create basic credential
  await storage.createCredential({
    tenantId,
    name: "Test Admin Account",
    type: "ssh",
    description: "Test administrator for PoC",
    credentialData: {
      username: "admin",
      hostname: "test01.poc.local"
    },
    createdBy: "94b366ae-6774-4481-b240-a9836a908a20"
  });

  // Create activities
  await storage.createActivity({
    tenantId,
    userId: "94b366ae-6774-4481-b240-a9836a908a20",
    action: "tenant_initialized",
    resource: "tenant",
    metadata: { environment: "poc" }
  });

  console.log("✓ PoC environment seeded with 2 collectors, 1 journey, 1 credential");
}