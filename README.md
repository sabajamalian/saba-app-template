# saba-app-template

A starting point for a brand-new web app that runs on a shared Kubernetes cluster, with **Microsoft login already wired in for you**. Click "Use this template", clone the new repo, run one command, and answer a few questions in plain English. A live, password-protected website comes out the other side.

## Quick start (no coding required)

You will need three things installed on your computer once. After that, every new app from this template is a few minutes of conversation.

1. [`gh`](https://cli.github.com/) - GitHub's command-line tool. After installing, run `gh auth login` and pick GitHub.com.
2. [`az`](https://learn.microsoft.com/cli/azure/install-azure-cli) - Microsoft Azure's command-line tool. After installing, run `az login --tenant d0401efd-a66a-4265-88d8-7d7801dda24e`.
3. [`copilot`](https://docs.github.com/copilot/github-copilot-cli) - the GitHub Copilot CLI.

Then, for each new app:

1. On GitHub, click **Use this template** -> **Create a new repository**. Pick a short, lowercase, dash-separated name like `recipe-notebook` or `team-standup`. That name becomes your app's URL.
2. Clone it to your computer:
   ```bash
   gh repo clone <your-username>/<your-new-repo>
   cd <your-new-repo>
   ```
3. Start the agent:
   ```bash
   copilot
   /agents app-builder
   ```
4. The **app-builder** agent will say hi, ask you a few short questions about what you want to build, write a plan for you to approve, build the app, and deploy it. The whole flow is conversational. You never have to look at code or YAML.

When it finishes, your app is live at:

```
https://<your-new-repo>.apps.saba.codes
```

The first time you open it, you will sign in with Microsoft. After that, you stay signed in across every app on this cluster.

## What you get

- A web app that **only logged-in Microsoft accounts can access**. You did not write the login code; the cluster handles it.
- A **public HTTPS URL** with a real certificate, no certificate setup on your end.
- An **optional private database** (Postgres on the cluster). The agent will offer to set it up; if you say yes, your app gets its own database and credentials with no work from you. See `docs/DATABASE.md`.
- Every push to `main` automatically rebuilds and redeploys. The deploy uses GitHub OIDC, so there are no passwords or API keys stored anywhere.
- Each app lives in its own isolated Kubernetes namespace, with its own identity scoped to that namespace.

## Adding more features later

Just open the repo, run `copilot`, and tell it what you want. The agent (or any future Copilot session) reads `AGENTS.md` and the existing `PLAN.md` to know the cluster's rules and your app's current state. You can say things like:

- "Add a page that lists my notes sorted by date."
- "Make the homepage show the user's name in the corner."
- "Add an Atom feed at /feed."

It will edit the code, push, and confirm when the new version is live.

## Reading the signed-in user inside your app

The cluster injects four trusted request headers on every request to your app. Use them, and never write a login page yourself.

| Header | What it is | Example |
| ------ | ---------- | ------- |
| `X-Auth-Request-Email` | Signed-in email | `alice@contoso.com` |
| `X-Auth-Request-User` | Stable user ID (Entra object ID) | `Nuz3mgDggFnRUK5m...` |
| `X-Auth-Request-Preferred-Username` | Username for display | `alice@contoso.com` |
| `X-Auth-Request-Groups` | Comma-separated group names (only if enabled on the Entra app) | `eng,admins` |

In Express:

```js
app.get('/me', (req, res) => {
  res.json({ email: req.get('x-auth-request-email') });
});
```

These headers are only set in production. To simulate them locally:

```bash
curl -H 'X-Auth-Request-Email: me@example.com' http://localhost:8080/me
```

## Built-in routes

Out of the box this template ships an Express "teapot" app:

- `GET /` -> HTTP 418 with a teapot message and the signed-in user's email.
- `GET /me` -> JSON with the user's identity.
- `GET /healthz` -> `200 OK`, used by Kubernetes for liveness/readiness.

You can keep, replace, or extend any of these. The agent will replace `/` and `/me` to match your idea while leaving `/healthz` alone.

## Tearing down an app

```bash
kubectl delete namespace <repo-name>
az identity delete -g rg-aks-saba-eastus -n id-app-<repo-name>
```

DNS is wildcard, so removing the Kubernetes resources is enough to take the URL offline.

---

# Advanced

For experienced developers who want to skip the agent and work directly.

## What is in the box

- `src/` - Node.js + Express app. Multi-stage Dockerfile (`node:22-alpine`, non-root, read-only rootfs).
- `k8s/` - Deployment, Service, Ingress with the four NGINX `auth-*` annotations + cert-manager TLS. The Deployment also has an optional `PG*` env block that lights up only when `enable-database.sh` has been run. All manifests use `${APP_NAME}`, `${IMAGE}`, `${HOSTNAME}` placeholders that the workflow `envsubst`s at deploy time.
- `.github/workflows/deploy.yml` - OIDC `azure/login@v2` + `az acr build` + `kubectl apply`. Runs on push to `main`. Skips on the template repo itself.
- `scripts/bootstrap.sh` - One-shot per-repo cluster wiring (Azure identity, OIDC federation, role assignments, namespace, Actions variables). Idempotent.
- `scripts/enable-database.sh` - One-shot per-repo Postgres provisioning (managed role, Database CR, credentials Secret in both the postgres namespace and the app's namespace). Idempotent.
- `AGENTS.md` - Shared cluster context that any AI agent should read before doing anything in this repo.
- `.github/agents/app-builder.md` - The end-to-end agent for non-technical users.
- `docs/AGENT-PLAYBOOK.md` - Long-form phase scripts referenced by the agent.
- `docs/DATABASE.md` - Reference doc for the optional Postgres database.

## What `bootstrap.sh` does

Idempotent. Safe to re-run.

| Step | Action |
| ---- | ------ |
| 1 | Creates user-assigned managed identity `id-app-<repo>` in `rg-aks-saba-eastus`. |
| 2 | Federates that identity to GitHub OIDC for `repo:<owner>/<repo>:ref:refs/heads/main`. |
| 3 | Grants `AcrPush` on `acrsabaeastus`. |
| 4 | Grants `Azure Kubernetes Service Cluster User Role` on `aks-saba-eastus`. |
| 5 | Creates K8s namespace `<repo>` and a `RoleBinding` granting your identity `edit` rights only in that namespace. |
| 6 | Sets repo Actions Variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ACR_NAME`, `AKS_NAME`, `AKS_RG`, `APP_HOSTNAME`. No secrets. |

## Local dev

```bash
cd src
npm install
APP_NAME=local npm run dev
curl -i http://localhost:8080/      # 418
```

## Customizing manually

- Swap the app: replace `src/`. Keep `GET /healthz`.
- Different port: update `PORT` default in `src/index.js`, the `Dockerfile` `EXPOSE`, the deployment `containerPort`, and the service `targetPort` consistently.
- Custom hostname: `gh variable set APP_HOSTNAME --body "my-app.apps.saba.codes"`.
- Add a database: `./scripts/enable-database.sh`. See `docs/DATABASE.md` for the connection env vars and a recommended `pg` client wrapper.
- Extra K8s resources: drop more YAML into `k8s/`. Anything in that folder is `envsubst`'d (with `${APP_NAME}`, `${IMAGE}`, `${HOSTNAME}`) and `kubectl apply`'d.

## Constraints

- No long-lived Azure credentials anywhere. OIDC only.
- Each app has its own managed identity, scoped to its own K8s namespace.
- ACR is shared across all apps on this cluster.
- The Entra app registration is single-tenant; only members and guests of the cluster's Entra tenant can log in. Invite external collaborators with `az ad user invite`.

## License

MIT.
