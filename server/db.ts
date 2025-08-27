import { Pool } from 'pg';
import { drizzle } from 'drizzle-orm/node-postgres';
import * as schema from "@shared/schema";

if (!process.env.DATABASE_URL) {
  throw new Error(
    "DATABASE_URL must be set. Did you forget to provision a database?",
  );
}

export const pool = new Pool({ 
  connectionString: process.env.DATABASE_URL,
  // Configuração adicional para garantir conectividade
  ssl: false, // Desabilita SSL para conexões locais
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 30000,
  max: 20 // Máximo de conexões no pool
});

export const db = drizzle(pool, { schema });