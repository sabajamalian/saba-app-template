# saba-app-template

A GitHub template for deploying apps to Saba's AKS cluster with Microsoft Entra ID "Easy Auth" baked in. Click **Use this template**, run one bootstrap command, push to `main`, and you have an authenticated app at `https://<your-repo-name>.apps.saba.codes`.

## What you get out of the box

- A tiny Node.js + Express app (`src/index.js`) that returns:
  - `GET /` -> HTTP 418 with a teapot message and the signed-in user's email.
  - `GET /me` -> JSON with `email`, `user`, `preferredUsername`, and `groups` derived from the trusted `X-Auth-Request-*` headers.
  - `GET /healthz` -> `200 OK` for K8s probes.
- A multi-stage `Dockerfile` (node:22-alpine, non-root, read-only rootfs) targeting AMD64 with a built-in HEALTHCHECK.
- Kubernetes manifests in `k8s/` that are pre-wired with the four NGINX annotations needed for Entra Easy Auth, cert-manager TLS, and a per-app namespace.
- A GitHub Actions workflow (`.github/workflows/deploy.yml`) that uses **OIDC federation** (no long-lived secrets) to:
  1. `az acr build` the image into the shared registry.
  2. `kubectl apply` the rendered manifests into a namespace named after the repo.
- A one-shot bootstrap script (`scripts/bootstrap.sh`) that creates a per-app managed identity, federates it to your repo, grants the minimum permissions, and sets all the Actions Variables for you.

## Quick start

1. **Use this template** -> create your new repo (let's call it `coffee-tracker`).
2. Clone it locally.
3. Run the bootstrap once:
   ```bash
   ./scripts/bootstrap.sh
   ```
   You need:
   - `gh auth status` -> logged in.
   - `az account show` -> on tenant `d0401efd-a66a-4265-88d8-7d7801dda24e` and subscription `4aa6e4ed-23f8-4ccd-a09a-36527503ab04`.
   - `kubectl` working against the cluster (`az aks get-credentials -g rg-aks-saba-eastus -n aks-saba-eastus`).
4. Push to `main`. The Actions workflow will build, push, and deploy to:
   ```
   https://coffee-tracker.apps.saba.codes
   ```
5. Open the URL. You'll be redirected to Entra ID login once; thereafter sessions are shared across all `*.apps.saba.codes` apps so you don't re-auth.

## Reading the user's identity in your app

The shared oauth2-proxy injects these request headers, which you should treat as authoritative:

| Header                             | Example                              |
| ---------------------------------- | ------------------------------------ |
| `X-Auth-Request-Email`             | `alice@contoso.com`                  |
| `X-Auth-Request-User`              | `Nuz3mgDggFnRUK5m...` (Entra OID)    |
| `X-Auth-Request-Preferred-Username`| `alice@contoso.com`                  |
| `X-Auth-Request-Groups`            | `eng,admins` (only if groups claim is enabled on the app reg) |

In Express:
```js
app.get('/whoami', (req, res) => {
  res.json({ email: req.get('x-auth-request-email') });
});
```

Do **not** trust these headers when running locally outside the cluster. They're only set by NGINX after a successful `auth_request` to oauth2-proxy.

## What the bootstrap actually does

| Step | Action |
| ---- | ------ |
| 1    | Creates user-assigned managed identity `id-app-<repo>` in `rg-aks-saba-eastus`. |
| 2    | Federates that identity to GitHub OIDC for `repo:<owner>/<repo>:ref:refs/heads/main`. |
| 3    | Grants `AcrPush` on `acrsabaeastus`. |
| 4    | Grants `Azure Kubernetes Service Cluster User Role` on `aks-saba-eastus`. |
| 5    | Creates K8s namespace `<repo>` and a `RoleBinding` granting your identity `edit` rights **only in that namespace**. |
| 6    | Sets repo Actions Variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ACR_NAME`, `AKS_NAME`, `AKS_RG`, `APP_HOSTNAME`. No secrets. |

The script is idempotent. Safe to re-run.

## Customizing for your app

- **Replace the app code in `src/`.** Keep `GET /healthz` returning 200 or update `k8s/deployment.yaml`'s probes.
- **Change the port?** Update `src/index.js`'s `PORT` default, the Dockerfile `EXPOSE`, the deployment `containerPort`, and the service `targetPort` consistently.
- **Need extra K8s resources?** Drop more YAML files into `k8s/`. Anything in that folder is `envsubst`'d (with `${APP_NAME}`, `${IMAGE}`, `${HOSTNAME}`) and `kubectl apply`'d.
- **Custom hostname** (e.g., `my-cool-app.apps.saba.codes` instead of repo name): set the `APP_HOSTNAME` repo variable to whatever you want, then push.

## Local development

```bash
cd src
npm install
APP_NAME=local npm run dev
curl -i http://localhost:8080/      # 418
curl -i http://localhost:8080/me    # null email, since no auth in front
```

To simulate the auth headers locally:
```bash
curl -H 'X-Auth-Request-Email: me@example.com' http://localhost:8080/me
```

## Tearing down an app

```bash
kubectl delete namespace <repo>
az identity delete -g rg-aks-saba-eastus -n id-app-<repo>
```

DNS is a wildcard, so removing the K8s resources is enough to take the URL offline.

## Security notes

- No long-lived Azure credentials live anywhere. OIDC federation only.
- Each app has its own managed identity, scoped to its own K8s namespace.
- ACR is shared across all apps on this cluster. Any app's identity could push under any image name, so don't use this template for code you don't trust to share an ACR with you.
- The Entra app registration is single-tenant; only members and guests of your Entra tenant can log in. Invite external collaborators via `az ad user invite ...`.

## License

MIT.
