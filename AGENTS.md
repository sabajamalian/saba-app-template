# Agent context

Shared, ground-truth context for any AI agent working in a repository created from `saba-app-template`. Read this before doing anything else.

## What this repo is

A starter repo for a single web application that gets deployed to a shared Azure Kubernetes Service cluster called **aks-saba-eastus**. Apps deployed from this template are automatically protected by Microsoft Entra ID login (Easy Auth) via a shared `oauth2-proxy` running at `auth.apps.saba.codes`. The app code itself does not implement login; it just reads identity headers injected by the ingress.

## The user persona

Assume the human running you is **non-technical**. They may have never written code. They probably do not know what Kubernetes, Docker, OIDC, or YAML are. Speak in plain English. Translate every technical concept into outcomes ("your app will be live on the internet at this URL") rather than mechanisms.

## Cluster constants (do not change)

| Thing | Value |
| ----- | ----- |
| Subscription ID | `4aa6e4ed-23f8-4ccd-a09a-36527503ab04` |
| Tenant ID | `d0401efd-a66a-4265-88d8-7d7801dda24e` |
| Resource group | `rg-aks-saba-eastus` |
| AKS cluster name | `aks-saba-eastus` |
| ACR registry | `acrsabaeastus` |
| Base domain | `apps.saba.codes` |
| Region | `eastus` |
| Auth endpoint | `https://auth.apps.saba.codes` |
| Ingress LB IP | `74.179.226.103` (DNS A record `*.apps.saba.codes` already points here) |

A new app is reachable at `https://<repo-name>.apps.saba.codes` by default, unless the user explicitly overrides `APP_HOSTNAME`.

## How auth works (so you can explain it)

1. User opens `https://<repo>.apps.saba.codes`.
2. NGINX ingress sees the four `nginx.ingress.kubernetes.io/auth-*` annotations on this app's Ingress and asks oauth2-proxy "is this request authenticated?".
3. If not, the user is redirected to `auth.apps.saba.codes` -> Microsoft login -> back. A cookie set on `.apps.saba.codes` means single sign-on across every app on this cluster.
4. NGINX then forwards the request to the app, with the user's identity in these trusted request headers:
   - `X-Auth-Request-Email`
   - `X-Auth-Request-User` (Entra object ID)
   - `X-Auth-Request-Preferred-Username`
   - `X-Auth-Request-Groups` (only if you enabled the groups optional claim on the Entra app)

The app code MUST treat these headers as authoritative and MUST NOT implement its own login.

## Files you must not touch

- `scripts/bootstrap.sh` - cluster wiring; load-bearing.
- The four `nginx.ingress.kubernetes.io/auth-*` annotations in `k8s/ingress.yaml`.
- The `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation in `k8s/ingress.yaml`.
- `.github/workflows/deploy.yml` (except trivial copy edits).

If a user asks you to change one of these, push back and explain why.

## Files you should freely shape to fit the user's app

- Everything under `src/`.
- `k8s/deployment.yaml` resources, replicas, env vars (the optional `PG*` block is fine to leave in place; it is silent when no DB is enabled), probes (keep `/healthz`).
- `k8s/service.yaml` if you change the container port.
- `k8s/ingress.yaml` host, path rules, and TLS secret name (NOT the auth annotations).
- `Dockerfile` if the runtime needs change (Node version, additional system deps).
- `README.md` to describe the app you actually built.
- New manifests in `k8s/` if you genuinely need them (rare; most apps need nothing beyond what is in the box).

## Persistence: shared Postgres

The cluster runs a shared CloudNativePG cluster called `shared-pg` in the `postgres` namespace, fronted by a PgBouncer pooler. Apps opt in by running `scripts/enable-database.sh` once, which gives the app:

- A private database `app_<repo>` and a private role `<repo>_user`.
- A Kubernetes Secret called `<repo>-db-credentials` in the app's namespace, with the keys `host`, `port`, `database`, `username`, `password`, `sslmode`, and `DATABASE_URL`.
- The Deployment in `k8s/deployment.yaml` already references that secret with `optional: true`, so the env vars `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGSSLMODE`, and `DATABASE_URL` light up automatically once the secret exists, and stay quietly absent before that.

Use the **node-postgres** library (`pg`) for Node apps. The complete client wrapper, schema-init pattern, and debugging recipes are in `docs/DATABASE.md`. Do not introduce a different database, an ORM, or a separate cache unless the user explicitly asks.

This is the **only** persistence pattern this template supports. Do not add SQLite, do not mount PVCs from the app's namespace, do not use Azure Storage or Cosmos DB. If the user wants persistence, run `scripts/enable-database.sh`.

## Constraints

- No paid Azure resources beyond what the cluster provides. No managed databases, no Key Vault, no extra ingress controllers, no Front Door, no Application Gateway. The shared in-cluster Postgres is the persistence story; do not propose alternatives.
- No long-lived secrets anywhere. All Azure auth uses GitHub OIDC federation set up by `bootstrap.sh`. The Postgres credentials are auto-generated and live as Kubernetes Secrets only.
- Stateless by default. If the user needs persistence, run `scripts/enable-database.sh` and use the env vars it provides; everything else is off limits.
- Image base is `node:22-alpine`, non-root, read-only rootfs. If you need a writable directory, mount an `emptyDir` volume; do not relax the security context.
- Do not ask the user for any password, API key, or token. The only credentials they may need are `gh auth login` and `az login`, which they run in their own terminal.

## How to deploy (after edits)

1. Ensure `bootstrap.sh` has been run (check with `gh variable list | grep AZURE_CLIENT_ID`). If not, run it.
2. If the app needs a database, ensure `enable-database.sh` has been run (check with `gh variable list | grep APP_DB_ENABLED` or `[ -f .db-enabled ]`). If not, run it.
3. Commit and push to `main`.
4. Watch the Actions run with `gh run watch`.
5. App is live at `https://<APP_HOSTNAME-from-repo-vars>` once the workflow goes green.

## Starting point for non-technical users

The recommended entry point is the `app-builder` custom agent at `.github/agents/app-builder.md`. Run `copilot` in this repo, then `/agents app-builder`, and it will walk the user from idea to live app.
