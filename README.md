# Developer Platform (Backstage)

Internal Developer Platform for the `duynhlab` ecosystem, built with
[Backstage](https://backstage.io). Developers onboard, update and promote
services themselves through software templates; **DevOps/SRE only review and
approve pull requests**. Flux applies whatever is on the gitops repo's `main`.

## Architecture

```mermaid
flowchart TD
    subgraph dev ["Developer"]
        Code["Push code to\ncheckout-service"]
        Portal["Use Backstage portal\n(:7007)"]
    end

    subgraph ci ["GitHub Actions (service repo)"]
        Pipeline["test · lint · gitleaks ·\ndocker build · trivy · cosign"]
        GHCR["ghcr.io image\n:sha-&lt;short&gt; (immutable)"]
        Pipeline --> GHCR
    end

    subgraph backstage ["Backstage"]
        Catalog["Software Catalog\n(auto-discovered from gitops)"]
        Onboard["Template: Onboard New Service"]
        Update["Template: Update / Promote Service"]
        K8sTab["Kubernetes + Flux tabs"]
    end

    subgraph gitops ["duynhlab/gitops (DevOps-owned, CODEOWNERS)"]
        DevEnv["apps/dev/*"]
        UatEnv["apps/uat/*"]
        ProdEnv["apps/prod/*"]
        CatalogDir["catalog/*.yaml"]
    end

    subgraph cluster ["Kind cluster"]
        Flux["Flux (operator-managed)"]
        NS1["ns checkout-dev"]
        NS2["ns checkout-uat"]
        NS3["ns checkout-prod"]
        DB["CloudNativePG\nbackstage-db"]
        BS["Backstage :7007"]
        BS --> DB
    end

    Code --> Pipeline
    Pipeline -->|"auto-commit tag bump"| DevEnv
    Portal --> Onboard & Update
    Onboard -->|"PR: base + 3 envs + catalog"| gitops
    Update -->|"PR: one env file"| gitops
    Catalog -->|"discover 1m"| CatalogDir
    Flux -->|"sync 1m"| gitops
    DevEnv --> NS1
    UatEnv --> NS2
    ProdEnv --> NS3
    GHCR -->|"pull"| cluster
```

**Review gate:** every PR to `duynhlab/gitops` requires DevOps/SRE approval
(CODEOWNERS + branch protection). The only exception is the CI dev-deploy lane,
which commits image-tag bumps to `apps/dev` directly.

## Delivery & promotion flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant CI as service CI
    participant Git as gitops repo
    participant Ops as DevOps/SRE
    participant Flux
    participant K8s as Cluster

    Dev->>CI: merge code PR to main
    CI->>CI: build image sha-X, scan, sign
    CI->>Git: commit apps/dev bump (auto)
    Flux->>K8s: reconcile → dev runs sha-X
    Dev->>Dev: verify in dev
    Dev->>Git: Backstage "Update/Promote" (env=uat, tag=sha-X) → PR
    Ops->>Git: review + merge
    Flux->>K8s: reconcile → uat runs sha-X
    Dev->>Git: same template (env=prod) → PR
    Ops->>Git: review + merge
    Flux->>K8s: reconcile → prod runs sha-X
```

See [docs/environments.md](docs/environments.md) for the environment model and
[docs/onboarding.md](docs/onboarding.md) for the step-by-step guide.

## Prerequisites

- **Node.js** 22 or 24, **Yarn** 4.4.1 (via `.yarnrc.yml`), **Docker**
- **Kind**, **kubectl**, **Helm v3+**, **helmfile v1+**
- **gh** CLI authenticated with an account that can open PRs against `duynhlab/gitops`

## Quick Start (local development)

```bash
export GITHUB_TOKEN=$(gh auth token)
corepack enable && corepack yarn install
corepack yarn start          # frontend :3000, backend :7007, SQLite in-memory
```

## Deploy to Kind

The whole stack — Flux Operator + FluxInstance (syncing
[duynhlab/gitops](https://github.com/duynhlab/gitops)), CloudNativePG, the
Backstage database (CNPG `Cluster`) and Backstage itself — is declared in
[`deploy/helmfile.yaml.gotmpl`](deploy/helmfile.yaml.gotmpl):

```bash
./deploy/setup.sh
# Open http://localhost:7007 (Kind maps NodePort 30007 → host 7007)
```

See [deploy/README.md](deploy/README.md) for details.

## Installed Plugins

| Plugin | Purpose |
|--------|---------|
| Software Catalog | Service registry — entities discovered from `duynhlab/gitops` `catalog/*.yaml` |
| Kubernetes | Pods/logs across all environments (label selector `app.kubernetes.io/name=<svc>`) |
| Flux (`@backstage-community/plugin-flux`) | HelmRelease status per env, Sync/Suspend |
| Scaffolder | `onboard-service`, `update-service` templates (PR-based self-service) |
| TechDocs, Search, Notifications | Docs, full-text search, signals |

## Project Structure

```
backstage/
├── app-config.yaml                 # Dev config (SQLite, localhost)
├── app-config.production.yaml      # In-cluster config (PostgreSQL, K8s, provider)
├── catalog/
│   ├── systems/ecommerce.yaml      # System entity
│   └── org/platform-team.yaml      # Group + User entities
├── templates/
│   ├── onboard-service/            # New service → PR (base + dev/uat/prod + catalog)
│   └── update-service/             # Update/promote one env → PR
├── packages/app/                   # Frontend (React)
├── packages/backend/               # Backend + Dockerfile
├── deploy/
│   ├── helmfile.yaml.gotmpl        # Full stack: flux, cnpg, backstage-db, backstage
│   ├── kind-config.yaml            # Kind cluster (NodePort 30007 → host 7007)
│   ├── setup.sh                    # One-command bootstrap
│   └── charts/                     # Local charts: backstage, backstage-db (CNPG)
└── docs/
    ├── onboarding.md               # Dev guide + DevOps review checklist
    └── environments.md             # dev/uat/prod model, promotion, rollback
```

## Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_TOKEN` | Yes | GitHub PAT with `repo` scope (scaffolder PRs + catalog discovery). `deploy/setup.sh` takes it from `gh auth token`. |
| `POSTGRES_*` | In-cluster | Injected by the `backstage` chart from the CNPG `backstage-db-app` secret. |

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [duynhlab/gitops](https://github.com/duynhlab/gitops) | Source of truth for dev/uat/prod deployments — all self-service PRs land here |
| [duynhlab/checkout-service](https://github.com/duynhlab/checkout-service) | Checkout pricing API (Go) — the reference service on this platform |
| [duynhlab/helm-charts](https://github.com/duynhlab/helm-charts) | Shared `mop` service chart (OCI) |
| [duynhlab/gha-workflows](https://github.com/duynhlab/gha-workflows) | Reusable CI workflows (go-check, docker-build-go, trivy, cosign) |
