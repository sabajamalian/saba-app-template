# syntax=docker/dockerfile:1.7
FROM node:22-alpine AS deps
WORKDIR /app
COPY src/package.json ./package.json
# No --mount=type=cache: ACR Tasks builds without BuildKit enabled.
RUN npm install --omit=dev --no-audit --no-fund

FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
# Use a numeric UID so Kubernetes' runAsNonRoot can verify non-root identity
# without resolving /etc/passwd. UID 10001 is conventional for app users.
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
COPY --from=deps /app/node_modules ./node_modules
COPY src ./src
COPY src/package.json ./package.json
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
CMD ["node", "src/index.js"]
