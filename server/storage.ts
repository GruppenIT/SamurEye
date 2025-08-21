import {
  users,
  tenants,
  tenantUsers,
  collectors,
  collectorTelemetry,
  journeys,
  credentials,
  threatIntelligence,
  activities,
  systemSettings,
  tenantUserAuth,
  type User,
  type UpsertUser,
  type Tenant,
  type InsertTenant,
  type TenantUser,
  type InsertTenantUser,
  type Collector,
  type InsertCollector,
  type CollectorTelemetry,
  type InsertCollectorTelemetry,
  type Journey,
  type InsertJourney,
  type Credential,
  type InsertCredential,
  type ThreatIntelligence,
  type InsertThreatIntelligence,
  type Activity,
  type InsertActivity,
  type SystemSettings,
  type InsertSystemSettings,
  type TenantUserAuth,
  type InsertTenantUserAuth,
} from "@shared/schema";
import { db } from "./db";
import { eq, and, desc, gte, isNotNull, sql } from "drizzle-orm";
import { randomUUID } from "crypto";

export interface IStorage {
  // User operations (mandatory for Replit Auth)
  getUser(id: string): Promise<User | undefined>;
  upsertUser(user: UpsertUser): Promise<User>;

  // Tenant operations
  getTenant(id: string): Promise<Tenant | undefined>;
  getAllTenants(): Promise<Tenant[]>;
  getUserTenants(userId: string): Promise<(TenantUser & { tenant: Tenant })[]>;
  createTenant(tenant: InsertTenant): Promise<Tenant>;
  updateTenant(id: string, updates: Partial<Tenant>): Promise<void>;
  addUserToTenant(tenantUser: InsertTenantUser): Promise<TenantUser>;
  updateUserCurrentTenant(userId: string, tenantId: string): Promise<void>;
  getTenantUsers(tenantId: string): Promise<(TenantUser & { user: User })[]>;
  updateTenantUserRole(tenantUserId: string, role: string): Promise<void>;
  removeTenantUser(tenantUserId: string): Promise<void>;

  // System settings operations  
  getSystemSetting(key: string): Promise<SystemSettings | undefined>;
  setSystemSetting(key: string, value: string, description?: string): Promise<SystemSettings>;
  getAllSystemSettings(): Promise<SystemSettings[]>;

  // Collector operations
  getCollectorsByTenant(tenantId: string): Promise<Collector[]>;
  getCollector(id: string): Promise<Collector | undefined>;
  createCollector(collector: InsertCollector): Promise<Collector>;
  updateCollectorStatus(id: string, status: string, lastSeen?: Date): Promise<void>;
  generateEnrollmentToken(collectorId: string): Promise<string>;
  getCollectorByEnrollmentToken(token: string): Promise<Collector | undefined>;
  addCollectorTelemetry(telemetry: InsertCollectorTelemetry): Promise<CollectorTelemetry>;
  getLatestCollectorTelemetry(collectorId: string): Promise<CollectorTelemetry | undefined>;

  // Journey operations
  getJourneysByTenant(tenantId: string): Promise<Journey[]>;
  getJourney(id: string): Promise<Journey | undefined>;
  createJourney(journey: InsertJourney): Promise<Journey>;
  updateJourneyStatus(id: string, status: string, results?: any): Promise<void>;

  // Credential operations
  getCredentialsByTenant(tenantId: string): Promise<Credential[]>;
  getCredential(id: string): Promise<Credential | undefined>;
  createCredential(credential: InsertCredential): Promise<Credential>;
  updateCredential(id: string, updates: Partial<Credential>): Promise<Credential>;
  deleteCredential(id: string): Promise<void>;

  // Threat Intelligence operations
  getThreatIntelligenceByTenant(tenantId: string): Promise<ThreatIntelligence[]>;
  createThreatIntelligence(intelligence: InsertThreatIntelligence): Promise<ThreatIntelligence>;

  // Activity operations
  getActivitiesByTenant(tenantId: string, limit?: number): Promise<Activity[]>;
  createActivity(activity: InsertActivity): Promise<Activity>;
}

export class DatabaseStorage implements IStorage {
  // User operations
  async getUser(id: string): Promise<User | undefined> {
    const [user] = await db.select().from(users).where(eq(users.id, id));
    return user;
  }

  async upsertUser(userData: UpsertUser): Promise<User> {
    // Check if user exists  
    if (userData.id) {
      const existingUser = await this.getUser(userData.id);
      
      if (existingUser) {
        // Update existing user
        const [user] = await db
          .update(users)
          .set({
            ...userData,
            updatedAt: new Date(),
          })
          .where(eq(users.id, userData.id))
          .returning();
        return user;
      }
    }
    
    // Create new user with default tenant
    const [user] = await db
      .insert(users)
      .values(userData)
      .returning();
    
    // Create default tenant for new user
    const defaultTenant = await this.createTenant({
      name: `${userData.firstName || userData.email || 'User'}'s Organization`,
      slug: `org-${user.id.slice(0, 8)}`,
      description: 'Default organization'
    });
    
    // Add user to tenant as admin
    await this.addUserToTenant({
      tenantId: defaultTenant.id,
      userId: user.id,
      role: 'tenant_admin'
    });
    
    // Set as current tenant
    await this.updateUserCurrentTenant(user.id, defaultTenant.id);
    
    // Return updated user
    const updatedUser = await this.getUser(user.id);
    return updatedUser!;
  }

  // Tenant operations
  async getTenant(id: string): Promise<Tenant | undefined> {
    const [tenant] = await db.select().from(tenants).where(eq(tenants.id, id));
    return tenant;
  }

  async getUserTenants(userId: string): Promise<(TenantUser & { tenant: Tenant })[]> {
    return await db
      .select({
        id: tenantUsers.id,
        tenantId: tenantUsers.tenantId,
        userId: tenantUsers.userId,
        role: tenantUsers.role,
        isActive: tenantUsers.isActive,
        createdAt: tenantUsers.createdAt,
        tenant: tenants,
      })
      .from(tenantUsers)
      .innerJoin(tenants, eq(tenantUsers.tenantId, tenants.id))
      .where(eq(tenantUsers.userId, userId));
  }

  async createTenant(tenant: InsertTenant): Promise<Tenant> {
    const [newTenant] = await db.insert(tenants).values(tenant).returning();
    return newTenant;
  }

  async addUserToTenant(tenantUser: InsertTenantUser): Promise<TenantUser> {
    const [newTenantUser] = await db.insert(tenantUsers).values(tenantUser).returning();
    return newTenantUser;
  }

  async updateUserCurrentTenant(userId: string, tenantId: string): Promise<void> {
    await db
      .update(users)
      .set({ currentTenantId: tenantId, updatedAt: new Date() })
      .where(eq(users.id, userId));
  }

  async getAllTenants(): Promise<Tenant[]> {
    return await db.select().from(tenants).orderBy(desc(tenants.createdAt));
  }

  // Admin operations  
  async deleteTenant(id: string): Promise<void> {
    await db.delete(tenants).where(eq(tenants.id, id));
  }

  async getAdminStats(): Promise<any> {
    const [totalTenantsResult] = await db.select({ count: sql<number>`count(*)` }).from(tenants);
    const [activeTenantsResult] = await db.select({ count: sql<number>`count(*)` }).from(tenants).where(eq(tenants.isActive, true));
    const [totalUsersResult] = await db.select({ count: sql<number>`count(*)` }).from(users);
    const [socUsersResult] = await db.select({ count: sql<number>`count(*)` }).from(users).where(eq(users.isSocUser, true));

    return {
      totalTenants: totalTenantsResult.count || 0,
      activeTenants: activeTenantsResult.count || 0,
      totalUsers: totalUsersResult.count || 0,
      socUsers: socUsersResult.count || 0
    };
  }

  async createAdminUser(userData: any): Promise<User> {
    // Check if user with email already exists
    const [existingUser] = await db.select().from(users).where(eq(users.email, userData.email));
    if (existingUser) {
      throw new Error(`Usuário com email ${userData.email} já existe`);
    }

    const userId = randomUUID();
    
    const [user] = await db.insert(users).values({
      id: userId,
      email: userData.email,
      firstName: userData.firstName,
      lastName: userData.lastName,
      password: userData.password, // In production, hash this
      isSocUser: userData.isSocUser || false,
      isActive: true,
    }).returning();

    // If not SOC user, create tenant user relationship
    if (!userData.isSocUser && userData.tenantId && userData.role) {
      await db.insert(tenantUsers).values({
        id: randomUUID(),
        tenantId: userData.tenantId,
        userId: user.id,
        role: userData.role,
        isActive: true,
      });
    }

    return user;
  }

  async getAllUsers(): Promise<User[]> {
    return await db.select().from(users).orderBy(desc(users.createdAt));
  }

  async deleteUser(userId: string): Promise<void> {
    // First delete tenant user relationships
    await db.delete(tenantUsers).where(eq(tenantUsers.userId, userId));
    
    // Then delete the user
    await db.delete(users).where(eq(users.id, userId));
  }

  async authenticateUser(email: string, password: string): Promise<User | null> {
    const [user] = await db.select().from(users).where(eq(users.email, email));
    
    if (!user) {
      return null;
    }

    // In production, you should hash passwords and compare hashes
    // For now, comparing plain text (this should be changed for security)
    if (user.password === password) {
      return user;
    }

    return null;
  }

  async getUserById(id: string): Promise<User | undefined> {
    const [user] = await db.select().from(users).where(eq(users.id, id));
    return user;
  }

  async updateLastLogin(userId: string): Promise<void> {
    await db.update(users)
      .set({ lastLoginAt: new Date() })
      .where(eq(users.id, userId));
  }

  async updateTenant(id: string, updates: Partial<Tenant>): Promise<void> {
    await db
      .update(tenants)
      .set({ ...updates, updatedAt: new Date() })
      .where(eq(tenants.id, id));
  }

  async getTenantUsers(tenantId: string): Promise<(TenantUser & { user: User })[]> {
    return await db
      .select({
        id: tenantUsers.id,
        tenantId: tenantUsers.tenantId,
        userId: tenantUsers.userId,
        role: tenantUsers.role,
        isActive: tenantUsers.isActive,
        createdAt: tenantUsers.createdAt,
        user: users,
      })
      .from(tenantUsers)
      .innerJoin(users, eq(tenantUsers.userId, users.id))
      .where(eq(tenantUsers.tenantId, tenantId));
  }

  async updateTenantUserRole(tenantUserId: string, role: string): Promise<void> {
    await db
      .update(tenantUsers)
      .set({ role: role as any })
      .where(eq(tenantUsers.id, tenantUserId));
  }

  async removeTenantUser(tenantUserId: string): Promise<void> {
    await db.delete(tenantUsers).where(eq(tenantUsers.id, tenantUserId));
  }

  // System settings operations
  async getSystemSetting(key: string): Promise<SystemSettings | undefined> {
    const [setting] = await db.select().from(systemSettings).where(eq(systemSettings.key, key));
    return setting;
  }

  async setSystemSetting(key: string, value: string, description?: string): Promise<SystemSettings> {
    const [setting] = await db
      .insert(systemSettings)
      .values({ key, value, description })
      .onConflictDoUpdate({
        target: systemSettings.key,
        set: { value, description, updatedAt: new Date() },
      })
      .returning();
    return setting;
  }

  async getAllSystemSettings(): Promise<SystemSettings[]> {
    return await db.select().from(systemSettings);
  }

  // Collector operations
  async getCollectorsByTenant(tenantId: string): Promise<Collector[]> {
    return await db.select().from(collectors).where(eq(collectors.tenantId, tenantId));
  }

  async getCollector(id: string): Promise<Collector | undefined> {
    const [collector] = await db.select().from(collectors).where(eq(collectors.id, id));
    return collector;
  }

  async createCollector(collector: InsertCollector): Promise<Collector> {
    const [newCollector] = await db.insert(collectors).values(collector).returning();
    return newCollector;
  }

  async updateCollectorStatus(id: string, status: string, lastSeen?: Date): Promise<void> {
    await db
      .update(collectors)
      .set({ 
        status: status as any, 
        lastSeen: lastSeen || new Date(), 
        updatedAt: new Date() 
      })
      .where(eq(collectors.id, id));
  }

  async generateEnrollmentToken(collectorId: string): Promise<string> {
    const token = randomUUID();
    const expires = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes

    await db
      .update(collectors)
      .set({ 
        enrollmentToken: token, 
        enrollmentTokenExpires: expires,
        status: 'enrolling',
        updatedAt: new Date() 
      })
      .where(eq(collectors.id, collectorId));

    return token;
  }

  async getCollectorByEnrollmentToken(token: string): Promise<Collector | undefined> {
    const [collector] = await db
      .select()
      .from(collectors)
      .where(
        and(
          eq(collectors.enrollmentToken, token),
          gte(collectors.enrollmentTokenExpires, new Date())
        )
      );
    return collector;
  }

  async addCollectorTelemetry(telemetry: InsertCollectorTelemetry): Promise<CollectorTelemetry> {
    const [newTelemetry] = await db.insert(collectorTelemetry).values(telemetry).returning();
    return newTelemetry;
  }

  async getLatestCollectorTelemetry(collectorId: string): Promise<CollectorTelemetry | undefined> {
    const [telemetry] = await db
      .select()
      .from(collectorTelemetry)
      .where(eq(collectorTelemetry.collectorId, collectorId))
      .orderBy(desc(collectorTelemetry.timestamp))
      .limit(1);
    return telemetry;
  }

  // Journey operations
  async getJourneysByTenant(tenantId: string): Promise<Journey[]> {
    return await db
      .select()
      .from(journeys)
      .where(eq(journeys.tenantId, tenantId))
      .orderBy(desc(journeys.createdAt));
  }

  async getJourney(id: string): Promise<Journey | undefined> {
    const [journey] = await db.select().from(journeys).where(eq(journeys.id, id));
    return journey;
  }

  async createJourney(journey: InsertJourney): Promise<Journey> {
    const [newJourney] = await db.insert(journeys).values(journey).returning();
    return newJourney;
  }

  async updateJourneyStatus(id: string, status: string, results?: any): Promise<void> {
    const updates: any = { 
      status: status as any, 
      updatedAt: new Date() 
    };

    if (status === 'running') {
      updates.startedAt = new Date();
    } else if (status === 'completed' || status === 'failed') {
      updates.completedAt = new Date();
    }

    if (results) {
      updates.results = results;
    }

    await db.update(journeys).set(updates).where(eq(journeys.id, id));
  }

  // Credential operations
  async getCredentialsByTenant(tenantId: string): Promise<Credential[]> {
    return await db
      .select()
      .from(credentials)
      .where(eq(credentials.tenantId, tenantId))
      .orderBy(desc(credentials.createdAt));
  }

  async getCredential(id: string): Promise<Credential | undefined> {
    const [credential] = await db.select().from(credentials).where(eq(credentials.id, id));
    return credential;
  }

  async createCredential(credential: InsertCredential): Promise<Credential> {
    const [newCredential] = await db.insert(credentials).values(credential).returning();
    return newCredential;
  }

  async updateCredential(id: string, updates: Partial<Credential>): Promise<Credential> {
    const [updated] = await db
      .update(credentials)
      .set({ ...updates, updatedAt: new Date() })
      .where(eq(credentials.id, id))
      .returning();
    return updated;
  }

  async deleteCredential(id: string): Promise<void> {
    await db.delete(credentials).where(eq(credentials.id, id));
  }

  // Threat Intelligence operations
  async getThreatIntelligenceByTenant(tenantId: string): Promise<ThreatIntelligence[]> {
    return await db
      .select()
      .from(threatIntelligence)
      .where(eq(threatIntelligence.tenantId, tenantId))
      .orderBy(desc(threatIntelligence.createdAt));
  }

  async createThreatIntelligence(intelligence: InsertThreatIntelligence): Promise<ThreatIntelligence> {
    const [newIntelligence] = await db.insert(threatIntelligence).values(intelligence).returning();
    return newIntelligence;
  }

  // Activity operations
  async getActivitiesByTenant(tenantId: string, limit = 50): Promise<Activity[]> {
    return await db
      .select()
      .from(activities)
      .where(eq(activities.tenantId, tenantId))
      .orderBy(desc(activities.timestamp))
      .limit(limit);
  }

  async createActivity(activity: InsertActivity): Promise<Activity> {
    const [newActivity] = await db.insert(activities).values({
      ...activity,
      ipAddress: null,
      userAgent: null
    }).returning();
    return newActivity;
  }

  // Clear all tenant-specific data for re-seeding
  async clearTenantData(tenantId: string): Promise<void> {
    // Delete in order to respect foreign key constraints
    await db.delete(collectorTelemetry).where(
      sql`collector_id IN (SELECT id FROM collectors WHERE tenant_id = ${tenantId})`
    );
    await db.delete(activities).where(eq(activities.tenantId, tenantId));
    await db.delete(threatIntelligence).where(eq(threatIntelligence.tenantId, tenantId));
    await db.delete(credentials).where(eq(credentials.tenantId, tenantId));
    await db.delete(journeys).where(eq(journeys.tenantId, tenantId));
    await db.delete(collectors).where(eq(collectors.tenantId, tenantId));
  }
}

export const storage = new DatabaseStorage();
