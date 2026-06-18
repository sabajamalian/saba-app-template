# Database guide

Every app created from this template gets its own **private Postgres database** on the shared cluster. It is shared infrastructure (everyone's apps run on the same Postgres cluster), but each app gets its own database and its own login, completely isolated from every other app.

**If you planted via Innovation Seed, you do not need to enable it.** The orchestrator provisions the database when the idea is planted, so the credentials are already injected into your pod. Just use them. (Repos created manually with "Use this template" instead run `scripts/enable-database.sh` once; see the fallback section below.)

## TL;DR

The template already ships `pg` and `src/db.js`. In your app:

```js
const db = require('./db');

await db.migrate(`CREATE TABLE IF NOT EXISTS notes (
  id SERIAL PRIMARY KEY, body TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);`);

const { rows } = await db.query('SELECT * FROM notes ORDER BY created_at DESC');
```

That's it. No scripts, no setup, no "ask Saba."

## What you get

| Thing | Value |
| ----- | ----- |
| Database name | `app_<repo>` (dashes become underscores, lowercased) |
| Database role | `<repo>_user` (same normalization) |
| Host | `shared-pg-pooler.postgres.svc.cluster.local` |
| Port | `5432` |
| SSL | required (self-signed cert; `src/db.js` handles this) |
| Owner | your role owns its database, with full DDL/DML rights, and cannot see other apps' databases |

## Environment variables in your pods

Innovation Seed creates a Kubernetes Secret called `<repo>-db-credentials` in your app's namespace at plant time. The Deployment in `k8s/deployment.yaml` references it with **optional** keys, so your pods see all of these:

| Env var | Example |
| ------- | ------- |
| `PGHOST` | `shared-pg-pooler.postgres.svc.cluster.local` |
| `PGPORT` | `5432` |
| `PGDATABASE` | `app_recipe_notebook` |
| `PGUSER` | `recipe_notebook_user` |
| `PGPASSWORD` | `(random hex chars)` |
| `PGSSLMODE` | `require` |
| `DATABASE_URL` | `postgresql://recipe_notebook_user:...@shared-pg-pooler.postgres.svc.cluster.local:5432/app_recipe_notebook?sslmode=require` |

`src/db.js` accepts either `DATABASE_URL` or the individual `PG*` variables, so both are available to you.

## The Node.js client

`pg` is already a dependency and `src/db.js` is already committed. The wrapper looks like this:

```js
// src/db.js - small wrapper over node-postgres with retry-on-startup.
const { Pool } = require('pg');

let pool = null;

function hasPgSettings() {
  return Boolean(
    process.env.PGHOST && process.env.PGDATABASE
      && process.env.PGUSER && process.env.PGPASSWORD,
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
    // Strip sslmode and configure TLS ourselves below so sslmode=require does
    // not turn on full certificate chain verification.
    const url = process.env.DATABASE_URL.replace(
      /([?&])sslmode=[^&]*(&|$)/g, (_, pre, post) => (post === '&' ? pre : ''),
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
    config.ssl = false; // explicit opt-out, e.g. local dev
  } else {
    // In-cluster Postgres uses TLS with a self-signed cert: skip verification.
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

// Run a one-shot SQL block at startup. Safe to call repeatedly because
// every statement should be CREATE TABLE IF NOT EXISTS or similar.
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
```

Then in `src/index.js`:

```js
const db = require('./db');

(async () => {
  await db.migrate(`
    CREATE TABLE IF NOT EXISTS notes (
      id SERIAL PRIMARY KEY,
      email TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS notes_email_idx ON notes (email);
  `);
})();

app.post('/notes', async (req, res) => {
  const email = req.get('x-auth-request-email');
  const body = (req.body?.body || '').slice(0, 500);
  const { rows } = await db.query(
    'INSERT INTO notes (email, body) VALUES ($1, $2) RETURNING *',
    [email, body],
  );
  res.json(rows[0]);
});
```

## How provisioning works (and the manual fallback)

For repos created through Innovation Seed, the orchestrator provisions the database automatically when the idea is planted: it creates the managed role on the shared cluster, applies the per-app `Database` resource, and writes the `<repo>-db-credentials` secret into your app namespace. You do nothing.

`scripts/enable-database.sh` does the same thing by hand. It is a **fallback** only for repos created manually with "Use this template" (not through Innovation Seed), or for cluster operators. It requires Azure and `kubectl` access that app authors do not have. If you planted via Innovation Seed, ignore it.

## Connecting from your laptop (debugging)

There is no public Postgres endpoint by design. To poke at your data, port-forward:

```bash
kubectl port-forward -n postgres svc/shared-pg-pooler 5432:5432
PGPASSWORD=$(kubectl get secret <repo>-db-credentials -n <repo> -o jsonpath='{.data.password}' | base64 -d) \
  psql "host=127.0.0.1 port=5432 user=<repo>_user dbname=app_<repo> sslmode=require"
```

Or directly via the primary, with superuser access:

```bash
kubectl exec -n postgres shared-pg-1 -c postgres -- psql -U postgres -d app_<repo>
```

## Backups

There are no automated backups in this dev environment. The data lives on a Persistent Volume, so it survives pod restarts, reschedules, and node failures, but a deleted PVC is gone forever.

If your app stores anything you would mourn, build an export endpoint into the app itself (e.g. `GET /admin/export.json` behind your Microsoft login).

## Rotating the password

```bash
kubectl delete secret <repo>-db-credentials -n postgres
./scripts/enable-database.sh
git commit --allow-empty -m "rotate db password"
git push
```

The script will detect that the postgres-namespace secret is missing, generate a new password, recreate it, mirror it to the app namespace, and the next deploy will roll the pods. Existing connections die; new ones use the new password.

## Tearing it down

If you stop using the database (or are deleting the app entirely):

```bash
APP=<repo>
kubectl delete database "$APP" -n postgres
kubectl exec -n postgres shared-pg-1 -c postgres -- \
  psql -U postgres \
    -c "DROP DATABASE IF EXISTS app_${APP//-/_}" \
    -c "DROP ROLE     IF EXISTS ${APP//-/_}_user"
kubectl delete secret "${APP}-db-credentials" -n postgres
kubectl delete secret "${APP}-db-credentials" -n "$APP"
# Then edit the shared cluster to remove the role from the managed list:
kubectl edit cluster shared-pg -n postgres
# Delete the matching object from spec.managed.roles
gh variable delete APP_DB_ENABLED
rm .db-enabled
```

## How isolation works

- One Postgres role per app, with `LOGIN` and a unique password held in a Kubernetes Secret.
- Each role owns exactly one database and has no privileges on any other.
- All Postgres traffic is in-cluster only; no public endpoint.
- TLS is on by default end-to-end (CNPG-issued certs).
- Connections go through PgBouncer in transaction-pool mode, so a few thousand client connections multiplex onto a smaller pool of real Postgres connections.

## Limits

- Storage: 20 GB across all apps for now. Bump `Cluster.spec.storage.size` on the shared cluster if you outgrow it.
- Connections: PgBouncer is configured with `max_client_conn=1000`, `default_pool_size=25` (per database).
- No PITR or off-cluster backups in v1.
- The cluster runs on confidential VMs in a single Azure region.
