#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTERS=(mgmt dev prod)

echo "=== duynhlab platform: mgmt + dev + prod (3 Kind clusters) ==="

# ── 1. Kind clusters ────────────────────────────────────────────────
for c in "${CLUSTERS[@]}"; do
  if kind get clusters 2>/dev/null | grep -q "^${c}$"; then
    echo "[1/5] Kind cluster '${c}' already exists, skipping."
  else
    echo "[1/5] Creating Kind cluster '${c}'..."
    kind create cluster --config "$SCRIPT_DIR/kind-${c}.yaml"
  fi
done

# ── 2. Backstage image (mgmt only) ──────────────────────────────────
cd "$PROJECT_ROOT"
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "[2/5] Building Backstage image..."
  corepack yarn install --immutable
  corepack yarn tsc
  corepack yarn build:backend
  corepack yarn build-image
else
  echo "[2/5] SKIP_BUILD=1 — using existing local 'backstage:latest' image."
fi
echo "Loading image into kind-mgmt..."
kind load docker-image backstage:latest --name mgmt

# ── 3. Environment tier: Flux + External Secrets + backstage-agent ──
export GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token)}"

# Git write credential for Flux image automation (staging auto-commit + the
# prod-* PR branches). Optional: without a GitHub App, image automation still
# reconciles but cannot push. Provide GITOPS_APP_ID / GITOPS_APP_INSTALLATION_ID
# / GITOPS_APP_PEM_PATH to enable it.
if [ -n "${GITOPS_APP_ID:-}" ]; then
  echo "[3/5] Creating Flux GitHub App secret on dev/prod..."
  for e in dev prod; do
    kubectl --context "kind-${e}" create namespace flux-system \
      --dry-run=client -o yaml | kubectl --context "kind-${e}" apply -f -
    # --export | apply so re-running setup.sh replaces the secret instead of
    # erroring on an existing one.
    flux --context "kind-${e}" create secret githubapp flux-system \
      --namespace flux-system \
      --app-id="${GITOPS_APP_ID}" \
      --app-installation-id="${GITOPS_APP_INSTALLATION_ID}" \
      --app-private-key="${GITOPS_APP_PEM_PATH}" \
      --export | kubectl --context "kind-${e}" apply -f -
  done
else
  echo "[3/5] GITOPS_APP_ID not set — Flux image automation will read-only "
  echo "      (no git push). Set the GitHub App vars to enable auto-commit."
fi

echo "[3/5] Installing Flux + External Secrets + backstage-agent on dev/prod..."
helmfile -f "$SCRIPT_DIR/helmfile.yaml.gotmpl" apply -l tier=env

# ── 4. Wire agent endpoints/tokens into the mgmt tier ───────────────
echo "[4/5] Extracting backstage-agent tokens..."
for e in dev prod; do
  IP=$(docker inspect "${e}-control-plane" --format '{{ index .NetworkSettings.Networks "kind" "IPAddress" }}')
  TOKEN=$(kubectl --context "kind-${e}" -n backstage-agent get secret backstage-agent-token \
    -o jsonpath='{.data.token}' | base64 -d)
  VAR_PREFIX=$(echo "$e" | tr '[:lower:]' '[:upper:]')
  export "K8S_${VAR_PREFIX}_URL=https://${IP}:6443"
  export "K8S_${VAR_PREFIX}_TOKEN=${TOKEN}"
  echo "  ${e}: https://${IP}:6443 (token: ${#TOKEN} chars)"
done

# ── 5. Mgmt tier: CNPG + Backstage ──────────────────────────────────
echo "[5/5] Installing CNPG + Backstage on mgmt..."
helmfile -f "$SCRIPT_DIR/helmfile.yaml.gotmpl" apply -l tier=mgmt

echo ""
echo "=== Setup complete ==="
echo "Backstage:  http://localhost:7007  (NodePort 30007 on kind-mgmt)"
echo "Flux dev:   kubectl --context kind-dev  -n flux-system get fluxinstance,kustomization"
echo "Flux prod:  kubectl --context kind-prod -n flux-system get fluxinstance,kustomization"
echo "Services:   kubectl --context kind-dev get helmrelease -A"
