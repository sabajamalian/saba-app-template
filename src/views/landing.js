'use strict';

function escape(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toUTCString();
}

function render(ctx) {
  const {
    appName,
    repoUrl,
    actionsUrl,
    hostname,
    email,
    preferredUsername,
    user,
    idea,
    creatorLogin,
    creatorAvatarUrl,
    createdAt,
  } = ctx;

  const greetName = preferredUsername || (email ? email.split('@')[0] : '') || 'friend';
  const ideaBlock = idea && idea.trim()
    ? `<p class="idea-text">${escape(idea)}</p>`
    : `<p class="idea-text idea-empty">No idea description was captured when this seed was planted. That's fine; tell Copilot what you want and start building.</p>`;

  const creatorBlock = creatorLogin
    ? `<div class="creator">
         ${creatorAvatarUrl ? `<img class="avatar" src="${escape(creatorAvatarUrl)}" alt="" width="32" height="32" />` : ''}
         <span>Planted by <a href="https://github.com/${escape(creatorLogin)}">@${escape(creatorLogin)}</a>${createdAt ? ` on <time datetime="${escape(createdAt)}">${escape(formatDate(createdAt))}</time>` : ''}</span>
       </div>`
    : '';

  const samplePrompt = idea && idea.trim()
    ? idea.trim()
    : `Build a small web app that ${appName.replace(/-/g, ' ')} can use.`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escape(appName)} - your idea is planted</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #0f1115;
      --panel: #171a21;
      --panel-2: #1f232c;
      --fg: #e6e8eb;
      --muted: #9aa3ad;
      --accent: #7ee787;
      --accent-2: #79c0ff;
      --border: #2a2f3a;
      --code-bg: #0b0d12;
    }
    @media (prefers-color-scheme: light) {
      :root {
        --bg: #f7f8fa;
        --panel: #ffffff;
        --panel-2: #f0f2f5;
        --fg: #1a1f2b;
        --muted: #5b6573;
        --accent: #1f883d;
        --accent-2: #0969da;
        --border: #d0d7de;
        --code-bg: #f6f8fa;
      }
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; }
    body {
      font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Ubuntu, sans-serif;
      background: var(--bg);
      color: var(--fg);
    }
    main {
      max-width: 760px;
      margin: 0 auto;
      padding: 48px 24px 96px;
    }
    header.hero { margin-bottom: 32px; }
    .seedling { font-size: 48px; line-height: 1; }
    h1 {
      font-size: 32px;
      line-height: 1.15;
      margin: 12px 0 8px;
      letter-spacing: -0.01em;
    }
    h1 .accent { color: var(--accent); }
    .lede { color: var(--muted); margin: 0; }
    section.card {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 20px 24px;
      margin: 20px 0;
    }
    section.card h2 {
      font-size: 18px;
      margin: 0 0 12px;
      letter-spacing: -0.005em;
    }
    section.card p { margin: 8px 0; }
    .idea-text {
      background: var(--panel-2);
      border-left: 3px solid var(--accent);
      padding: 12px 14px;
      border-radius: 6px;
      white-space: pre-wrap;
    }
    .idea-empty { border-left-color: var(--border); color: var(--muted); }
    .creator {
      display: flex;
      align-items: center;
      gap: 10px;
      color: var(--muted);
      font-size: 14px;
      margin-top: 12px;
    }
    .avatar { border-radius: 50%; }
    code, pre {
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Monaco, Consolas, monospace;
      font-size: 13px;
    }
    pre {
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 12px 14px;
      overflow-x: auto;
      margin: 8px 0;
    }
    code.inline {
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 4px;
      padding: 1px 6px;
    }
    ul { padding-left: 20px; margin: 8px 0; }
    li { margin: 4px 0; }
    a { color: var(--accent-2); }
    .you {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      background: var(--panel-2);
      border: 1px solid var(--border);
      border-radius: 999px;
      padding: 4px 12px;
      font-size: 13px;
      color: var(--muted);
    }
    .you strong { color: var(--fg); font-weight: 600; }
    footer {
      margin-top: 32px;
      color: var(--muted);
      font-size: 13px;
      display: flex;
      flex-wrap: wrap;
      gap: 12px 20px;
    }
    .pill {
      display: inline-block;
      font-size: 11px;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: var(--accent);
      border: 1px solid var(--accent);
      border-radius: 999px;
      padding: 2px 8px;
      margin-bottom: 8px;
    }
  </style>
</head>
<body>
  <main>
    <header class="hero">
      <div class="seedling" aria-hidden="true">&#127793;</div>
      <span class="pill">Innovation Seed</span>
      <h1>Your idea is <span class="accent">planted</span>, ${escape(greetName)}.</h1>
      <p class="lede">This is <code class="inline">${escape(appName)}</code>, freshly grown on the cluster. ${hostname ? `It's live at <a href="https://${escape(hostname)}">${escape(hostname)}</a>.` : ''}</p>
      ${email ? `<p class="you" style="margin-top:14px"><span>Signed in as</span> <strong>${escape(email)}</strong></p>` : ''}
    </header>

    <section class="card">
      <h2>Your idea</h2>
      ${ideaBlock}
      ${creatorBlock}
    </section>

    <section class="card">
      <h2>Iterate with GitHub Copilot</h2>
      <p>The fastest way to grow this seed into a real app is to open it in Copilot CLI and describe what you want.</p>
      <pre>gh repo clone ${escape(repoUrl ? repoUrl.replace(/^https?:\/\/github.com\//, '') : appName)}
cd ${escape(appName)}
copilot</pre>
      <p>Then say something like:</p>
      <pre>${escape(samplePrompt)}</pre>
      <p>Copilot will ask a few questions, write a plan, edit the code, and push to <code class="inline">main</code>. You don't need to touch Azure or Kubernetes.</p>
    </section>

    <section class="card">
      <h2>What just happened behind the scenes</h2>
      <p>When this repo was created, a GitHub Actions workflow (<code class="inline">.github/workflows/deploy.yml</code>) ran automatically and did all of this for you:</p>
      <ul>
        <li>Signed in to Azure with OIDC (no secrets stored anywhere).</li>
        <li>Built a container image with <code class="inline">az acr build</code> and pushed it to the shared registry.</li>
        <li>Fetched cluster credentials with <code class="inline">az aks get-credentials</code>.</li>
        <li>Rendered the manifests in <code class="inline">k8s/</code> and applied them with <code class="inline">kubectl apply</code>.</li>
        <li>Waited for the rollout to be healthy.</li>
      </ul>
      <p>The same workflow runs on every push to <code class="inline">main</code>. Typical end-to-end time: about two minutes.</p>
    </section>

    <section class="card">
      <h2>What you got for free</h2>
      <ul>
        <li><strong>Microsoft login</strong> at the front door. You're reading this page because the cluster already authenticated you and forwarded your identity in <code class="inline">X-Auth-Request-*</code> headers.</li>
        <li>A <strong>public HTTPS URL</strong> with a real certificate (managed by cert-manager).</li>
        <li>An <strong>isolated namespace</strong> and a <strong>per-app managed identity</strong> with only the rights it needs.</li>
        <li>An <strong>optional Postgres database</strong>. Ask Saba to enable it when your app needs to remember things.</li>
      </ul>
    </section>

    <footer>
      ${repoUrl ? `<a href="${escape(repoUrl)}">Repository</a>` : ''}
      ${actionsUrl ? `<a href="${escape(actionsUrl)}">GitHub Actions</a>` : ''}
      <a href="/me">/me</a>
      <a href="/healthz">/healthz</a>
      ${user ? `<span>You: <code class="inline">${escape(user)}</code></span>` : ''}
    </footer>
  </main>
</body>
</html>
`;
}

module.exports = { render, escape };
