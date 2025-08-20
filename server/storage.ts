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
} from "@shared/schema";
import { db } from "./db";
import { eq, and, desc, gte, isNotNull } from "drizzle-orm";
import { randomUUID } from "crypto";

export interface IStorage {
  // User operations (mandatory for Replit Auth)
  getUser(id: string): Promise<User | undefined>;
  upsertUser(user: UpsertUser): Promise<User>;

  // Tenant operations
  getTenant(id: string): Promise<Tenant | undefined>;
  getUserTenants(userId: string): Promise<(TenantUser & { tenant: Tenant })[]>;
  createTenant(tenant: InsertTenant): Promise<Tenant>;
  addUserToTenant(tenantUser: InsertTenantUser): Promise<TenantUser>;
  updateUserCurrentTenant(userId: string, tenantId: string): Promise<void>;

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
  getJourneysByTenant(tenantId: string): Promise<(Journey & { collector?: Collector; createdBy: User })[]>;
  getJourney(id: string): Promise<Journey | undefined>;
  createJourney(journey: InsertJourney): Promise<Journey>;
  updateJourneyStatus(id: string, status: string, results?: any): Promise<void>;

  // Credential operations
  getCredentialsByTenant(tenantId: string): Promise<(Credential & { createdBy: User })[]>;
  getCredential(id: string): Promise<Credential | undefined>;
  createCredential(credential: InsertCredential): Promise<Credential>;
  updateCredential(id: string, updates: Partial<Credential>): Promise<void>;
  deleteCredential(id: string): Promise<void>;

  // Threat Intelligence operations
  getThreatIntelligenceByTenant(tenantId: string): Promise<ThreatIntelligence[]>;
  createThreatIntelligence(intelligence: InsertThreatIntelligence): Promise<ThreatIntelligence>;

  // Activity operations
  getActivitiesByTenant(tenantId: string, limit?: number): Promise<(Activity & { user: User })[]>;
  createActivity(activity: InsertActivity): Promise<Activity>;
}

export class DatabaseStorage implements IStorage {
  // User operations
  async getUser(id: string): Promise<User | undefined> {
    const [user] = await db.select().from(users).where(eq(users.id, id));
    return user;
  }

  async upsertUser(userData: UpsertUser): Promise<User> {
    const [user] = await db
      .insert(users)
      .values(userData)
      .onConflictDoUpdate({
        target: users.id,
        set: {
          ...userData,
          updatedAt: new Date(),
        },
      })
      .returning();
    return user;
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
  async getJourneysByTenant(tenantId: string): Promise<(Journey & { collector?: Collector; createdBy: User })[]> {
    return await db
      .select({
        id: journeys.id,
        tenantId: journeys.tenantId,
        name: journeys.name,
        type: journeys.type,
        status: journeys.status,
        config: journeys.config,
        results: journeys.results,
        collectorId: journeys.collectorId,
        createdBy: users,
        startedAt: journeys.startedAt,
        completedAt: journeys.completedAt,
        createdAt: journeys.createdAt,
        updatedAt: journeys.updatedAt,
        collector: collectors,
      })
      .from(journeys)
      .innerJoin(users, eq(journeys.createdBy, users.id))
      .leftJoin(collectors, eq(journeys.collectorId, collectors.id))
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
  async getCredentialsByTenant(tenantId: string): Promise<(Credential & { createdBy: User })[]> {
    return await db
      .select({
        id: credentials.id,
        tenantId: credentials.tenantId,
        name: credentials.name,
        type: credentials.type,
        delineaSecretId: credentials.delineaSecretId,
        delineaPath: credentials.delineaPath,
        description: credentials.description,
        createdBy: users,
        createdAt: credentials.createdAt,
        updatedAt: credentials.updatedAt,
      })
      .from(credentials)
      .innerJoin(users, eq(credentials.createdBy, users.id))
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

  async updateCredential(id: string, updates: Partial<Credential>): Promise<void> {
    await db
      .update(credentials)
      .set({ ...updates, updatedAt: new Date() })
      .where(eq(credentials.id, id));
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
  async getActivitiesByTenant(tenantId: string, limit = 20): Promise<(Activity & { user: User })[]> {
    return await db
      .select({
        id: activities.id,
        tenantId: activities.tenantId,
        userId: activities.userId,
        action: activities.action,
        resource: activities.resource,
        resourceId: activities.resourceId,
        metadata: activities.metadata,
        timestamp: activities.timestamp,
        user: users,
      })
      .from(activities)
      .innerJoin(users, eq(activities.userId, users.id))
      .where(eq(activities.tenantId, tenantId))
      .orderBy(desc(activities.timestamp))
      .limit(limit);
  }

  async createActivity(activity: InsertActivity): Promise<Activity> {
    const [newActivity] = await db.insert(activities).values(activity).returning();
    return newActivity;
  }
}

export const storage = new DatabaseStorage();
