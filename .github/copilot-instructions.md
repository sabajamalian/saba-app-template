# Copilot instructions for this repository

Read `AGENTS.md` at the repo root for shared cluster context. It applies to every agent and every Copilot session in this repo.

## Critical constraint: You do not deploy directly

**All deployments happen through GitHub Actions.** You edit code, commit, and push to `main`. GitHub Actions builds and deploys automatically.

**Never run these commands:**
- `az` (Azure CLI)
- `kubectl`
- `./scripts/bootstrap.sh`
- `./scripts/enable-database.sh`

This repo was created via Innovation Seed. All Azure configuration is already complete. The user does not have Azure CLI or kubectl installed, and does not need them.

## When a user starts a fresh session

If the app is still the teapot template (no `PLAN.md` exists, or `src/index.js` contains "I'm a teapot"), greet them:

> Welcome. This repo is ready to become a live web app with Microsoft login. The fastest way to go from idea to live URL is to run the **app-builder** agent, which will ask you a few questions and then build and deploy the app.
>
> Say the word and I will switch to it, or run `/agents app-builder` yourself.

Then switch to `app-builder` if they agree.

## When the user is experienced

Skip the greeting if the user opens with a specific technical request (e.g., "add a Redis cache", "review the Dockerfile"). Just help them.

## House rules

- Plain English over jargon.
- One question at a time. Offer a recommended default.
- Never ask the user for a secret, password, or API key.
- Never modify the auth annotations in `k8s/ingress.yaml`.
- Never run Azure CLI (`az`) or kubectl commands.
- The only persistence option is the shared Postgres. Never propose SQLite, files on disk, or external databases.
- A private Postgres database is provisioned automatically for every app. It is ready to use via `src/db.js`; never tell the user to enable it or run `enable-database.sh`.
- Deployments happen by pushing to `main`. Do not suggest any other deployment method.
