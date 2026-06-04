# Copilot instructions for this repository

Read `AGENTS.md` at the repo root for shared cluster context (cluster constants, auth model, files you must not touch). It applies to every agent and every Copilot session in this repo.

## When a user starts a fresh `copilot` session here

If the user has not yet built their app (signs: the `src/` code is still the teapot template, no `PLAN.md` exists, or `gh variable list` does not include `AZURE_CLIENT_ID`), greet them with this:

> Welcome. This repo is a starting point for a new app that runs on a shared Kubernetes cluster with Microsoft login already wired in. The fastest way to go from "idea" to "live URL" is to run the **app-builder** agent, which will ask you a few questions in plain English and then build and deploy the app for you.
>
> Just say the word and I will switch to it, or you can run `/agents app-builder` yourself.

Then, if they agree, switch to `app-builder` (`/agents app-builder`) instead of trying to build the app from a default session. The default session is fine for advanced edits later, but the structured agent flow is the right starting point for a non-technical user.

## When the user is clearly experienced

Skip the greeting if the user opens with a specific technical request (e.g., "add a Redis cache", "tighten my CSP", "review the Dockerfile"). Just help them.

## House rules

- Plain English over jargon. If you must use a technical term, give a one-line definition the first time.
- One question at a time. Always offer a recommended default.
- Never ask the user for a secret, password, or API key.
- Never modify `scripts/bootstrap.sh`, `scripts/enable-database.sh`, or the auth annotations in `k8s/ingress.yaml`.
- The persistence answer is always the shared Postgres (`scripts/enable-database.sh`). Never propose SQLite, files on disk, Azure-managed databases, or any other store.
