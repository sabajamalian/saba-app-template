#!/usr/bin/env bash
# scripts/enable-database.sh
#
# FALLBACK ONLY. Repos created through Innovation Seed get their database
# provisioned automatically at plant time, so you do not need this. Use this
# script only for repos created manually with "Use this template", or for
# operator tasks (password rotation). Requires Azure + kubectl access.
#
# Run ONCE per repo to add a private Postgres database to this app.
# Run AFTER scripts/bootstrap.sh. Idempotent - safe to re-run.
#
# What it does:
#   1. Generates a strong password (or reuses the existing one).
#   2. Creates the credentials Secret in the shared 'postgres' namespace.
#   3. Adds a managed role for this app to the shared CNPG Cluster.
#   4. Applies a per-app CNPG Database CR.
#   5. Mirrors the credentials Secret into this app's namespace, so the
#      Deployment's secretKeyRef lookups succeed without any cross-namespace
#      RBAC.
#   6. Sets repo Actions variable APP_DB_ENABLED=1 and writes a .db-enabled
#      marker file at the repo root so the agent and humans can tell.
#
# Requirements: gh, az (logged in to the cluster's tenant), kubectl with
# cluster admin or at least edit access on the 'postgres' namespace, jq, openssl.

set -euo pipefail

# ---- Cluster constants (mirror scripts/bootstrap.sh) ----
SUBSCRIPTION_ID="4aa6e4ed-23f8-4ccd-a09a-36527503ab04"
TENANT_ID="d0401efd-a66a-4265-88d8-7d7801dda24e"
AKS_RG="rg-aks-saba-eastus"
AKS_NAME="aks-saba-eastus"
PG_NAMESPACE="postgres"
PG_CLUSTER="shared-pg"
PG_HOST="shared-pg-pooler.postgres.svc.cluster.local"
PG_PORT="5432"

for cmd in gh az kubectl jq openssl; do
  command -v "$cmd" >/dev/null || { echo "$cmd required"; exit 1; }
done

REPO_JSON=$(gh repo view --json owner,name)
OWNER=$(echo "$REPO_JSON" | jq -r .owner.login)
REPO=$(echo  "$REPO_JSON" | jq -r .name)

# Postgres identifiers must be lowercase and use underscores.
SLUG=$(echo "$REPO" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
APP_DB="app_${SLUG}"
APP_USER="${SLUG}_user"
SECRET_NAME="${REPO}-db-credentials"
DB_CR_NAME="${REPO}"
APP_NAMESPACE="${REPO}"

echo "Enabling Postgres for ${OWNER}/${REPO}"
echo "  database: ${APP_DB}"
echo "  user:     ${APP_USER}"
echo "  host:     ${PG_HOST}"
echo

az account set --subscription "$SUBSCRIPTION_ID" >/dev/null

# Make sure we have cluster credentials.
kubectl get ns "$PG_NAMESPACE" >/dev/null 2>&1 || {
  echo "Refreshing AKS credentials..."
  az aks get-credentials -g "$AKS_RG" -n "$AKS_NAME" --overwrite-existing >/dev/null
}

# 1. Password
if kubectl -n "$PG_NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  PASSWORD=$(kubectl -n "$PG_NAMESPACE" get secret "$SECRET_NAME" -o jsonpath='{.data.password}' | base64 -d)
  echo "[1/6] Reusing existing password from secret ${PG_NAMESPACE}/${SECRET_NAME}"
else
  PASSWORD=$(openssl rand -hex 24)
  kubectl create secret generic "$SECRET_NAME" -n "$PG_NAMESPACE" \
    --type=kubernetes.io/basic-auth \
    --from-literal=username="$APP_USER" \
    --from-literal=password="$PASSWORD" >/dev/null
  echo "[1/6] Created secret ${PG_NAMESPACE}/${SECRET_NAME}"
fi

# 2. Patch managed.roles on the shared Cluster (idempotent merge).
echo "[2/6] Ensuring managed role ${APP_USER} on Cluster/${PG_CLUSTER}..."
EXISTING=$(kubectl -n "$PG_NAMESPACE" get cluster "$PG_CLUSTER" -o json | jq '.spec.managed.roles // []')
HAS_ROLE=$(echo "$EXISTING" | jq --arg name "$APP_USER" 'any(.name == $name)')
if [ "$HAS_ROLE" != "true" ]; then
  NEW_ROLES=$(echo "$EXISTING" | jq --arg name "$APP_USER" --arg sec "$SECRET_NAME" \
    '. + [{ name: $name, ensure: "present", login: true, passwordSecret: { name: $sec } }]')
  kubectl -n "$PG_NAMESPACE" patch cluster "$PG_CLUSTER" --type=merge \
    -p "{\"spec\":{\"managed\":{\"roles\":$NEW_ROLES}}}" >/dev/null
  echo "  added"
else
  echo "  already present"
fi

# 3. Database CR.
echo "[3/6] Applying Database/${DB_CR_NAME}..."
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: ${DB_CR_NAME}
  namespace: ${PG_NAMESPACE}
spec:
  name: ${APP_DB}
  owner: ${APP_USER}
  cluster:
    name: ${PG_CLUSTER}
EOF

# 4. Wait for the role and the database to be reconciled by CNPG.
echo "[4/6] Waiting for the database and role to become ready..."
for i in $(seq 1 60); do
  APPLIED=$(kubectl -n "$PG_NAMESPACE" get database "$DB_CR_NAME" -o jsonpath='{.status.applied}' 2>/dev/null || true)
  ROLE_OK=$(kubectl -n "$PG_NAMESPACE" get cluster "$PG_CLUSTER" -o json \
    | jq --arg n "$APP_USER" '(.status.managedRolesStatus.byStatus.reconciled // []) | any(. == $n)')
  if [ "$APPLIED" = "true" ] && [ "$ROLE_OK" = "true" ]; then
    echo "  ready"
    break
  fi
  sleep 3
done

# 5. Mirror credentials into the app's namespace so the deployment can mount them
#    without any cross-namespace RBAC.
echo "[5/6] Mirroring credentials into namespace '${APP_NAMESPACE}'..."
kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

DATABASE_URL="postgresql://${APP_USER}:${PASSWORD}@${PG_HOST}:${PG_PORT}/${APP_DB}?sslmode=require"

kubectl create secret generic "$SECRET_NAME" -n "$APP_NAMESPACE" \
  --type=Opaque \
  --from-literal=username="$APP_USER" \
  --from-literal=password="$PASSWORD" \
  --from-literal=database="$APP_DB" \
  --from-literal=host="$PG_HOST" \
  --from-literal=port="$PG_PORT" \
  --from-literal=sslmode="require" \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# 6. Mark repo as DB-enabled.
echo "[6/6] Recording repo state..."
gh variable set APP_DB_ENABLED --body "1" >/dev/null
cat > .db-enabled <<EOF
Provisioned via scripts/enable-database.sh on $(date -u +%FT%TZ)
database: ${APP_DB}
user:     ${APP_USER}
host:     ${PG_HOST}
EOF

cat <<EOF

Done. Your app now has a private Postgres database.

  Database: ${APP_DB}
  User:     ${APP_USER}
  Host:     ${PG_HOST}
  Port:     ${PG_PORT}
  SSL:      require
  Secret:   ${SECRET_NAME} (in namespace '${APP_NAMESPACE}')

The deployment in k8s/deployment.yaml is already wired to read these
credentials with optional secret references, so on your next push to main
your pods will pick up PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD,
PGSSLMODE, and DATABASE_URL automatically.

To inspect or query manually:
  kubectl exec -n ${PG_NAMESPACE} ${PG_CLUSTER}-1 -c postgres -- \\
    psql -U postgres -d ${APP_DB} -c '\\dt'

To rotate the password later:
  kubectl delete secret ${SECRET_NAME} -n ${PG_NAMESPACE}
  ./scripts/enable-database.sh    # regenerates and re-mirrors

To tear it down (destructive):
  kubectl delete database ${DB_CR_NAME} -n ${PG_NAMESPACE}
  kubectl exec -n ${PG_NAMESPACE} ${PG_CLUSTER}-1 -c postgres -- \\
    psql -U postgres -c "DROP DATABASE IF EXISTS ${APP_DB}" \\
                       -c "DROP ROLE IF EXISTS ${APP_USER}"
  kubectl delete secret ${SECRET_NAME} -n ${PG_NAMESPACE}
  kubectl delete secret ${SECRET_NAME} -n ${APP_NAMESPACE}
  # Then remove ${APP_USER} from Cluster.spec.managed.roles by editing
  # the Cluster resource manually.
EOF
