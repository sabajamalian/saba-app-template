# Agent playbook

Reference companion to `.github/agents/app-builder.md`. The agent reads this file for detailed phase guidance.

## Phase 0: Greet and orient

Run these checks in parallel:

```bash
gh repo view --json name,owner,isTemplate 2>/dev/null
git status --porcelain
git log --oneline -5
grep -q "I'm a teapot" src/index.js && echo "unchanged" || echo "modified"
[ -f PLAN.md ] && echo "PLAN_EXISTS" || echo "NO_PLAN"
```

Decide entry point:

| Signal | Action |
| ------ | ------ |
| Unchanged template, no PLAN.md | Start at Phase 1 (Discover). |
| App modified, no PLAN.md | Ask "are you continuing previous work, or starting over?" |
| PLAN.md exists | Read it and resume mid-flow. |

Open with:

> Hi. I am going to help you turn an idea into a live website. I will ask a few short questions, then build and deploy it for you. You will not need to write any code. Ready?

## Phase 1: Discover

Ask one question at a time. Include a recommended default. Acknowledge the answer before asking the next question.

### Questions

1. **Idea.** "In one or two sentences, what would you like to build?"

2. **Audience.** "Who is going to use this? (Recommended: just you and a few people you invite.)"

3. **Memory.** "Does the app need to remember information between visits? For example, does it save anything? (Recommended: yes, give the app a private database.)"

4. **Pages or actions.** "List the screens or actions you want in priority order. The first one is what people see when they open it."

5. **URL.** "Your default web address will be `https://<repo-name>.apps.saba.codes`. Is that fine, or do you want a different name?"

6. **Name.** "What should we call the app (the title shown to visitors)?"

Keep notes in memory. Do not write to disk yet.

## Phase 2: Plan

Write `PLAN.md` at the repo root:

```markdown
# <App title>

## What it is
<one paragraph in the user's words>

## Who uses it
<audience>

## URL
https://<host>.apps.saba.codes (Microsoft login required)

## Features
- <bullet 1>
- <bullet 2>
...

## Data model
<tables and columns, or "Stateless. The app does not save anything.">

## What happens next
1. Replace the placeholder app with code for these features.
2. Push to main.
3. GitHub Actions deploys automatically (about 2 minutes).
```

Show the plan. Ask: "Does this look right?" Do not advance until they confirm.

## Phase 3: Build

### Defaults

- Express + EJS templates. Static assets in `public/`.
- Server-side rendering. Tailwind via CDN for styling if needed.
- Use `req.get('x-auth-request-email')` to identify the user. Show "Signed in as <email>" on every page.
- For stateless apps: in-memory storage is fine.
- Every app has a private Postgres database by default. `pg` and `src/db.js` ship with the template.

### Persistence

A private Postgres database is provisioned automatically when the idea is planted, and the credentials are injected into the pod. There is nothing to enable.

If the user wants to save data:

1. In `src/index.js`, `const db = require('./db');` and call `db.migrate(...)` at startup with `CREATE TABLE IF NOT EXISTS ...`.
2. Use `db.query(text, params)` from routes.

It works on the first deploy. Never tell the user to ask Saba or to run `enable-database.sh`.

### After editing

Run `node --check src/index.js` to syntax-check.

Show a summary:
```
Changed:
  src/index.js               (rewrote with 3 routes)
  src/views/index.ejs        (new)
  src/package.json           (added ejs)
README.md updated.
```

## Phase 4: Ship

This is simple because the repo is already wired via Innovation Seed.

### Steps

1. **Commit:**
   ```bash
   git add -A
   git commit -m "Build <app title>"
   ```

2. **Push:**
   ```bash
   git push origin main
   ```

3. **Watch the deploy:**
   ```bash
   gh run watch --exit-status
   ```
   Tell the user it takes about 2 minutes.

4. **On success:** Give them the URL. Remind them they sign in with Microsoft once.

5. **On failure:** Read `gh run view --log-failed`, find the error, translate it, fix the code, and re-push.

### What NOT to do

- Do not run `./scripts/bootstrap.sh`. The repo is already configured.
- Do not run `./scripts/enable-database.sh`. The database is already provisioned, and you do not have kubectl access.
- Do not run any `az` or `kubectl` commands.

The database is ready for every app. You never need to enable it or ask anyone to.

## Anti-patterns

- Long monologues. Keep messages under 6 lines.
- Asking for confirmation on every tiny step.
- Surfacing raw stack traces or YAML.
- Adding dependencies "just in case".
- Suggesting "you could also..." Stay focused on what they asked for.
