import { storage } from "./storage";

export async function seedExampleData(tenantId: string, userId: string) {
  try {
    // Create example collectors
    const collector1 = await storage.createCollector({
      tenantId,
      name: "Collector-DC-01",
      hostname: "dc01.corp.local",
      ipAddress: "192.168.1.10",
      status: "online",
      version: "1.0.0",
      lastSeen: new Date(),
      metadata: {
        os: "Windows Server 2022",
        location: "Data Center - Rack A1",
        capabilities: ["nmap", "nuclei", "ad_hygiene"]
      }
    });

    const collector2 = await storage.createCollector({
      tenantId,
      name: "Collector-DMZ-01", 
      hostname: "dmz01.corp.local",
      ipAddress: "10.0.100.5",
      status: "offline",
      version: "1.0.0",
      lastSeen: new Date(Date.now() - 30 * 60 * 1000), // 30 minutes ago
      metadata: {
        os: "Ubuntu 22.04 LTS",
        location: "DMZ Network",
        capabilities: ["nmap", "nuclei", "external_scan"]
      }
    });

    const collector3 = await storage.createCollector({
      tenantId,
      name: "Collector-Branch-01",
      hostname: "branch01.corp.local", 
      ipAddress: "192.168.10.15",
      status: "enrolling",
      version: "1.0.0",
      lastSeen: new Date(Date.now() - 5 * 60 * 1000), // 5 minutes ago
      metadata: {
        os: "CentOS 8",
        location: "Branch Office - São Paulo",
        capabilities: ["nmap", "ad_hygiene"]
      }
    });

    // Generate enrollment tokens
    await storage.generateEnrollmentToken(collector1.id);
    await storage.generateEnrollmentToken(collector2.id);
    await storage.generateEnrollmentToken(collector3.id);

    // Add some telemetry for online collector
    await storage.addCollectorTelemetry({
      collectorId: collector1.id,
      cpuUsage: 45.2,
      memoryUsage: 67.8,
      diskUsage: 23.1,
      networkThroughput: {
        inbound: 12.5,
        outbound: 8.3
      },
      processes: [
        { name: "samureye-agent", cpu: 2.1, memory: 128 },
        { name: "nmap", cpu: 15.2, memory: 512 },
        { name: "nuclei", cpu: 8.7, memory: 256 }
      ]
    });

    // Create example credentials
    await storage.createCredential({
      tenantId,
      name: "Domain Admin",
      type: "windows_domain",
      delineaSecretId: "12345",
      delineaPath: "/Active Directory/Domain Admins/Administrator",
      description: "Domain administrator account for AD hygiene tests",
      createdBy: userId
    });

    await storage.createCredential({
      tenantId,
      name: "Service Account - Scanner",
      type: "service_account",
      delineaSecretId: "12346",
      delineaPath: "/Service Accounts/Scanner/svc-scanner",
      description: "Service account for network scanning operations",
      createdBy: userId
    });

    // Create example threat intelligence
    await storage.createThreatIntelligence({
      tenantId,
      source: "MITRE ATT&CK",
      indicator: "T1003.001",
      type: "technique",
      severity: "high",
      description: "LSASS Memory dumping technique often used by attackers",
      metadata: {
        mitre: {
          tactic: "Credential Access",
          technique: "OS Credential Dumping: LSASS Memory",
          platforms: ["Windows"]
        }
      }
    });

    await storage.createThreatIntelligence({
      tenantId,
      source: "CVE Database",
      indicator: "CVE-2023-23397",
      type: "vulnerability",
      severity: "critical",
      description: "Microsoft Outlook Remote Code Execution Vulnerability",
      metadata: {
        cvss: 9.8,
        affected_products: ["Microsoft Outlook"],
        patch_available: true
      }
    });

    // Create example journeys
    await storage.createJourney({
      tenantId,
      name: "Weekly Network Scan",
      type: "attack_surface",
      config: {
        targets: ["192.168.1.0/24", "10.0.0.0/16"],
        tools: ["nmap", "nuclei"],
        schedule: "weekly"
      },
      status: "completed",
      results: {
        open_ports: 23,
        vulnerabilities_found: 5,
        services_detected: 15,
        scan_duration: "00:45:30"
      },
      collectorId: collector1.id,
      createdBy: userId,
      startedAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000), // 2 days ago
      completedAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000 + 45 * 60 * 1000) // 45 minutes later
    });

    await storage.createJourney({
      tenantId,
      name: "AD Health Check",
      type: "ad_hygiene",
      config: {
        domain: "corp.local",
        checks: ["password_policy", "stale_accounts", "privileged_accounts"],
        schedule: "monthly"
      },
      status: "running",
      collectorId: collector1.id,
      createdBy: userId,
      startedAt: new Date()
    });

    // Create some activities
    await storage.createActivity({
      tenantId,
      userId,
      action: "create",
      resource: "collector",
      resourceId: collector1.id,
      metadata: { collectorName: collector1.name }
    });

    await storage.createActivity({
      tenantId,
      userId,
      action: "complete",
      resource: "journey",
      resourceId: "journey-1",
      metadata: { journeyName: "Weekly Network Scan", duration: "45m30s" }
    });

    console.log(`✅ Example data seeded for tenant ${tenantId}`);
    return {
      collectors: [collector1, collector2, collector3],
      message: "Example data created successfully"
    };

  } catch (error) {
    console.error("Error seeding example data:", error);
    throw error;
  }
}