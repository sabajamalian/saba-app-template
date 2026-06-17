# saba-app-template

A starting point for a web app that runs on a shared Kubernetes cluster with Microsoft login already wired in. Plant a seed, describe your idea, and a live URL comes out the other side.

## Quick start

1. Go to **[seed.apps.saba.codes](https://seed.apps.saba.codes)** and sign in with GitHub.
2. Pick a short, lowercase name for your app (like `recipe-notebook` or `team-standup`).
3. Click **Plant the seed**.

That's it. You now have a new repository under your GitHub account, fully configured to deploy. Your app will be live at:

```
https://<your-app-name>.apps.saba.codes
```

The first deploy lands on a friendly "your idea is planted" welcome page that shows your idea, who planted it, what just happened behind the scenes, and how to keep going with Copilot. That page lives in `src/index.js` and `src/views/landing.js`; replace it with your own app as soon as you're ready.

## Building your app

Open your new repository in GitHub Copilot CLI:

```bash
gh repo clone <your-username>/<your-app-name>
cd <your-app-name>
copilot
```

Then say something like:

> Build me a personal recipe notebook where I can save and search my favorite recipes.

The **app-builder** agent will ask a few questions, write a plan, build the code, and deploy it. The whole flow is conversational. You never need to touch Azure, Kubernetes, or deployment configs.

When you push changes to `main`, GitHub Actions automatically builds and deploys your app. No local tools required beyond `git` and optionally `copilot`.

## What you get

- A web app protected by **Microsoft login**. You did not write the login code; the cluster handles it.
- A **public HTTPS URL** with a real certificate.
- An **optional private database** (Postgres). The agent will offer to set it up if your app needs to save data.
- **Automatic deployments**: push to `main` and your app updates in about 2 minutes.
- Each app runs in its own isolated namespace with its own identity.

## How auth works

The cluster handles authentication. Your app receives trusted headers on every request:

| Header | What it is |
| ------ | ---------- |
| `X-Auth-Request-Email` | Signed-in email (e.g., `alice@contoso.com`) |
| `X-Auth-Request-User` | Stable user ID |
| `X-Auth-Request-Preferred-Username` | Display name |

In your code:

```js
app.get('/me', (req, res) => {
  res.json({ email: req.get('x-auth-request-email') });
});
```

Never write a login page. The cluster does that for you.

## Adding features later

Just open your repo, run `copilot`, and describe what you want:

- "Add a page that lists my notes sorted by date."
- "Make the homepage show the user's name in the corner."
- "Add an Atom feed at /feed."

The agent edits the code, pushes to `main`, and confirms when the new version is live.

## Running locally (optional)

If you want to test changes before pushing:

```bash
cd src
npm install
npm run dev
```

Your app runs at `http://localhost:8080`. The auth headers won't be present locally, so simulate them:

```bash
curl -H 'X-Auth-Request-Email: me@example.com' http://localhost:8080/me
```

## Deleting your app

Ask Saba to tear it down, or if you have cluster access:

```bash
kubectl delete namespace <app-name>
```

---

<details>
<summary><strong>Advanced: Manual setup (requires Azure access)</strong></summary>

This section is for users who have Azure CLI access and want to set up a repo manually instead of using Innovation Seed.

### Prerequisites

- `gh` CLI, logged in to GitHub
- `az` CLI, logged in to tenant `d0401efd-a66a-4265-88d8-7d7801dda24e`
- `kubectl` with cluster credentials
- `jq`

### Steps

1. Click **Use this template** on GitHub to create a new repo.
2. Clone it locally.
3. Run `./scripts/bootstrap.sh` to wire the repo to the cluster.
4. Push to `main`.

The bootstrap script creates a managed identity, federates it to GitHub OIDC, grants permissions, creates a namespace, and sets the Actions variables.

### Database (optional)

If your app needs persistence:

```bash
./scripts/enable-database.sh
```

This creates a private Postgres database and injects credentials into your app's environment.

</details>

## License

MIT.
