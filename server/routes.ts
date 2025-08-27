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
import session from "express-session";
import createMemoryStore from "memorystore";

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

// Local credential storage with basic encryption

// Removed Delinea integration - credentials now stored locally with encryption

export async function registerRoutes(app: Express): Promise<Server> {
  // Create memory store for session
  const MemoryStore = createMemoryStore(session);
  
  // Session middleware
  app.use(session({
    secret: 'samureye-dev-secret-2024',
    resave: false,
    saveUninitialized: false,
    cookie: { 
      secure: false, // Set to true in production with HTTPS
      httpOnly: true,
      maxAge: 24 * 60 * 60 * 1000, // 24 hours
      sameSite: 'lax'
    },
    store: new MemoryStore({
      checkPeriod: 86400000 // prune expired entries every 24h
    })
  }));

  // Auth middleware (for Replit Auth - disabled for now to avoid conflicts)
  // await setupAuth(app);

  // Admin authentication routes
  app.post('/api/admin/login', async (req, res) => {
    try {
      const { email, password } = req.body;
      
      // Simple admin login - in production, use proper password hashing
      if (email === 'admin@samureye.com.br' && password === 'SamurEye2024!') {
        // Clear any regular user session
        delete (req.session as any).userId;
        delete (req.session as any).userEmail;
        
        // Set admin session
        (req.session as any).adminUser = { email, isAdmin: true };
        res.json({ success: true, message: 'Login realizado com sucesso' });
      } else {
        res.status(401).json({ message: 'Credenciais inválidas' });
      }
    } catch (error) {
      console.error('Admin login error:', error);
      res.status(500).json({ message: 'Erro interno do servidor' });
    }
  });

  app.post('/api/admin/logout', async (req, res) => {
    try {
      delete (req.session as any).adminUser;
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ message: 'Erro no logout' });
    }
  });

  // Check admin authentication status
  app.get('/api/admin/me', async (req, res) => {
    try {
      const adminUser = (req.session as any)?.adminUser;
      if (adminUser?.isAdmin) {
        res.json({ 
          isAuthenticated: true, 
          email: adminUser.email,
          isAdmin: true 
        });
      } else {
        res.status(401).json({ 
          isAuthenticated: false, 
          message: 'Not authenticated' 
        });
      }
    } catch (error) {
      res.status(500).json({ message: 'Erro na verificação de autenticação' });
    }
  });

  // Admin middleware
  const isAdmin = (req: any, res: any, next: any) => {
    if (!(req.session as any)?.adminUser?.isAdmin) {
      return res.status(401).json({ message: 'Acesso negado - Admin apenas' });
    }
    next();
  };

  // Admin routes
  app.get('/api/admin/tenants', isAdmin, async (req, res) => {
    try {
      const tenants = await storage.getAllTenants();
      res.json(tenants);
    } catch (error) {
      console.error("Error fetching admin tenants:", error);
      res.status(500).json({ message: "Failed to fetch tenants" });
    }
  });

  app.post('/api/admin/tenants', isAdmin, async (req, res) => {
    try {
      const tenant = await storage.createTenant(req.body);
      res.json(tenant);
    } catch (error) {
      console.error("Error creating tenant:", error);
      res.status(500).json({ message: "Failed to create tenant" });
    }
  });

  app.delete('/api/admin/tenants/:id', isAdmin, async (req, res) => {
    try {
      await storage.deleteTenant(req.params.id);
      res.json({ success: true });
    } catch (error) {
      console.error("Error deleting tenant:", error);
      res.status(500).json({ message: "Failed to delete tenant" });
    }
  });

  // Admin Settings routes
  app.get('/api/admin/settings', isAdmin, async (req, res) => {
    try {
      // Get or create system settings
      let settings = await storage.getSystemSettings();
      if (!settings) {
        settings = await storage.createSystemSettings({
          systemName: 'SamurEye',
          systemDescription: 'Plataforma de Simulação de Ataques e Análise de Segurança',
          supportEmail: 'suporte@samureye.com.br',
          logoUrl: null
        });
      }
      res.json(settings);
    } catch (error) {
      console.error("Error fetching admin settings:", error);
      res.status(500).json({ message: "Failed to fetch settings" });
    }
  });

  app.put('/api/admin/settings', isAdmin, async (req, res) => {
    try {
      const { systemName, systemDescription, supportEmail, logoUrl } = req.body;
      
      const settings = await storage.updateSystemSettings({
        systemName,
        systemDescription, 
        supportEmail,
        logoUrl
      });
      
      res.json(settings);
    } catch (error) {
      console.error("Error updating admin settings:", error);
      res.status(500).json({ message: "Failed to update settings" });
    }
  });

  // Admin User Edit routes
  app.get('/api/admin/users/:id', isAdmin, async (req, res) => {
    try {
      const user = await storage.getUserById(req.params.id);
      if (!user) {
        return res.status(404).json({ message: "User not found" });
      }

      const userTenants = await storage.getUserTenants(user.id);
      const userWithTenants = {
        ...user,
        tenants: userTenants
      };

      res.json(userWithTenants);
    } catch (error) {
      console.error("Error fetching user:", error);
      res.status(500).json({ message: "Failed to fetch user" });
    }
  });

  app.put('/api/admin/users/:id', isAdmin, async (req, res) => {
    try {
      const { firstName, lastName, email, isSocUser, isActive, password, tenants } = req.body;
      const userId = req.params.id;

      // Update user basic info
      const updateData: any = {
        firstName,
        lastName,
        email,
        isSocUser,
        isActive
      };

      if (password && password.trim()) {
        updateData.password = password;
      }

      const updatedUser = await storage.updateUser(userId, updateData);

      // Update tenant associations
      if (tenants) {
        // Remove all current associations
        await storage.removeAllUserTenants(userId);
        
        // Add new associations
        for (const tenantAssoc of tenants) {
          await storage.addUserToTenant(userId, tenantAssoc.tenantId, tenantAssoc.role);
        }
      }

      res.json(updatedUser);
    } catch (error) {
      console.error("Error updating user:", error);
      res.status(500).json({ message: "Failed to update user" });
    }
  });

  // Admin tenant edit routes
  app.get('/api/admin/tenants/:id', isAdmin, async (req, res) => {
    try {
      const tenant = await storage.getTenant(req.params.id);
      if (!tenant) {
        return res.status(404).json({ message: "Tenant not found" });
      }
      res.json(tenant);
    } catch (error) {
      console.error("Error fetching tenant:", error);
      res.status(500).json({ message: "Failed to fetch tenant" });
    }
  });

  app.put('/api/admin/tenants/:id', isAdmin, async (req, res) => {
    try {
      const { name, slug, description, logoUrl, isActive } = req.body;
      const tenantId = req.params.id;

      await storage.updateTenant(tenantId, {
        name,
        slug,
        description,
        logoUrl,
        isActive
      });

      const updatedTenant = await storage.getTenant(tenantId);
      res.json(updatedTenant);
    } catch (error) {
      console.error("Error updating tenant:", error);
      res.status(500).json({ message: "Failed to update tenant" });
    }
  });

  // Object storage upload route (for admin uploads)
  app.post('/api/objects/upload', isAdmin, async (req, res) => {
    try {
      const objectStorageService = new ObjectStorageService();
      const uploadURL = await objectStorageService.getObjectEntityUploadURL();
      res.json({ uploadURL });
    } catch (error) {
      console.error("Error getting upload URL:", error);
      res.status(500).json({ message: "Failed to get upload URL" });
    }
  });

  // Serve objects from storage (for logo display)
  app.get('/objects/:objectPath(*)', async (req, res) => {
    try {
      const objectStorageService = new ObjectStorageService();
      const objectFile = await objectStorageService.getObjectEntityFile(req.path);
      objectStorageService.downloadObject(objectFile, res);
    } catch (error) {
      console.error("Error serving object:", error);
      if (error instanceof ObjectNotFoundError) {
        return res.sendStatus(404);
      }
      return res.sendStatus(500);
    }
  });

  // Public route to get system settings (without admin requirement)
  app.get('/api/system/settings', async (req, res) => {
    try {
      const settings = await storage.getSystemSettings();
      if (!settings) {
        return res.json({
          systemName: 'SamurEye',
          systemDescription: 'Plataforma de Simulação de Ataques e Análise de Segurança',
          logoUrl: null
        });
      }
      // Only return public settings fields
      res.json({
        systemName: settings.systemName,
        systemDescription: settings.systemDescription,
        logoUrl: settings.logoUrl
      });
    } catch (error) {
      console.error("Error fetching system settings:", error);
      res.status(500).json({ message: "Failed to fetch system settings" });
    }
  });

  app.get('/api/admin/stats', isAdmin, async (req, res) => {
    try {
      const stats = await storage.getAdminStats();
      res.json(stats);
    } catch (error) {
      console.error("Error fetching admin stats:", error);
      res.status(500).json({ message: "Failed to fetch stats" });
    }
  });

  app.post('/api/admin/users', isAdmin, async (req, res) => {
    try {
      const user = await storage.createAdminUser(req.body);
      res.json(user);
    } catch (error: any) {
      console.error("Error creating user:", error);
      
      // Handle specific errors with user-friendly messages
      if (error.message.includes('já existe')) {
        return res.status(400).json({ message: error.message });
      }
      
      res.status(500).json({ message: "Erro ao criar usuário" });
    }
  });

  // Admin endpoint to list all users
  app.get('/api/admin/users', isAdmin, async (req, res) => {
    try {
      const users = await storage.getAllUsers();
      res.json(users);
    } catch (error) {
      console.error("Error fetching users:", error);
      res.status(500).json({ message: "Failed to fetch users" });
    }
  });

  // Admin endpoint to delete user
  app.delete('/api/admin/users/:userId', isAdmin, async (req, res) => {
    try {
      await storage.deleteUser(req.params.userId);
      res.json({ success: true });
    } catch (error) {
      console.error("Error deleting user:", error);
      res.status(500).json({ message: "Failed to delete user" });
    }
  });

  // User login endpoint (for regular users created in the system)
  app.post('/api/login', async (req, res) => {
    try {
      const { email, password } = req.body;
      
      if (!email || !password) {
        return res.status(400).json({ message: "Email e senha são obrigatórios" });
      }

      const user = await storage.authenticateUser(email, password);
      if (!user) {
        return res.status(401).json({ message: "Credenciais inválidas" });
      }

      if (!user.isActive) {
        return res.status(401).json({ message: "Usuário inativo" });
      }

      // Clear any admin session
      delete (req.session as any).adminUser;
      
      // Create user session  
      (req.session as any).userId = user.id;
      (req.session as any).userEmail = user.email;
      
      // Force session save
      await new Promise<void>((resolve, reject) => {
        req.session.save((err: any) => {
          if (err) {
            console.error('Session save error:', err);
            reject(err);
          } else {
            resolve();
          }
        });
      });
      
      // Update last login
      await storage.updateLastLogin(user.id);
      
      res.json({
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        isSocUser: user.isSocUser,
      });
    } catch (error) {
      console.error("Error during login:", error);
      res.status(500).json({ message: "Erro interno do servidor" });
    }
  });

  // User logout endpoint
  app.post('/api/logout', async (req, res) => {
    try {
      req.session.destroy((err) => {
        if (err) {
          console.error("Error destroying session:", err);
          return res.status(500).json({ message: "Erro ao fazer logout" });
        }
        res.json({ success: true });
      });
    } catch (error) {
      console.error("Error during logout:", error);
      res.status(500).json({ message: "Erro interno do servidor" });
    }
  });

  // Get current user endpoint (for session-based auth) with tenant information
  app.get('/api/user', async (req, res) => {
    try {
      const userId = (req.session as any)?.userId;
      
      if (!userId) {
        return res.status(401).json({ message: "Não autenticado" });
      }

      const user = await storage.getUserById(userId);
      if (!user || !user.isActive) {
        return res.status(401).json({ message: "Usuário não encontrado ou inativo" });
      }

      // Get user tenants and current tenant info
      let tenants: any[] = [];
      let currentTenant = null;

      if (user.isSocUser) {
        // SOC users have access to all tenants
        const allTenants = await storage.getAllTenants();
        tenants = allTenants.map(t => ({
          tenantId: t.id,
          role: 'soc_operator',
          tenant: t
        }));
        // For SOC users, use currentTenantId if set, otherwise use first tenant
        if (user.currentTenantId) {
          currentTenant = await storage.getTenant(user.currentTenantId);
        } else if (allTenants.length > 0) {
          currentTenant = allTenants[0];
        }
      } else {
        // Regular users - get their specific tenant associations
        tenants = await storage.getUserTenants(userId);
        if (user.currentTenantId) {
          currentTenant = await storage.getTenant(user.currentTenantId);
        } else if (tenants.length > 0) {
          // Use first available tenant if no current tenant set
          const firstTenant = tenants[0];
          currentTenant = await storage.getTenant(firstTenant.tenantId);
        }
      }

      res.json({
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        isSocUser: user.isSocUser,
        tenants,
        currentTenant
      });
    } catch (error) {
      console.error("Error getting user:", error);
      res.status(500).json({ message: "Erro interno do servidor" });
    }
  });

  // Local user middleware (for session-based authentication)
  const isLocalUserAuthenticated = async (req: any, res: any, next: any) => {
    try {
      const userId = (req.session as any)?.userId;
      
      if (!userId) {
        return res.status(401).json({ message: "Unauthorized" });
      }

      const user = await storage.getUserById(userId);
      if (!user || !user.isActive) {
        return res.status(401).json({ message: "Unauthorized" });
      }

      req.userId = userId;
      req.localUser = user;
      req.user = user; // Para compatibilidade com outros endpoints
      next();
    } catch (error) {
      console.error("Authentication error:", error);
      res.status(500).json({ message: "Authentication error" });
    }
  };

  // Tenant middleware for local users
  const requireLocalUserTenant = async (req: any, res: any, next: any) => {
    try {
      const user = req.localUser;
      
      if (user.isSocUser) {
        // SOC users can access all tenants - use currentTenantId if set
        let tenantId = user.currentTenantId;
        if (!tenantId) {
          // If no current tenant set, use first available
          const tenants = await storage.getAllTenants();
          if (tenants.length > 0) {
            tenantId = tenants[0].id;
          } else {
            return res.status(400).json({ message: "No tenants available" });
          }
        }
        
        const tenant = await storage.getTenant(tenantId);
        if (!tenant) {
          return res.status(404).json({ message: "Tenant not found" });
        }
        
        req.tenant = tenant;
      } else {
        // Regular users need tenant association
        const userTenants = await storage.getUserTenants(user.id);
        if (userTenants.length === 0) {
          return res.status(403).json({ message: "No tenant access" });
        }
        
        // Use current tenant or first available
        let tenantId = user.currentTenantId;
        if (!tenantId || !userTenants.find(ut => ut.tenantId === tenantId)) {
          tenantId = userTenants[0].tenantId;
        }
        
        const tenant = await storage.getTenant(tenantId);
        if (!tenant) {
          return res.status(404).json({ message: "Tenant not found" });
        }
        
        req.tenant = tenant;
        req.userTenantRole = userTenants.find(ut => ut.tenantId === tenantId)?.role;
      }
      
      next();
    } catch (error) {
      console.error("Tenant middleware error:", error);
      res.status(500).json({ message: "Tenant access error" });
    }
  };

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

  app.post('/api/switch-tenant', isLocalUserAuthenticated, async (req: any, res) => {
    try {
      const userId = req.localUser.id;
      const { tenantId } = req.body;

      // Get user to check if they are SOC user
      const user = await storage.getUserById(userId);
      if (!user) {
        return res.status(404).json({ message: "User not found" });
      }

      let hasAccess = false;

      if (user.isSocUser) {
        // SOC users have access to all tenants - just verify tenant exists
        const tenant = await storage.getTenant(tenantId);
        hasAccess = !!tenant;
      } else {
        // Regular users - check their specific tenant associations
        const userTenants = await storage.getUserTenants(userId);
        hasAccess = userTenants.some(ut => ut.tenantId === tenantId);
      }
      
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
  app.get('/api/collectors', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      const collectors = await storage.getCollectorsByTenant(req.tenant.id);
      res.json(collectors);
    } catch (error) {
      console.error("Error fetching collectors:", error);
      res.status(500).json({ message: "Failed to fetch collectors" });
    }
  });

  app.post('/api/collectors', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
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

  app.post('/api/collectors/:id/regenerate-token', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
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
  app.get('/api/journeys', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      const journeys = await storage.getJourneysByTenant(req.tenant.id);
      res.json(journeys);
    } catch (error) {
      console.error("Error fetching journeys:", error);
      res.status(500).json({ message: "Failed to fetch journeys" });
    }
  });

  app.post('/api/journeys', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      const journey = await storage.createJourney({
        ...req.body,
        tenantId: req.tenant.id,
        createdBy: req.localUser.id
      });

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.localUser.id,
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

  app.post('/api/journeys/:id/start', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      const journey = await storage.getJourney(req.params.id);
      if (!journey || journey.tenantId !== req.tenant.id) {
        return res.status(404).json({ message: "Journey not found" });
      }

      await storage.updateJourneyStatus(journey.id, 'running');

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.localUser.id,
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
  app.get('/api/credentials', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      const credentials = await storage.getCredentialsByTenant(req.tenant.id);
      res.json(credentials);
    } catch (error) {
      console.error("Error fetching credentials:", error);
      res.status(500).json({ message: "Failed to fetch credentials" });
    }
  });

  app.post('/api/credentials', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      // Store credential with local data
      const credential = await storage.createCredential({
        ...req.body,
        tenantId: req.tenant.id,
        createdBy: req.localUser.id
      });

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.localUser.id,
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

  app.put('/api/credentials/:id', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      const validatedData = insertCredentialSchema.parse({
        ...req.body,
        tenantId: req.tenant.id,
        createdBy: req.localUser.id
      });

      const credential = await storage.updateCredential(req.params.id, validatedData);

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.localUser.id,
        action: 'update',
        resource: 'credential',
        resourceId: credential.id,
        metadata: { credentialName: credential.name, credentialType: credential.type }
      });

      res.json(credential);
    } catch (error) {
      console.error("Error updating credential:", error);
      res.status(500).json({ message: "Failed to update credential" });
    }
  });

  app.delete('/api/credentials/:id', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      await storage.deleteCredential(req.params.id);

      // Log activity
      await storage.createActivity({
        tenantId: req.tenant.id,
        userId: req.localUser.id,
        action: 'delete',
        resource: 'credential',
        resourceId: req.params.id,
        metadata: {}
      });

      res.json({ message: 'Credential deleted successfully' });
    } catch (error) {
      console.error("Error deleting credential:", error);
      res.status(500).json({ message: "Failed to delete credential" });
    }
  });

  // Journey Results Dashboard data
  app.get('/api/dashboard/journey-results', isLocalUserAuthenticated, async (req: any, res) => {
    try {
      if (!req.user) {
        return res.status(401).json({ message: "User not authenticated" });
      }

      const tenantId = req.user.currentTenantId;
      if (!tenantId) {
        return res.status(400).json({ message: "No active tenant selected" });
      }

      const tenant = await storage.getTenant(tenantId);
      if (!tenant) {
        return res.status(404).json({ message: "Tenant not found" });
      }

      const collectors = await storage.getCollectorsByTenant(tenantId);
      const journeys = await storage.getJourneysByTenant(tenantId);
      const threatIntel = await storage.getThreatIntelligenceByTenant(tenantId);
      
      // Tenant-specific journey results
      const journeyData = tenant.name === 'PoC' ? [
        {
          id: 'attack-surface',
          title: 'Superfície de Ataque',
          icon: 'Globe',
          iconColor: 'text-blue-500',
          iconBg: 'bg-blue-500/20',
          lastExecution: '4h atrás',
          status: 'success',
          results: {
            hostsScanned: 127,
            servicesExposed: 423,
            criticalCves: threatIntel.filter(t => t.severity === 'critical').length || 3,
            internetFacing: 18
          },
          scanType: 'Escaneamento PoC via collector'
        },
        {
          id: 'ad-hygiene',
          title: 'Higiene AD/LDAP',
          icon: 'Users',
          iconColor: 'text-blue-400',
          iconBg: 'bg-blue-400/20',
          lastExecution: '8h atrás',
          status: 'warning',
          results: {
            inactiveAccounts: 23,
            orphanAdmins: 2,
            weakPolicies: 5,
            slaExpiring: 3
          },
          scanType: 'Análise de ambiente PoC'
        },
        {
          id: 'edr-testing',
          title: 'Testes EDR/AV',
          icon: 'Shield',
          iconColor: 'text-green-500',
          iconBg: 'bg-green-500/20',
          lastExecution: '1h atrás',
          status: 'success',
          results: {
            detectionRate: '78.3%',
            blockRate: '71.2%',
            avgLatency: '2.1s',
            detectionFailures: 8
          },
          scanType: 'Testando 5 endpoints PoC'
        }
      ] : [
        {
          id: 'attack-surface',
          title: 'Superfície de Ataque',
          icon: 'Globe',
          iconColor: 'text-blue-500',
          iconBg: 'bg-blue-500/20',
          lastExecution: '2h atrás',
          status: 'success',
          results: {
            hostsScanned: 847,
            servicesExposed: 2341,
            criticalCves: threatIntel.filter(t => t.severity === 'critical').length || 23,
            internetFacing: 127
          },
          scanType: 'Escaneamento interno via collector'
        },
        {
          id: 'ad-hygiene',
          title: 'Higiene AD/LDAP',
          icon: 'Users',
          iconColor: 'text-blue-400',
          iconBg: 'bg-blue-400/20',
          lastExecution: '6h atrás',
          status: 'warning',
          results: {
            inactiveAccounts: 142,
            orphanAdmins: 7,
            weakPolicies: 28,
            slaExpiring: 15
          },
          scanType: 'Análise contínua de domínio'
        },
        {
          id: 'edr-testing',
          title: 'Testes EDR/AV',
          icon: 'Shield',
          iconColor: 'text-green-500',
          iconBg: 'bg-green-500/20',
          lastExecution: '30min atrás',
          status: 'success',
          results: {
            detectionRate: '94.2%',
            blockRate: '87.8%',
            avgLatency: '1.2s',
            detectionFailures: 4
          },
          scanType: 'Testando 23 endpoints ativos'
        }
      ];

      res.json(journeyData);
    } catch (error) {
      console.error("Error fetching journey results:", error);
      res.status(500).json({ message: "Failed to fetch journey results" });
    }
  });

  // Threat Intelligence routes
  app.get('/api/threat-intelligence', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      const intelligence = await storage.getThreatIntelligenceByTenant(req.tenant.id);
      res.json(intelligence);
    } catch (error) {
      console.error("Error fetching threat intelligence:", error);
      res.status(500).json({ message: "Failed to fetch threat intelligence" });
    }
  });

  // Activity routes
  app.get('/api/activities', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
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
  app.get('/api/dashboard/metrics', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      const collectors = await storage.getCollectorsByTenant(req.tenant.id);
      const journeys = await storage.getJourneysByTenant(req.tenant.id);
      const threatIntel = await storage.getThreatIntelligenceByTenant(req.tenant.id);

      const onlineCollectors = collectors.filter(c => c.status === 'online').length;
      const totalCollectors = collectors.length;
      const activeJourneys = journeys.filter(j => j.status === 'running').length;
      const criticalThreats = threatIntel.filter(t => t.severity === 'critical').length;

      // Tenant-specific metrics based on actual data
      const baseMetrics = req.tenant.name === 'PoC' ? {
        assets: { total: 425 },
        edr: { detectionRate: 87.5, blockRate: 78.3, avgLatency: 2.1 }
      } : {
        assets: { total: 1247 },
        edr: { detectionRate: 94.2, blockRate: 87.8, avgLatency: 1.2 }
      };

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
        ...baseMetrics
      };

      res.json(metrics);
    } catch (error) {
      console.error("Error fetching dashboard metrics:", error);
      res.status(500).json({ message: "Failed to fetch dashboard metrics" });
    }
  });

  // Attack Surface Heatmap data
  app.get('/api/dashboard/attack-surface', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      // Tenant-specific attack surface data
      const heatmapData = req.tenant.name === 'PoC' ? [
        { severity: 'medium', service: 'SSH', port: '22/TCP', count: 3, tooltip: 'SSH - 22/TCP: 3 vulnerabilidades médias' },
        { severity: 'low', service: 'HTTP', port: '80/TCP', count: 2, tooltip: 'HTTP - 80/TCP: 2 vulnerabilidades baixas' },
        { severity: 'high', service: 'RDP', port: '3389/TCP', count: 1, tooltip: 'RDP - 3389/TCP: 1 vulnerabilidade alta' },
        { severity: 'none', service: 'HTTPS', port: '443/TCP', count: 0, tooltip: 'HTTPS - 443/TCP: Seguro' },
      ] : [
        { severity: 'critical', service: 'SSH', port: '22/TCP', count: 15, tooltip: 'SSH - 22/TCP: 15 vulnerabilidades críticas' },
        { severity: 'high', service: 'HTTP', port: '80/TCP', count: 8, tooltip: 'HTTP - 80/TCP: 8 vulnerabilidades altas' },
        { severity: 'low', service: 'DNS', port: '53/UDP', count: 2, tooltip: 'DNS - 53/UDP: 2 vulnerabilidades baixas' },
        { severity: 'critical', service: 'RDP', port: '3389/TCP', count: 22, tooltip: 'RDP - 3389/TCP: 22 vulnerabilidades críticas' },
        { severity: 'medium', service: 'HTTPS', port: '443/TCP', count: 5, tooltip: 'HTTPS - 443/TCP: 5 vulnerabilidades médias' },
        { severity: 'low', service: 'FTP', port: '21/TCP', count: 1, tooltip: 'FTP - 21/TCP: 1 vulnerabilidade baixa' },
        { severity: 'none', service: 'Unknown', port: 'N/A', count: 0, tooltip: 'Sem dados' },
        { severity: 'info', service: 'SMTP', port: '25/TCP', count: 0, tooltip: 'SMTP - 25/TCP: Informativo' },
      ];

      res.json(heatmapData);
    } catch (error) {
      console.error("Error fetching attack surface:", error);
      res.status(500).json({ message: "Failed to fetch attack surface" });
    }
  });

  // EDR Timeline data
  app.get('/api/dashboard/edr-events', isLocalUserAuthenticated, requireLocalUserTenant, async (req: any, res) => {
    try {
      // Tenant-specific EDR events
      const edrEvents = req.tenant.name === 'PoC' ? [
        {
          id: '1',
          type: 'detected',
          title: 'Suspicious Activity',
          endpoint: 'PoC-Test-01',
          process: 'powershell.exe',
          latency: '2.8s',
          timestamp: '14:45:22'
        },
        {
          id: '2',
          type: 'blocked',
          title: 'Malware Detected',
          endpoint: 'PoC-Demo-01',
          process: 'suspicious.exe',
          latency: '1.9s',
          timestamp: '14:22:15'
        }
      ] : [
        {
          id: '1',
          type: 'blocked',
          title: 'Malware Detected',
          endpoint: 'Enterprise-DC-01',
          process: 'suspicious.exe',
          latency: '125ms',
          timestamp: '14:32:15'
        },
        {
          id: '2',
          type: 'detected',
          title: 'Suspicious Activity',
          endpoint: 'Enterprise-Branch-SP',
          process: 'powershell.exe',
          latency: '2.3s',
          timestamp: '14:28:42'
        },
        {
          id: '3',
          type: 'failed',
          title: 'Detection Failed',
          endpoint: 'Enterprise-Branch-RJ',
          process: 'mimikatz.exe',
          latency: 'Timeout',
          timestamp: '14:25:18'
        }
      ];

      res.json(edrEvents);
    } catch (error) {
      console.error("Error fetching EDR events:", error);
      res.status(500).json({ message: "Failed to fetch EDR events" });
    }
  });

  // Global Admin Routes (for system management)
  app.get('/api/admin/tenants', isAuthenticated, async (req: any, res) => {
    try {
      const user = await storage.getUser(req.user.claims.sub);
      if (!user?.globalRole || !['global_admin', 'global_auditor'].includes(user.globalRole)) {
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
      console.log("Creating tenant request body:", req.body);
      const user = await storage.getUser(req.user.claims.sub);
      console.log("User permission check:", user?.globalRole);
      
      if (!user?.globalRole || !['global_admin', 'global_auditor'].includes(user.globalRole)) {
        return res.status(403).json({ message: "Global admin access required" });
      }

      const validatedData = insertTenantSchema.parse(req.body);
      console.log("Validated data:", validatedData);
      
      const tenant = await storage.createTenant(validatedData);
      console.log("Created tenant:", tenant);

      // Log activity
      try {
        await storage.createActivity({
          userId: req.user.claims.sub,
          action: 'create',
          resource: 'tenant',
          resourceId: tenant.id,
          metadata: { tenantName: tenant.name }
        });
      } catch (activityError) {
        console.warn("Failed to log activity:", activityError);
        // Don't fail the request if activity logging fails
      }

      res.json(tenant);
    } catch (error) {
      console.error("Error creating tenant:", error);
      if (error instanceof Error) {
        console.error("Error details:", error.message, error.stack);
      }
      res.status(500).json({ 
        message: "Failed to create tenant", 
        error: error instanceof Error ? error.message : "Unknown error"
      });
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
      const tenantUser = await storage.addUserToTenant(newUser.id, req.tenant.id, role);

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
      
      if (!user?.globalRole || !['global_admin', 'global_auditor'].includes(user.globalRole)) {
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

  // Development route to seed different tenant data
  app.post('/api/dev/seed-tenant-data', async (req, res) => {
    try {
      const { seedDifferentTenantData } = await import('./seedSimpleData');
      await seedDifferentTenantData();
      res.json({ success: true, message: 'Tenant data seeded successfully' });
    } catch (error) {
      console.error('Error seeding tenant data:', error);
      res.status(500).json({ error: 'Failed to seed tenant data' });
    }
  });

  return httpServer;
}
