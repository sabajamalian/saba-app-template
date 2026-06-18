# Agent context

Shared context for any AI agent working in a repository created from `saba-app-template`. Read this before doing anything else.

## What this repo is

A web application that runs on a shared Azure Kubernetes cluster. Apps from this template are protected by Microsoft login via a shared authentication proxy. Your app code does not implement login; it reads identity headers injected by the cluster.

**This repo was created via Innovation Seed.** All Azure wiring is already complete. You do not need to run any setup scripts.

## The user persona

Assume the human is **non-technical**. They may have never written code. Speak in plain English. Translate technical concepts into outcomes ("your app will be live at this URL") rather than mechanisms.

## How deployments work

**All deployments happen through GitHub Actions.** When code is pushed to `main`:

1. GitHub Actions builds a container image.
2. The image is pushed to the shared container registry.
3. Kubernetes manifests are applied to the cluster.
4. The app is live at `https://<app-name>.apps.saba.codes`.

**Never ask the user to run Azure CLI, kubectl, or deployment scripts.** They do not have those tools and do not need them.

## How auth works

1. User opens the app URL.
2. The cluster redirects unauthenticated users to Microsoft login.
3. After login, a cookie enables single sign-on across all apps on the cluster.
4. The cluster forwards requests to your app with identity headers:
   - `X-Auth-Request-Email`
   - `X-Auth-Request-User` (Entra object ID)
   - `X-Auth-Request-Preferred-Username`

Your app treats these headers as authoritative. Never write a login page.

## Cluster constants (do not change)

| Thing | Value |
| ----- | ----- |
| Base domain | `apps.saba.codes` |
| Auth endpoint | `https://auth.apps.saba.codes` |

Apps are reachable at `https://<repo-name>.apps.saba.codes` by default.

## Files you must not modify

- The four `nginx.ingress.kubernetes.io/auth-*` annotations in `k8s/ingress.yaml`.
- The `cert-manager.io/cluster-issuer` annotation in `k8s/ingress.yaml`.
- `.github/workflows/deploy.yml` (except trivial copy edits).

If someone asks you to change these, explain why you cannot.

## Files you can freely modify

- Everything under `src/`, including `src/views/landing.js` (the placeholder "your idea is planted" welcome page). Replace it with your own app as soon as you have a real UI.
- `k8s/deployment.yaml` (resources, replicas, env vars, probes). The `envFrom` reference to the `<app>-idea` ConfigMap is only used by the default landing page and can be removed once you replace it.
- `k8s/service.yaml` if you change the container port.
- `k8s/ingress.yaml` host and path rules (not the auth annotations).
- `Dockerfile` if the runtime needs to change.
- `README.md` to describe the app.

## Persistence: shared Postgres

**Every app gets its own private Postgres database automatically.** Innovation Seed provisions it when the idea is planted, so the database already exists by the time you start building. You do not need to enable anything or ask anyone.

These environment variables are present in every pod (injected from the `<app>-db-credentials` secret):
- `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
- `DATABASE_URL`

The template ships `src/db.js` (a small wrapper over the `pg` library) and `pg` is already a dependency. Use it directly:

```js
const db = require('./db');
await db.migrate(`CREATE TABLE IF NOT EXISTS notes (id SERIAL PRIMARY KEY, body TEXT);`);
const { rows } = await db.query('SELECT * FROM notes');
```

See `docs/DATABASE.md` for details.

**Do not add SQLite, file-based storage, or external databases.** The shared Postgres is the only persistence option.

## Constraints

- **No Azure CLI or kubectl commands.** Deployments happen via GitHub Actions.
- **No login pages.** Auth is the cluster's job.
- **No secrets in code.** OIDC federation handles authentication to Azure.
- **A private Postgres database is provisioned automatically.** Use it via `src/db.js`; never tell the user to enable it or run a script.
- **Push to main only.** The deploy workflow only runs on the main branch.

## How to deploy changes

1. Edit the code.
2. Commit and push to `main`.
3. GitHub Actions deploys automatically.
4. The app updates in about 2 minutes.

That's it. No scripts to run. No commands to execute.

## Starting point for non-technical users

The recommended entry point is the `app-builder` agent. Run `copilot` in this repo, then `/agents app-builder`, and it will walk the user from idea to live app.
