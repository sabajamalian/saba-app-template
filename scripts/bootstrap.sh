#!/usr/bin/env bash
# scripts/bootstrap.sh
#
# Run ONCE per new repo created from this template. Wires the repo into
# the shared AKS cluster so push-to-main deploys at https://<repo>.apps.saba.codes
#
# What it does (all idempotent):
#   1. Creates a per-app user-assigned managed identity (UAMI) in the cluster's RG.
#   2. Federates the UAMI to GitHub OIDC for THIS repo's main branch.
#   3. Grants the UAMI AcrPush on the shared ACR.
#   4. Grants the UAMI Azure Kubernetes Service Cluster User Role on the shared AKS.
#   5. Creates a Kubernetes namespace named after the repo and a RoleBinding so
#      the UAMI's principal has 'edit' rights ONLY in that namespace.
#   6. Sets repo Actions Variables (no secrets) so deploy.yml just works.
#
# Requirements: az (logged in to the cluster's tenant), gh (logged into github.com),
# kubectl (with credentials for the cluster), jq.

set -euo pipefail

# ---- Cluster constants. Update these once if you ever rebuild the cluster. ----
SUBSCRIPTION_ID="4aa6e4ed-23f8-4ccd-a09a-36527503ab04"
TENANT_ID="d0401efd-a66a-4265-88d8-7d7801dda24e"
AKS_RG="rg-aks-saba-eastus"
AKS_NAME="aks-saba-eastus"
ACR_NAME="acrsabaeastus"
BASE_DOMAIN="apps.saba.codes"
LOCATION="eastus"

# ---- Discover repo from gh CLI ----
command -v gh >/dev/null  || { echo "gh CLI required"; exit 1; }
command -v az >/dev/null  || { echo "az CLI required"; exit 1; }
command -v jq >/dev/null  || { echo "jq required"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl required"; exit 1; }

REPO_JSON=$(gh repo view --json owner,name,defaultBranchRef)
OWNER=$(echo "$REPO_JSON" | jq -r .owner.login)
REPO=$(echo  "$REPO_JSON" | jq -r .name)
BRANCH=$(echo "$REPO_JSON" | jq -r .defaultBranchRef.name)
APP_NAME="$REPO"
APP_HOST="${REPO}.${BASE_DOMAIN}"
UAMI_NAME="id-app-${REPO}"

echo "Bootstrapping ${OWNER}/${REPO}"
echo "  hostname: ${APP_HOST}"
echo "  branch:   ${BRANCH}"
echo "  uami:     ${UAMI_NAME}"
echo

# ---- Lock to the right subscription ----
az account set --subscription "$SUBSCRIPTION_ID"

# ---- 1. Create or fetch the UAMI ----
echo "[1/6] Ensuring UAMI ${UAMI_NAME}..."
UAMI_JSON=$(az identity show -g "$AKS_RG" -n "$UAMI_NAME" -o json 2>/dev/null \
  || az identity create -g "$AKS_RG" -n "$UAMI_NAME" -l "$LOCATION" -o json)
CLIENT_ID=$(echo  "$UAMI_JSON" | jq -r .clientId)
PRINCIPAL_ID=$(echo "$UAMI_JSON" | jq -r .principalId)
echo "  clientId=$CLIENT_ID"

# ---- 2. Federated credential for this repo's default branch ----
echo "[2/6] Federating GitHub OIDC for ${OWNER}/${REPO}@${BRANCH}..."
FED_NAME="gh-${OWNER}-${REPO}-${BRANCH}"
SUBJECT="repo:${OWNER}/${REPO}:ref:refs/heads/${BRANCH}"
if az identity federated-credential show -g "$AKS_RG" --identity-name "$UAMI_NAME" --name "$FED_NAME" >/dev/null 2>&1; then
  az identity federated-credential update -g "$AKS_RG" --identity-name "$UAMI_NAME" --name "$FED_NAME" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "$SUBJECT" \
    --audiences "api://AzureADTokenExchange" >/dev/null
else
  az identity federated-credential create -g "$AKS_RG" --identity-name "$UAMI_NAME" --name "$FED_NAME" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "$SUBJECT" \
    --audiences "api://AzureADTokenExchange" >/dev/null
fi

# ---- 3. ACR push role ----
echo "[3/6] Granting AcrPush on ${ACR_NAME}..."
ACR_ID=$(az acr show -n "$ACR_NAME" --query id -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role AcrPush --scope "$ACR_ID" >/dev/null 2>&1 || echo "  (already assigned)"

# ---- 4. AKS Cluster User role (lets the workflow run get-credentials) ----
echo "[4/6] Granting Azure Kubernetes Service Cluster User Role on ${AKS_NAME}..."
AKS_ID=$(az aks show -g "$AKS_RG" -n "$AKS_NAME" --query id -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Cluster User Role" --scope "$AKS_ID" >/dev/null 2>&1 || echo "  (already assigned)"

# ---- 5. K8s namespace + RoleBinding scoped to that namespace ----
echo "[5/6] Creating namespace and namespace-scoped RoleBinding..."
az aks get-credentials -g "$AKS_RG" -n "$AKS_NAME" --overwrite-existing >/dev/null

kubectl create namespace "$APP_NAME" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Bind the UAMI's principal (by objectId) to the built-in 'edit' role in the namespace.
# Works whether or not Azure RBAC for AKS is enabled - we use a Kubernetes-native binding.
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-deployer
  namespace: ${APP_NAME}
subjects:
  - kind: User
    name: ${PRINCIPAL_ID}
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
EOF

# ---- 6. Repo Actions Variables ----
echo "[6/6] Setting GitHub Actions repo variables..."
gh variable set AZURE_CLIENT_ID       --body "$CLIENT_ID"
gh variable set AZURE_TENANT_ID       --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
gh variable set ACR_NAME              --body "$ACR_NAME"
gh variable set AKS_NAME              --body "$AKS_NAME"
gh variable set AKS_RG                --body "$AKS_RG"
gh variable set APP_HOSTNAME          --body "$APP_HOST"

echo
echo "Done. Push to ${BRANCH} and your app will deploy at:"
echo "  https://${APP_HOST}"
echo
echo "After the first successful deploy, log in once with your Entra account; sessions"
echo "are shared across *.${BASE_DOMAIN} so other apps on the cluster require no re-auth."
