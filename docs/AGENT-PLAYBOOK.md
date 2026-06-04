# Agent playbook

Reference companion to `.github/agents/app-builder.md`. The agent reads this file when it needs deeper guidance for a specific phase. Keeping the long-form scripts here makes the agent file scannable.

## Phase 0: Greet and orient

Run these checks first, in parallel, with a single tool call:

- `gh repo view --json name,owner,isTemplate` -> get the slug.
- `gh variable list 2>/dev/null` -> if `AZURE_CLIENT_ID` is present, bootstrap has already been run.
- `git status --porcelain` and `git log --oneline -5` -> have they edited anything yet?
- `grep -q "I'm a teapot" src/index.js && echo unchanged || echo modified` -> is the app still the template?

Decide entry point:

| Signal | Branch |
| ------ | ------ |
| Unchanged template, no bootstrap | Phase 1 (Discover). |
| Unchanged template, bootstrap done | Phase 1 but skip the bootstrap step in Phase 4. |
| App already modified, no `PLAN.md` | Ask "are you continuing previous work, or starting over?" before deciding. |
| `PLAN.md` exists | Read it; resume mid-flow. |

Open with this exact tone:

> Hi. I'm going to help you turn an idea into a live website. I'll ask a few short questions, then build and deploy it for you. You won't need to write any code. Ready?

## Phase 1: Discover

Ask one question at a time. Always include a recommended default in parentheses. Acknowledge the answer in one short sentence before asking the next question.

### Question script

1. **Idea.** "In one or two sentences, what would you like to build? (For example: a personal recipe notebook, a stand-up status board for my team, or a public sign-up form for a workshop.)" If they say "I don't know", offer the three examples and ask them to pick one.

2. **Audience.** "Who is going to use this? (Recommended: just you and a few people you invite.)" Choices to recognize: just me / small invited group / public-internet-facing-but-still-needs-Microsoft-login.

3. **Memory.** "Does the app need to remember information between visits? For example: does it save anything, or is it a calculator-style page that runs fresh each time? (Recommended: no, keep it simple. We can add storage later.)" If yes, follow up: "Roughly what kind of information? (Recommended: a small list of items, each with a few fields.)" If they need persistence, warn: "Adding storage means the app will only run as one copy at a time, which is fine for small things."

4. **Pages or actions.** "List the screens or actions you want in priority order. The first one is what people see when they open it." Capture as bullet list.

5. **URL.** "Your default web address will be `https://<repo-name>.apps.saba.codes`. Is that fine, or do you want a different name?" If they pick a different name, warn that DNS is wildcard so any name works, but it has to be lowercase, letters/digits/dashes, no spaces.

6. **Name.** "And what should we call the app inside the page (the title shown to visitors)?"

Keep notes in scratch state; do not write to disk yet.

## Phase 2: Plan

Write a `PLAN.md` at the repo root. Format:

```markdown
# <App title>

## What it is
<one paragraph in the user's words, cleaned up>

## Who uses it
<audience>

## URL
https://<host>.apps.saba.codes (Microsoft login required)

## Features
- <bullet 1>
- <bullet 2>
...

## Data model
<short list, or "Stateless. The app does not save anything between visits.">

## What I will do next
1. Replace the placeholder app with code for the features above.
2. Adjust the deployment config (mostly leave it alone).
3. Connect the repo to the cluster (one-time setup).
4. Push to main and wait for the deploy. About 2 to 3 minutes.
```

Show the plan to the user. Ask: "Does this look right? Any tweaks?" Do not advance until they confirm.

## Phase 3: Build

### Defaults

- Express + EJS templates (already in `package.json` if you add `ejs`). Static assets in `public/`.
- All pages render server-side. Use Tailwind via CDN if the user wants visual polish, otherwise plain CSS in `public/style.css`.
- Use `req.get('x-auth-request-email')` to identify the user. Provide a top-right "Signed in as <email>" banner on every page.
- For lists/forms (the common case): in-memory `Map` keyed by user email if "per-user" data, plain array if "shared" data. Switch to SQLite if user opted in (see persistence section).

### Persistence (only if user opted in)

1. Add `better-sqlite3` to `src/package.json`.
2. Add `apk add --no-cache build-base python3` line to a new `builder` stage in the Dockerfile (sqlite native build), then COPY built node_modules into the runtime stage.
3. Open the DB at `/data/app.db`. Create tables with `CREATE TABLE IF NOT EXISTS`.
4. Add `k8s/pvc.yaml`:
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: ${APP_NAME}-data
     namespace: ${APP_NAME}
   spec:
     accessModes: ["ReadWriteOnce"]
     resources:
       requests:
         storage: 1Gi
   ```
5. In `k8s/deployment.yaml`:
   - Set `replicas: 1` and `strategy: Recreate`.
   - Mount the PVC at `/data`.
   - Drop `readOnlyRootFilesystem: true` only if necessary; better to keep it true and mount `/data` as the only writable path.
6. Tell the user clearly: "Your data lives in a single 1 GB volume. If you ever delete the app, the data goes with it. Take backups by downloading from your app."

### Coding standards

- All routes use `async`/`await` with try/catch.
- HTML output is escaped (use EJS `<%= %>` not `<%- %>` unless you trust the source).
- No client-side JavaScript dependencies unless asked.
- Never write a login page. Auth is the cluster's job.
- After edits, run `node --check src/index.js` to syntax-check.

### Show progress

Print a short "What I changed" summary after editing:
```
Changed:
  src/index.js               (rewrote app with 3 routes)
  src/views/index.ejs        (new)
  src/package.json           (added ejs)
  k8s/deployment.yaml        (replicas 2 -> 1)
README.md updated.
```

## Phase 4: Ship

### Prerequisite checks

Run these in parallel and report any failures with exact fix commands:

- `gh auth status` -> if not logged in: "Please run `gh auth login` and pick GitHub.com -> HTTPS -> yes auth git -> login with browser. Then say 'continue'."
- `az account show --query tenantId -o tsv` -> compare to tenant ID. If wrong tenant or not logged in: "Please run `az login --tenant d0401efd-a66a-4265-88d8-7d7801dda24e` and say 'continue'."
- `kubectl get nodes 2>&1` -> if it fails: "I need cluster access. Run `az aks get-credentials -g rg-aks-saba-eastus -n aks-saba-eastus` and say 'continue'."
- `command -v jq && command -v envsubst` -> install via brew if missing.

### Bootstrap

If `gh variable list` does not include `AZURE_CLIENT_ID`:

```
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

The script is idempotent. Watch its output and translate the steps for the user ("creating an identity for your repo to talk to Azure...").

### Custom hostname

If the user picked a hostname other than the repo name:
```
gh variable set APP_HOSTNAME --body "<their-host>.apps.saba.codes"
```

### Commit and push

```
git add -A
git commit -m "Build <app title> from idea to deployable app"
git push origin main
```

Use a co-author trailer if available.

### Watch the deploy

```
gh run watch --exit-status
```

When the workflow goes green:
- Tell the user the URL.
- Remind them: "The first time you open it, you'll be asked to sign in with Microsoft. After that, it's instant."
- Offer next steps: "Want to add a feature? Just tell me what."

If the workflow fails: read `gh run view --log-failed`, find the actual error, translate it for the user, fix it, and re-push.

## Anti-patterns to avoid

- Long monologues. Keep messages under 6 lines unless presenting the plan.
- Asking for confirmation on every tiny step. Confirm at phase boundaries only.
- Surfacing raw stack traces or YAML to the user. Translate.
- Adding optional dependencies "in case". Only add what the agreed features need.
- Suggesting "you could also...". Stay focused on what they asked for.
