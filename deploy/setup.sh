#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="backstage-dev"

echo "=== Kind + FluxCD + CNPG + Backstage: platform POC setup ==="

# ── 1. Kind cluster ─────────────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "[1/4] Kind cluster '${CLUSTER_NAME}' already exists, skipping."
else
  echo "[1/4] Creating Kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --config "$SCRIPT_DIR/kind-config.yaml"
fi
kubectl config use-context "kind-${CLUSTER_NAME}"

# ── 2. Backstage image ──────────────────────────────────────────────
cd "$PROJECT_ROOT"
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "[2/4] Building Backstage image..."
  corepack yarn install --immutable
  corepack yarn tsc
  corepack yarn build:backend
  corepack yarn build-image
else
  echo "[2/4] SKIP_BUILD=1 — using existing local 'backstage:latest' image."
fi

# ── 3. Load image into Kind ─────────────────────────────────────────
echo "[3/4] Loading image into Kind..."
kind load docker-image backstage:latest --name "${CLUSTER_NAME}"

# ── 4. Install everything via helmfile ──────────────────────────────
# flux-operator + flux-instance (syncs duynhlab/gitops-poc),
# cloudnative-pg + backstage-db (CNPG Cluster), backstage
echo "[4/4] Applying helmfile..."
export GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token)}"
helmfile -f "$SCRIPT_DIR/helmfile.yaml.gotmpl" apply

echo ""
echo "=== Setup complete ==="
echo "Backstage:  http://localhost:7007  (NodePort 30007 mapped by Kind)"
echo "Flux:       kubectl -n flux-system get fluxinstance,kustomization,gitrepository"
echo "Database:   kubectl -n backstage get cluster"
echo "Services:   kubectl get helmrelease -A"
