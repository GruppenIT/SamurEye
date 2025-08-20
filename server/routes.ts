import type { Express, RequestHandler } from "express";
import { createServer, type Server } from "http";
import { WebSocketServer, WebSocket } from "ws";
import { storage } from "./storage";
import { setupAuth, isAuthenticated } from "./replitAuth";
import { z } from "zod";
import { 
  insertCollectorSchema, 
  insertJourneySchema, 
  insertCredentialSchema,
  insertTenantSchema,
  tenantRoleEnum 
} from "@shared/schema";
import axios from "axios";
import { randomUUID } from "crypto";
import { ObjectStorageService, ObjectNotFoundError } from "./objectStorage";

// Tenant middleware
const requireTenant: RequestHandler = async (req: any, res, next) => {
  try {
    const userId = req.user?.claims?.sub;
    if (!userId) {
      return res.status(401).json({ message: "Unauthorized" });
    }

    const user = await storage.getUser(userId);
    if (!user?.currentTenantId) {
      return res.status(400).json({ message: "No active tenant selected" });
    }

    const tenant = await storage.getTenant(user.currentTenantId);
    if (!tenant) {
      return res.status(404).json({ message: "Active tenant not found" });
    }

    req.tenant = tenant;
    req.userId = userId;
    next();
  } catch (error) {
    console.error("Tenant middleware error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Delinea Secret Server integration
const delineaApiKey = process.env.DELINEA_API_KEY || process.env.API_KEY || "default_key";
const delineaBaseUrl = "https://gruppenztna.secretservercloud.com";

async function createDelineaSecret(tenantSlug: string, credentialType: string, credentialName: string, secretData: any) {
  try {
    const path = `BAS/${tenantSlug}/${credentialType}/${credentialName}`;
    
    const response = await axios.post(`${delineaBaseUrl}/api/v1/secrets`, {
      name: credentialName,
      path: path,
      folderId: null, // Will be created in appropriate folder
      secretData: secretData
    }, {
      headers: {
        'Authorization': `Bearer ${delineaApiKey}`,
        'Content-Type': 'application/json'
      }
    });

    return {
      secretId: response.data.id,
      path: path
    };
  } catch (error) {
    console.error("Error creating Delinea secret:", error);
    throw new Error("Failed to create secret in Delinea");
  }
}

export async function registerRoutes(app: Express): Promise<Server> {
  // Auth middleware
  await setupAuth(app);

  // User routes
  app.get('/api/auth/user', isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const user = await storage.getUser(userId);
      if (!user) {
        return res.status(404).json({ message: "User not found" });
      }

      const tenants = await storage.getUserTenants(userId);
      const currentTenant = user.currentTenantId 
        ? await storage.getTenant(user.currentTenantId)
        : null;

      res.json({
        ...user,
        tenants,
        currentTenant
      });
    } catch (error) {
      console.error("Error fetching user:", error);
      res.status(500).json({ message: "Failed to fetch user" });
    }
  });

  app.post('/api/auth/switch-tenant', isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const { tenantId } = req.body;

      // Verify user has access to this tenant
      const userTenants = await storage.getUserTenants(userId);
      const hasAccess = userTenants.some(ut => ut.tenantId === tenantId);
      
      if (!hasAccess) {
        return res.status(403).json({ message: "Access denied to this tenant" });
      }

      await storage.updateUserCurrentTenant(userId, tenantId);
      res.json({ message: "Tenant switched successfully" });
    } catch (error) {
      console.error("Error switching tenant:", error);
      res.status(500).json({ message: "Failed to switch tenant" });
    }
  });

  // Collector routes
  app.get('/api/collectors', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const collectors = await storage.getCollectorsByTenant(req.tenant.id);
      res.json(collectors);
    } catch (error) {
      console.error("Error fetching collectors:", error);
      res.status(500).json({ message: "Failed to fetch collectors" });
    }
  });

  app.post('/api/collectors', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const validatedData = insertCollectorSchema.parse({
        ...req.body,
        tenantId: req.tenant.id
      });

      const collector = await storage.createCollector(validatedData);
      const enrollmentToken = await storage.generateEnrollmentToken(collector.id);

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.userId,
        action: 'create',
        resource: 'collector',
        resourceId: collector.id,
        metadata: { collectorName: collector.name }
      });

      res.json({ ...collector, enrollmentToken });
    } catch (error) {
      console.error("Error creating collector:", error);
      res.status(500).json({ message: "Failed to create collector" });
    }
  });

  app.post('/api/collectors/:id/regenerate-token', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const collector = await storage.getCollector(req.params.id);
      if (!collector || collector.tenantId !== req.tenant.id) {
        return res.status(404).json({ message: "Collector not found" });
      }

      const enrollmentToken = await storage.generateEnrollmentToken(collector.id);
      res.json({ enrollmentToken });
    } catch (error) {
      console.error("Error regenerating token:", error);
      res.status(500).json({ message: "Failed to regenerate token" });
    }
  });

  // Collector telemetry endpoint (authenticated via enrollment token)
  app.post('/api/telemetry', async (req, res) => {
    try {
      const { token, telemetry } = req.body;
      
      if (!token) {
        return res.status(401).json({ message: "Enrollment token required" });
      }

      const collector = await storage.getCollectorByEnrollmentToken(token);
      if (!collector) {
        return res.status(401).json({ message: "Invalid or expired token" });
      }

      // Update collector status
      await storage.updateCollectorStatus(collector.id, 'online');

      // Store telemetry
      await storage.addCollectorTelemetry({
        collectorId: collector.id,
        cpuUsage: telemetry.cpuUsage,
        memoryUsage: telemetry.memoryUsage,
        diskUsage: telemetry.diskUsage,
        networkThroughput: telemetry.networkThroughput,
        processes: telemetry.processes
      });

      res.json({ message: "Telemetry received" });
    } catch (error) {
      console.error("Error processing telemetry:", error);
      res.status(500).json({ message: "Failed to process telemetry" });
    }
  });

  // Journey routes
  app.get('/api/journeys', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const journeys = await storage.getJourneysByTenant(req.tenant.id);
      res.json(journeys);
    } catch (error) {
      console.error("Error fetching journeys:", error);
      res.status(500).json({ message: "Failed to fetch journeys" });
    }
  });

  app.post('/api/journeys', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const validatedData = insertJourneySchema.parse({
        ...req.body,
        tenantId: req.tenant.id,
        createdBy: req.userId
      });

      const journey = await storage.createJourney(validatedData);

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.userId,
        action: 'create',
        resource: 'journey',
        resourceId: journey.id,
        metadata: { journeyName: journey.name, journeyType: journey.type }
      });

      res.json(journey);
    } catch (error) {
      console.error("Error creating journey:", error);
      res.status(500).json({ message: "Failed to create journey" });
    }
  });

  app.post('/api/journeys/:id/start', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const journey = await storage.getJourney(req.params.id);
      if (!journey || journey.tenantId !== req.tenant.id) {
        return res.status(404).json({ message: "Journey not found" });
      }

      await storage.updateJourneyStatus(journey.id, 'running');

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.userId,
        action: 'start',
        resource: 'journey',
        resourceId: journey.id,
        metadata: { journeyName: journey.name }
      });

      res.json({ message: "Journey started" });
    } catch (error) {
      console.error("Error starting journey:", error);
      res.status(500).json({ message: "Failed to start journey" });
    }
  });

  // Credential routes
  app.get('/api/credentials', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const credentials = await storage.getCredentialsByTenant(req.tenant.id);
      res.json(credentials);
    } catch (error) {
      console.error("Error fetching credentials:", error);
      res.status(500).json({ message: "Failed to fetch credentials" });
    }
  });

  app.post('/api/credentials', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const { secretData, ...credentialData } = req.body;
      
      const validatedData = insertCredentialSchema.parse({
        ...credentialData,
        tenantId: req.tenant.id,
        createdBy: req.userId
      });

      // Create secret in Delinea
      const { secretId, path } = await createDelineaSecret(
        req.tenant.slug,
        validatedData.type,
        validatedData.name,
        secretData
      );

      // Store credential reference
      const credential = await storage.createCredential({
        ...validatedData,
        delineaSecretId: secretId,
        delineaPath: path,
        createdBy: req.userId
      });

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.userId,
        action: 'create',
        resource: 'credential',
        resourceId: credential.id,
        metadata: { credentialName: credential.name, credentialType: credential.type }
      });

      res.json(credential);
    } catch (error) {
      console.error("Error creating credential:", error);
      res.status(500).json({ message: "Failed to create credential" });
    }
  });

  // Threat Intelligence routes
  app.get('/api/threat-intelligence', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const intelligence = await storage.getThreatIntelligenceByTenant(req.tenant.id);
      res.json(intelligence);
    } catch (error) {
      console.error("Error fetching threat intelligence:", error);
      res.status(500).json({ message: "Failed to fetch threat intelligence" });
    }
  });

  // Activity routes
  app.get('/api/activities', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const limit = parseInt(req.query.limit as string) || 20;
      const activities = await storage.getActivitiesByTenant(req.tenant.id, limit);
      res.json(activities);
    } catch (error) {
      console.error("Error fetching activities:", error);
      res.status(500).json({ message: "Failed to fetch activities" });
    }
  });

  // Dashboard metrics route
  app.get('/api/dashboard/metrics', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const collectors = await storage.getCollectorsByTenant(req.tenant.id);
      const journeys = await storage.getJourneysByTenant(req.tenant.id);
      const threatIntel = await storage.getThreatIntelligenceByTenant(req.tenant.id);

      const onlineCollectors = collectors.filter(c => c.status === 'online').length;
      const totalCollectors = collectors.length;
      const activeJourneys = journeys.filter(j => j.status === 'running').length;
      const criticalThreats = threatIntel.filter(t => t.severity === 'critical').length;

      // Mock some additional metrics for demo
      const metrics = {
        collectors: {
          online: onlineCollectors,
          total: totalCollectors
        },
        journeys: {
          active: activeJourneys,
          total: journeys.length
        },
        vulnerabilities: {
          critical: criticalThreats,
          high: threatIntel.filter(t => t.severity === 'high').length,
          medium: threatIntel.filter(t => t.severity === 'medium').length,
          low: threatIntel.filter(t => t.severity === 'low').length
        },
        assets: {
          total: 1247 // This would come from journey results in real implementation
        },
        edr: {
          detectionRate: 94.2, // This would come from EDR journey results
          blockRate: 87.8,
          avgLatency: 1.2
        }
      };

      res.json(metrics);
    } catch (error) {
      console.error("Error fetching dashboard metrics:", error);
      res.status(500).json({ message: "Failed to fetch dashboard metrics" });
    }
  });

  // Global Admin Routes (for system management)
  app.get('/api/admin/tenants', isAuthenticated, async (req: any, res) => {
    try {
      const user = await storage.getUser(req.user.claims.sub);
      if (!user?.isGlobalUser || user.globalRole !== 'global_admin') {
        return res.status(403).json({ message: "Global admin access required" });
      }

      const tenants = await storage.getAllTenants();
      res.json(tenants);
    } catch (error) {
      console.error("Error fetching tenants:", error);
      res.status(500).json({ message: "Failed to fetch tenants" });
    }
  });

  app.post('/api/admin/tenants', isAuthenticated, async (req: any, res) => {
    try {
      const user = await storage.getUser(req.user.claims.sub);
      if (!user?.isGlobalUser || user.globalRole !== 'global_admin') {
        return res.status(403).json({ message: "Global admin access required" });
      }

      const validatedData = insertTenantSchema.parse(req.body);
      const tenant = await storage.createTenant(validatedData);

      // Log activity
      await storage.createActivity({
        userId: req.user.claims.sub,
        action: 'create',
        resource: 'tenant',
        resourceId: tenant.id,
        metadata: { tenantName: tenant.name }
      });

      res.json(tenant);
    } catch (error) {
      console.error("Error creating tenant:", error);
      res.status(500).json({ message: "Failed to create tenant" });
    }
  });

  // Tenant management routes
  app.get('/api/tenant/users', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const user = await storage.getUser(req.userId);
      const userTenants = await storage.getUserTenants(req.userId);
      const currentTenant = userTenants.find(ut => ut.tenantId === req.tenant.id);
      
      if (!currentTenant || !['tenant_admin'].includes(currentTenant.role)) {
        return res.status(403).json({ message: "Tenant admin access required" });
      }

      const tenantUsers = await storage.getTenantUsers(req.tenant.id);
      res.json(tenantUsers);
    } catch (error) {
      console.error("Error fetching tenant users:", error);
      res.status(500).json({ message: "Failed to fetch users" });
    }
  });

  app.post('/api/tenant/users', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const user = await storage.getUser(req.userId);
      const userTenants = await storage.getUserTenants(req.userId);
      const currentTenant = userTenants.find(ut => ut.tenantId === req.tenant.id);
      
      if (!currentTenant || !['tenant_admin'].includes(currentTenant.role)) {
        return res.status(403).json({ message: "Tenant admin access required" });
      }

      const { email, firstName, lastName, role = 'viewer' } = req.body;

      // Create user
      const newUser = await storage.upsertUser({
        id: randomUUID(),
        email,
        firstName,
        lastName,
        isGlobalUser: false
      });

      // Add to tenant
      const tenantUser = await storage.addUserToTenant({
        tenantId: req.tenant.id,
        userId: newUser.id,
        role: role as any
      });

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.userId,
        action: 'invite',
        resource: 'user',
        resourceId: newUser.id,
        metadata: { userEmail: email, role }
      });

      res.json({ user: newUser, tenantUser });
    } catch (error) {
      console.error("Error creating user:", error);
      res.status(500).json({ message: "Failed to create user" });
    }
  });

  app.put('/api/tenant/users/:userId/role', isAuthenticated, requireTenant, async (req: any, res) => {
    try {
      const user = await storage.getUser(req.userId);
      const userTenants = await storage.getUserTenants(req.userId);
      const currentTenant = userTenants.find(ut => ut.tenantId === req.tenant.id);
      
      if (!currentTenant || !['tenant_admin'].includes(currentTenant.role)) {
        return res.status(403).json({ message: "Tenant admin access required" });
      }

      const { role } = req.body;
      const tenantUsers = await storage.getTenantUsers(req.tenant.id);
      const targetUser = tenantUsers.find(tu => tu.userId === req.params.userId);

      if (!targetUser) {
        return res.status(404).json({ message: "User not found in tenant" });
      }

      await storage.updateTenantUserRole(targetUser.id, role);

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.userId,
        action: 'update_role',
        resource: 'user',
        resourceId: req.params.userId,
        metadata: { oldRole: targetUser.role, newRole: role }
      });

      res.json({ message: "Role updated successfully" });
    } catch (error) {
      console.error("Error updating user role:", error);
      res.status(500).json({ message: "Failed to update role" });
    }
  });

  // Object Storage routes for logos
  app.get("/public-objects/:filePath(*)", async (req, res) => {
    const filePath = req.params.filePath;
    const objectStorageService = new ObjectStorageService();
    try {
      const file = await objectStorageService.searchPublicObject(filePath);
      if (!file) {
        return res.status(404).json({ error: "File not found" });
      }
      objectStorageService.downloadObject(file, res);
    } catch (error) {
      console.error("Error searching for public object:", error);
      return res.status(500).json({ error: "Internal server error" });
    }
  });

  app.get("/objects/:objectPath(*)", isAuthenticated, async (req, res) => {
    const objectStorageService = new ObjectStorageService();
    try {
      const objectFile = await objectStorageService.getObjectEntityFile(
        req.path,
      );
      objectStorageService.downloadObject(objectFile, res);
    } catch (error) {
      console.error("Error accessing object:", error);
      if (error instanceof ObjectNotFoundError) {
        return res.sendStatus(404);
      }
      return res.sendStatus(500);
    }
  });

  app.post("/api/objects/upload", isAuthenticated, async (req, res) => {
    const objectStorageService = new ObjectStorageService();
    const uploadURL = await objectStorageService.getObjectEntityUploadURL();
    res.json({ uploadURL });
  });

  app.put("/api/tenant/logo", isAuthenticated, requireTenant, async (req: any, res) => {
    if (!req.body.logoURL) {
      return res.status(400).json({ error: "logoURL is required" });
    }

    try {
      const objectStorageService = new ObjectStorageService();
      const objectPath = objectStorageService.normalizeObjectEntityPath(
        req.body.logoURL,
      );

      // Update tenant with logo path
      await storage.updateTenant(req.tenant.id, { logoUrl: objectPath });

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.userId,
        action: 'update',
        resource: 'tenant',
        resourceId: req.tenant.id,
        metadata: { action: 'logo_update' }
      });

      res.status(200).json({
        objectPath: objectPath,
      });
    } catch (error) {
      console.error("Error setting tenant logo:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // Add example data endpoint
  app.post("/api/admin/seed-example-data", isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const user = await storage.getUser(userId);
      
      if (!user?.globalRole || user.globalRole !== 'global_admin') {
        return res.status(403).json({ message: "Access denied" });
      }

      const { tenantId } = req.body;
      if (!tenantId) {
        return res.status(400).json({ message: "Tenant ID required" });
      }

      // Create example collectors directly here
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

      // Add telemetry for online collector
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
          { name: "samureye-agent", cpu: 2.1, memory: 128 }
        ]
      });

      res.json({
        message: "Example data created successfully",
        collectors: [collector1, collector2]
      });
    } catch (error) {
      console.error("Error creating example data:", error);
      res.status(500).json({ message: "Failed to create example data" });
    }
  });

  const httpServer = createServer(app);

  // WebSocket setup for real-time updates
  const wss = new WebSocketServer({ server: httpServer, path: '/ws' });
  
  wss.on('connection', (ws) => {
    console.log('WebSocket client connected');
    
    ws.on('close', () => {
      console.log('WebSocket client disconnected');
    });
  });

  // Broadcast telemetry updates to connected clients
  setInterval(async () => {
    if (wss.clients.size === 0) return;

    try {
      // This would be more sophisticated in a real implementation
      const message = JSON.stringify({
        type: 'telemetry_update',
        timestamp: new Date().toISOString()
      });

      wss.clients.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(message);
        }
      });
    } catch (error) {
      console.error('Error broadcasting telemetry:', error);
    }
  }, 10000); // Every 10 seconds

  return httpServer;
}
