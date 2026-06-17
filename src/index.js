const express = require('express');
const { render: renderLanding } = require('./views/landing');

const app = express();
const APP_NAME = process.env.APP_NAME || 'saba-app';
const PORT = parseInt(process.env.PORT || '8080', 10);

// Idea metadata, populated by the Innovation Seed orchestrator as repo variables
// and forwarded into the pod by the deploy workflow + k8s/deployment.yaml.
// Any missing value just makes the corresponding section degrade gracefully.
const IDEA_DESCRIPTION = process.env.IDEA_DESCRIPTION || '';
const IDEA_CREATOR_LOGIN = process.env.IDEA_CREATOR_LOGIN || '';
const IDEA_CREATOR_AVATAR_URL = process.env.IDEA_CREATOR_AVATAR_URL || '';
const IDEA_CREATED_AT = process.env.IDEA_CREATED_AT || '';
const IDEA_REPO_URL = process.env.IDEA_REPO_URL || '';
const APP_HOSTNAME = process.env.APP_HOSTNAME || '';

app.disable('x-powered-by');
app.set('trust proxy', true);

// Liveness/readiness for Kubernetes. Not behind auth (NGINX exempts /healthz at the ingress level).
app.get('/healthz', (_req, res) => {
  res.status(200).json({ status: 'ok', app: APP_NAME });
});

// Echo the trusted identity headers injected by oauth2-proxy + nginx auth_request.
// These headers are only present when the ingress is annotated with auth-* annotations
// AND the request has been authenticated through https://auth.apps.saba.codes.
app.get('/me', (req, res) => {
  res.status(200).json({
    app: APP_NAME,
    email: req.get('x-auth-request-email') || null,
    user: req.get('x-auth-request-user') || null,
    preferredUsername: req.get('x-auth-request-preferred-username') || null,
    groups: (req.get('x-auth-request-groups') || '')
      .split(',')
      .map(s => s.trim())
      .filter(Boolean),
  });
});

// Default route: a friendly "your idea is planted" landing page. Designed to be
// replaced by the user (with help from Copilot) as soon as they start building.
app.get('/', (req, res) => {
  const html = renderLanding({
    appName: APP_NAME,
    hostname: APP_HOSTNAME,
    repoUrl: IDEA_REPO_URL,
    actionsUrl: IDEA_REPO_URL ? `${IDEA_REPO_URL.replace(/\/$/, '')}/actions` : '',
    email: req.get('x-auth-request-email') || '',
    preferredUsername: req.get('x-auth-request-preferred-username') || '',
    user: req.get('x-auth-request-user') || '',
    idea: IDEA_DESCRIPTION,
    creatorLogin: IDEA_CREATOR_LOGIN,
    creatorAvatarUrl: IDEA_CREATOR_AVATAR_URL,
    createdAt: IDEA_CREATED_AT,
  });
  res.status(200).type('text/html; charset=utf-8').send(html);
});

app.listen(PORT, () => {
  console.log(`[${APP_NAME}] listening on :${PORT}`);
});
