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
- `k8s/deployment.yaml` resources, replicas, env vars, probes (keep `/healthz`).
- `k8s/service.yaml` if you change the container port.
- `k8s/ingress.yaml` host, path rules, and TLS secret name (NOT the auth annotations).
- `Dockerfile` if the runtime needs change (Node version, additional system deps).
- `README.md` to describe the app you actually built.
- New manifests in `k8s/` (e.g., `pvc.yaml` for SQLite persistence).

## Constraints

- No paid Azure resources beyond what the cluster provides. No managed databases, no Key Vault, no extra ingress controllers, no Front Door, no Application Gateway.
- No long-lived secrets anywhere. All Azure auth uses GitHub OIDC federation set up by `bootstrap.sh`.
- Stateless by default. If the user needs persistence, use SQLite on a PersistentVolumeClaim and warn them this means single-pod (`replicas: 1`, `strategy: Recreate`).
- Image base is `node:22-alpine`, non-root, read-only rootfs. If you need a writable directory, mount an `emptyDir` volume; do not relax the security context.
- Do not ask the user for any password, API key, or token. The only credentials they may need are `gh auth login` and `az login`, which they run in their own terminal.

## How to deploy (after edits)

1. Ensure `bootstrap.sh` has been run (check with `gh variable list | grep AZURE_CLIENT_ID`). If not, run it.
2. Commit and push to `main`.
3. Watch the Actions run with `gh run watch`.
4. App is live at `https://<APP_HOSTNAME-from-repo-vars>` once the workflow goes green.

## Starting point for non-technical users

The recommended entry point is the `app-builder` custom agent at `.github/agents/app-builder.md`. Run `copilot` in this repo, then `/agents app-builder`, and it will walk the user from idea to live app.
