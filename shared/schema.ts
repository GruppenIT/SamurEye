import { sql } from 'drizzle-orm';
import {
  boolean,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  real,
  text,
  timestamp,
  varchar,
} from "drizzle-orm/pg-core";
import { relations } from "drizzle-orm";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

// Session storage table (mandatory for Replit Auth)
export const sessions = pgTable(
  "sessions",
  {
    sid: varchar("sid").primaryKey(),
    sess: jsonb("sess").notNull(),
    expire: timestamp("expire").notNull(),
  },
  (table) => [index("IDX_session_expire").on(table.expire)],
);

// User roles enum - Global and Tenant-specific
export const globalRoleEnum = pgEnum("global_role", ["global_admin", "global_auditor"]);
export const tenantRoleEnum = pgEnum("tenant_role", ["tenant_admin", "operator", "viewer", "tenant_auditor"]);

// User storage table (mandatory for Replit Auth)
export const users = pgTable("users", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  email: varchar("email").unique(),
  firstName: varchar("first_name"),
  lastName: varchar("last_name"),
  profileImageUrl: varchar("profile_image_url"),
  password: varchar("password"), // For local auth users
  currentTenantId: varchar("current_tenant_id"),
  preferredLanguage: varchar("preferred_language").default('pt-BR'),
  globalRole: globalRoleEnum("global_role"), // Global admin/auditor via SSO
  isGlobalUser: boolean("is_global_user").default(false), // SSO users vs tenant users
  isSocUser: boolean("is_soc_user").default(false), // SOC users can access all tenants
  isActive: boolean("is_active").default(true),
  lastLoginAt: timestamp("last_login_at"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Tenants
export const tenants = pgTable("tenants", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  name: varchar("name").notNull(),
  slug: varchar("slug").unique().notNull(),
  description: text("description"),
  logoUrl: varchar("logo_url"), // Tenant-specific logo
  settings: jsonb("settings"),
  isActive: boolean("is_active").default(true),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Tenant users (many-to-many with roles)
export const tenantUsers = pgTable("tenant_users", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  tenantId: varchar("tenant_id").notNull().references(() => tenants.id, { onDelete: 'cascade' }),
  userId: varchar("user_id").notNull().references(() => users.id, { onDelete: 'cascade' }),
  role: tenantRoleEnum("role").notNull().default('viewer'),
  isActive: boolean("is_active").default(true),
  createdAt: timestamp("created_at").defaultNow(),
});

// Collectors
export const collectorStatusEnum = pgEnum("collector_status", ["online", "offline", "enrolling", "error"]);

export const collectors = pgTable("collectors", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  tenantId: varchar("tenant_id").notNull().references(() => tenants.id, { onDelete: 'cascade' }),
  name: varchar("name").notNull(),
  hostname: varchar("hostname"),
  ipAddress: varchar("ip_address"),
  status: collectorStatusEnum("status").notNull().default('offline'),
  version: varchar("version"),
  lastSeen: timestamp("last_seen"),
  enrollmentToken: varchar("enrollment_token"),
  enrollmentTokenExpires: timestamp("enrollment_token_expires"),
  metadata: jsonb("metadata"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Collector telemetry
export const collectorTelemetry = pgTable("collector_telemetry", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  collectorId: varchar("collector_id").notNull().references(() => collectors.id, { onDelete: 'cascade' }),
  cpuUsage: real("cpu_usage"),
  memoryUsage: real("memory_usage"),
  diskUsage: real("disk_usage"),
  networkThroughput: jsonb("network_throughput"),
  processes: jsonb("processes"),
  timestamp: timestamp("timestamp").defaultNow(),
});

// Journey types
export const journeyTypeEnum = pgEnum("journey_type", ["attack_surface", "ad_hygiene", "edr_testing"]);
export const journeyStatusEnum = pgEnum("journey_status", ["pending", "running", "completed", "failed", "cancelled"]);

// Journeys
export const journeys = pgTable("journeys", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  tenantId: varchar("tenant_id").notNull().references(() => tenants.id, { onDelete: 'cascade' }),
  name: varchar("name").notNull(),
  type: journeyTypeEnum("type").notNull(),
  status: journeyStatusEnum("status").notNull().default('pending'),
  config: jsonb("config").notNull(),
  results: jsonb("results"),
  collectorId: varchar("collector_id").references(() => collectors.id),
  createdBy: varchar("created_by").notNull().references(() => users.id),
  startedAt: timestamp("started_at"),
  completedAt: timestamp("completed_at"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Credentials (stored references to Delinea)
export const credentials = pgTable("credentials", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  tenantId: varchar("tenant_id").notNull().references(() => tenants.id, { onDelete: 'cascade' }),
  name: varchar("name").notNull(),
  type: varchar("type").notNull(), // SSH, LDAP, etc.
  delineaSecretId: varchar("delinea_secret_id"), // Reference to Delinea Secret Server
  delineaPath: varchar("delinea_path").notNull(), // Path in Delinea: BAS/<tenantid>/<Type>/<Name>
  description: text("description"),
  createdBy: varchar("created_by").notNull().references(() => users.id),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Threat Intelligence
export const threatIntelligence = pgTable("threat_intelligence", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  tenantId: varchar("tenant_id").notNull().references(() => tenants.id, { onDelete: 'cascade' }),
  type: varchar("type").notNull(), // cve, ioc, signature, etc.
  source: varchar("source").notNull(),
  severity: varchar("severity").notNull(), // critical, high, medium, low, info
  title: varchar("title").notNull(),
  description: text("description"),
  data: jsonb("data"),
  score: integer("score"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Global system settings (for platform-wide configuration)
export const systemSettings = pgTable("system_settings", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  key: varchar("key").unique().notNull(),
  value: text("value"),
  description: text("description"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Tenant users authentication (for local users with MFA)
export const tenantUserAuth = pgTable("tenant_user_auth", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  tenantUserId: varchar("tenant_user_id").notNull().references(() => tenantUsers.id, { onDelete: 'cascade' }),
  username: varchar("username").notNull(),
  passwordHash: varchar("password_hash"),
  totpSecret: varchar("totp_secret"),
  emailVerified: boolean("email_verified").default(false),
  lastLogin: timestamp("last_login"),
  loginAttempts: integer("login_attempts").default(0),
  lockedUntil: timestamp("locked_until"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Activities/Audit Log
export const activities = pgTable("activities", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  tenantId: varchar("tenant_id").references(() => tenants.id, { onDelete: 'cascade' }), // Nullable for global actions
  userId: varchar("user_id").notNull().references(() => users.id),
  action: varchar("action").notNull(),
  resource: varchar("resource").notNull(),
  resourceId: varchar("resource_id"),
  metadata: jsonb("metadata"),
  ipAddress: varchar("ip_address"),
  userAgent: varchar("user_agent"),
  timestamp: timestamp("timestamp").defaultNow(),
});

// Relations
export const usersRelations = relations(users, ({ many }) => ({
  tenantUsers: many(tenantUsers),
  activities: many(activities),
  journeys: many(journeys),
  credentials: many(credentials),
}));

export const tenantsRelations = relations(tenants, ({ many }) => ({
  tenantUsers: many(tenantUsers),
  collectors: many(collectors),
  journeys: many(journeys),
  credentials: many(credentials),
  threatIntelligence: many(threatIntelligence),
  activities: many(activities),
}));

export const systemSettingsRelations = relations(systemSettings, ({ many }) => ({}));

export const tenantUserAuthRelations = relations(tenantUserAuth, ({ one }) => ({
  tenantUser: one(tenantUsers, { fields: [tenantUserAuth.tenantUserId], references: [tenantUsers.id] }),
}));

export const tenantUsersRelations = relations(tenantUsers, ({ one, many }) => ({
  tenant: one(tenants, { fields: [tenantUsers.tenantId], references: [tenants.id] }),
  user: one(users, { fields: [tenantUsers.userId], references: [users.id] }),
  auth: one(tenantUserAuth),
}));

export const collectorsRelations = relations(collectors, ({ one, many }) => ({
  tenant: one(tenants, { fields: [collectors.tenantId], references: [tenants.id] }),
  telemetry: many(collectorTelemetry),
  journeys: many(journeys),
}));

export const collectorTelemetryRelations = relations(collectorTelemetry, ({ one }) => ({
  collector: one(collectors, { fields: [collectorTelemetry.collectorId], references: [collectors.id] }),
}));

export const journeysRelations = relations(journeys, ({ one }) => ({
  tenant: one(tenants, { fields: [journeys.tenantId], references: [tenants.id] }),
  collector: one(collectors, { fields: [journeys.collectorId], references: [collectors.id] }),
  createdBy: one(users, { fields: [journeys.createdBy], references: [users.id] }),
}));

export const credentialsRelations = relations(credentials, ({ one }) => ({
  tenant: one(tenants, { fields: [credentials.tenantId], references: [tenants.id] }),
  createdBy: one(users, { fields: [credentials.createdBy], references: [users.id] }),
}));

export const threatIntelligenceRelations = relations(threatIntelligence, ({ one }) => ({
  tenant: one(tenants, { fields: [threatIntelligence.tenantId], references: [tenants.id] }),
}));

export const activitiesRelations = relations(activities, ({ one }) => ({
  tenant: one(tenants, { fields: [activities.tenantId], references: [tenants.id] }),
  user: one(users, { fields: [activities.userId], references: [users.id] }),
}));

// Types
export type UpsertUser = typeof users.$inferInsert;
export type User = typeof users.$inferSelect;

export type Tenant = typeof tenants.$inferSelect;
export type InsertTenant = typeof tenants.$inferInsert;
export const insertTenantSchema = createInsertSchema(tenants).omit({ id: true, createdAt: true, updatedAt: true });

export type SystemSettings = typeof systemSettings.$inferSelect;
export type InsertSystemSettings = typeof systemSettings.$inferInsert;
export const insertSystemSettingsSchema = createInsertSchema(systemSettings).omit({ id: true, createdAt: true, updatedAt: true });

export type TenantUserAuth = typeof tenantUserAuth.$inferSelect;
export type InsertTenantUserAuth = typeof tenantUserAuth.$inferInsert;
export const insertTenantUserAuthSchema = createInsertSchema(tenantUserAuth).omit({ 
  id: true, 
  createdAt: true, 
  updatedAt: true,
  passwordHash: true,
  totpSecret: true
});

export type TenantUser = typeof tenantUsers.$inferSelect;
export type InsertTenantUser = typeof tenantUsers.$inferInsert;

export type Collector = typeof collectors.$inferSelect;
export type InsertCollector = typeof collectors.$inferInsert;
export const insertCollectorSchema = createInsertSchema(collectors).omit({ 
  id: true, 
  createdAt: true, 
  updatedAt: true,
  enrollmentToken: true,
  enrollmentTokenExpires: true 
});

export type CollectorTelemetry = typeof collectorTelemetry.$inferSelect;
export type InsertCollectorTelemetry = typeof collectorTelemetry.$inferInsert;

export type Journey = typeof journeys.$inferSelect;
export type InsertJourney = typeof journeys.$inferInsert;
export const insertJourneySchema = createInsertSchema(journeys).omit({ 
  id: true, 
  createdAt: true, 
  updatedAt: true,
  startedAt: true,
  completedAt: true,
  createdBy: true
});

export type Credential = typeof credentials.$inferSelect;
export type InsertCredential = typeof credentials.$inferInsert;
export const insertCredentialSchema = createInsertSchema(credentials).omit({ 
  id: true, 
  createdAt: true, 
  updatedAt: true,
  createdBy: true,
  delineaSecretId: true
});

export type ThreatIntelligence = typeof threatIntelligence.$inferSelect;
export type InsertThreatIntelligence = typeof threatIntelligence.$inferInsert;

export type Activity = typeof activities.$inferSelect;
export type InsertActivity = typeof activities.$inferInsert;
