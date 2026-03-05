#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLUSTER_NAME="backstage-dev"

echo "=== Backstage + Flux Operator: Kind Cluster Setup ==="
echo ""

# ── 1. Create Kind cluster ──────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "[1/7] Kind cluster '${CLUSTER_NAME}' already exists, skipping."
else
  echo "[1/7] Creating Kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --config "$SCRIPT_DIR/kind-config.yaml"
fi
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
echo ""

# ── 2. Create namespaces ────────────────────────────────────────────
echo "[2/7] Creating namespaces..."
kubectl apply -f "$PROJECT_ROOT/deploy/base/namespace.yaml"
kubectl create namespace apps --dry-run=client -o yaml | kubectl apply -f -
echo ""

# ── 3. Deploy PostgreSQL ────────────────────────────────────────────
echo "[3/7] Deploying PostgreSQL..."
if helm status postgresql -n backstage &>/dev/null; then
  echo "  PostgreSQL already installed, skipping."
else
  helm install postgresql oci://registry-1.docker.io/bitnamicharts/postgresql \
    --namespace backstage \
    --set auth.postgresPassword=backstage \
    --set auth.database=backstage \
    --set primary.persistence.size=1Gi \
    --wait --timeout 120s
fi
echo ""

# ── 4. Install Flux Operator ────────────────────────────────────────
echo "[4/7] Installing Flux Operator..."
if helm status flux-operator -n flux-system &>/dev/null; then
  echo "  Flux Operator already installed, skipping."
else
  helm install flux-operator \
    oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
    --namespace flux-system --create-namespace \
    --wait --timeout 120s
fi
echo ""

# ── 5. Apply FluxInstance CRD ────────────────────────────────────────
echo "[5/7] Applying FluxInstance and RBAC..."
kubectl apply -f "$PROJECT_ROOT/deploy/flux/flux-instance.yaml"
kubectl apply -f "$PROJECT_ROOT/deploy/flux/backstage-rbac.yaml"
echo ""

# ── 6. Build and load Backstage image ───────────────────────────────
echo "[6/7] Building and loading Backstage Docker image..."
cd "$PROJECT_ROOT"
if [ ! -f packages/backend/dist/bundle.tar.gz ]; then
  echo "  Backend not built yet. Run: corepack yarn tsc && corepack yarn build:backend"
  echo "  Then run: corepack yarn build-image"
  echo "  Then run: kind load docker-image backstage --name ${CLUSTER_NAME}"
  echo "  Skipping image build (manual step required)."
else
  echo "  Backend already built. Loading image..."
  kind load docker-image backstage --name "${CLUSTER_NAME}" 2>/dev/null || \
    echo "  Image 'backstage' not found locally. Build it first with: corepack yarn build-image"
fi
echo ""

# ── 7. Deploy Backstage ─────────────────────────────────────────────
echo "[7/7] Deploying Backstage..."
if [ ! -f "$PROJECT_ROOT/deploy/base/secret.yaml" ]; then
  echo "  WARNING: deploy/base/secret.yaml not found!"
  echo "  Copy deploy/base/secret.yaml.example to deploy/base/secret.yaml"
  echo "  and fill in your GITHUB_TOKEN before deploying."
  echo ""
  echo "  Applying remaining manifests (deployment will wait for secret)..."
fi
kubectl apply -f "$PROJECT_ROOT/deploy/base/serviceaccount.yaml"
kubectl apply -f "$PROJECT_ROOT/deploy/base/service.yaml"
if [ -f "$PROJECT_ROOT/deploy/base/secret.yaml" ]; then
  kubectl apply -f "$PROJECT_ROOT/deploy/base/secret.yaml"
fi
kubectl apply -f "$PROJECT_ROOT/deploy/base/deployment.yaml"
echo ""

echo "=== Setup Complete ==="
echo ""
echo "Access Backstage:"
echo "  kubectl port-forward -n backstage svc/backstage 7007:7007"
echo "  Open http://localhost:7007"
echo ""
echo "Check Flux status:"
echo "  kubectl -n flux-system get fluxinstance"
echo "  kubectl -n flux-system get pods"
