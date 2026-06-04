# Database guide

This template can give your app a **private Postgres database** that lives on the same Kubernetes cluster as the app. It is shared infrastructure (everyone's apps run on the same Postgres cluster), but each app gets its own database and its own login, completely isolated from every other app.

## TL;DR

```bash
./scripts/bootstrap.sh        # one-time cluster wiring (already done if you used the agent)
./scripts/enable-database.sh  # one-time database provisioning
git push                      # next deploy picks up the new env vars
```

After that, in your app you can just:

```js
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const { rows } = await pool.query('SELECT now()');
```

## What you get

| Thing | Value |
| ----- | ----- |
| Database name | `app_<repo>` (dashes become underscores, lowercased) |
| Database role | `<repo>_user` (same normalization) |
| Host | `shared-pg-pooler.postgres.svc.cluster.local` |
| Port | `5432` |
| SSL | required |
| Owner | your role owns its database, with full DDL/DML rights, and cannot see other apps' databases |

## Environment variables in your pods

`scripts/enable-database.sh` writes a Kubernetes Secret called `<repo>-db-credentials` into your app's namespace. The Deployment in `k8s/deployment.yaml` references that secret with **optional** keys, so:

- If you have not run `enable-database.sh`, the secret does not exist and the env vars are simply absent. Your stateless app is unaffected.
- After you run it and redeploy, your pods see all of these:

| Env var | Example |
| ------- | ------- |
| `PGHOST` | `shared-pg-pooler.postgres.svc.cluster.local` |
| `PGPORT` | `5432` |
| `PGDATABASE` | `app_recipe_notebook` |
| `PGUSER` | `recipe_notebook_user` |
| `PGPASSWORD` | `(40 random hex chars)` |
| `PGSSLMODE` | `require` |
| `DATABASE_URL` | `postgresql://recipe_notebook_user:...@shared-pg-pooler.postgres.svc.cluster.local:5432/app_recipe_notebook?sslmode=require` |

## Recommended Node.js client

Add the dep:

```bash
cd src && npm install pg
```

Drop this in `src/db.js`:

```js
// src/db.js - small wrapper over node-postgres with retry-on-startup.
const { Pool } = require('pg');

let pool = null;

function getPool() {
  if (!process.env.DATABASE_URL) return null;
  if (pool) return pool;
  pool = new Pool({
    connectionString: process.env.DATABASE_URL,
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
  if (!p) throw new Error('Database not configured. Run scripts/enable-database.sh.');
  return p.query(text, params);
}

function hasDatabase() {
  return !!process.env.DATABASE_URL;
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
