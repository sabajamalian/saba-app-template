// src/db.js - small wrapper over node-postgres (pg).
//
// Every app on the cluster gets its own database. Innovation Seed provisions it
// when the idea is planted and injects the credentials via the
// <app>-db-credentials secret, so in normal operation a database is always
// available. This wrapper connects using either DATABASE_URL or the standard
// PGHOST/PGPORT/PGDATABASE/PGUSER/PGPASSWORD variables (both are present in the
// secret), and degrades gracefully (returns null / throws a clear error) when
// neither is set, e.g. in local dev.
const { Pool } = require('pg');

let pool = null;

function hasPgSettings() {
  return Boolean(
    process.env.PGHOST
      && process.env.PGDATABASE
      && process.env.PGUSER
      && process.env.PGPASSWORD,
  );
}

function sslModeFrom(url) {
  const m = /[?&]sslmode=([^&]+)/.exec(url || '');
  return m ? m[1].toLowerCase() : '';
}

function getPool() {
  if (pool) return pool;
  if (!process.env.DATABASE_URL && !hasPgSettings()) return null;

  const sslmode = (sslModeFrom(process.env.DATABASE_URL) || process.env.PGSSLMODE || '').toLowerCase();

  let config;
  if (process.env.DATABASE_URL) {
    // Strip sslmode from the URL and configure TLS ourselves below, so that
    // sslmode=require does not turn on full certificate chain verification.
    const url = process.env.DATABASE_URL.replace(
      /([?&])sslmode=[^&]*(&|$)/g,
      (_, pre, post) => (post === '&' ? pre : ''),
    );
    config = { connectionString: url };
  } else {
    config = {
      host: process.env.PGHOST,
      port: parseInt(process.env.PGPORT || '5432', 10),
      database: process.env.PGDATABASE,
      user: process.env.PGUSER,
      password: process.env.PGPASSWORD,
    };
  }

  if (sslmode === 'disable') {
    // Explicit opt-out, e.g. local dev against a plain Postgres.
    config.ssl = false;
  } else {
    // In-cluster Postgres requires TLS but presents a self-signed certificate,
    // so skip chain verification. This is the default for the shared cluster.
    config.ssl = { rejectUnauthorized: false };
  }

  pool = new Pool({
    ...config,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
  });
  pool.on('error', err => console.error('[db] idle client error:', err));
  return pool;
}

// Run a one-shot SQL block at startup, retrying while the database finishes
// provisioning. Safe to call repeatedly when every statement is idempotent
// (CREATE TABLE IF NOT EXISTS, etc.). No-op when no database is configured.
async function migrate(sql) {
  const p = getPool();
  if (!p) return;
  for (let attempt = 1; attempt <= 10; attempt++) {
    try {
      await p.query(sql);
      console.log('[db] migrate ok');
      return;
    } catch (err) {
      if (attempt === 10) throw err;
      console.warn(`[db] migrate attempt ${attempt} failed: ${err.message}, retrying...`);
      await new Promise(r => setTimeout(r, 1000 * attempt));
    }
  }
}

async function query(text, params) {
  const p = getPool();
  if (!p) throw new Error('Database not configured: no DATABASE_URL or PG* environment variables.');
  return p.query(text, params);
}

function hasDatabase() {
  return Boolean(process.env.DATABASE_URL || hasPgSettings());
}

module.exports = { getPool, query, migrate, hasDatabase };
