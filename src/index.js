const express = require('express');

const app = express();
const APP_NAME = process.env.APP_NAME || 'saba-app';
const PORT = parseInt(process.env.PORT || '8080', 10);

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

// Default route: HTTP 418 so it's obvious you've hit the template app.
app.get('/', (req, res) => {
  const email = req.get('x-auth-request-email');
  res.status(418).type('text/plain').send(
    `I'm a teapot.\n\n` +
    `app:   ${APP_NAME}\n` +
    `who:   ${email || '(unauthenticated - check ingress annotations)'}\n` +
    `try:   GET /me   -> identity headers\n` +
    `       GET /healthz -> liveness\n`
  );
});

app.listen(PORT, () => {
  console.log(`[${APP_NAME}] listening on :${PORT}`);
});
