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
        StgEnv["apps/staging/*"]
        ProdEnv["apps/{beta,prod-us,prod-eu}/*"]
        CatalogDir["catalog/*.yaml"]
    end

    subgraph mgmt ["kind-mgmt"]
        BS["Backstage :7007"]
        DB["CloudNativePG\nbackstage-db"]
        BS --> DB
    end
    subgraph devc ["kind-dev"]
        FluxD["Flux (dev)"]
        NS1["ns checkout-staging"]
        FluxD --> NS1
    end
    subgraph prodc ["kind-prod"]
        FluxP["Flux (prod)"]
        NS3["ns checkout-{beta,prod-us,prod-eu}"]
        FluxP --> NS3
    end

    Code --> Pipeline
    Pipeline -->|"auto-commit tag bump"| DevEnv
    Portal --> Onboard & Update
    Onboard -->|"PR: base + staging + catalog"| gitops
    Update -->|"PR: one env file"| gitops
    Catalog -->|"discover 1m"| CatalogDir
    FluxD -->|"sync clusters/dev (1m)"| gitops
    FluxP -->|"sync clusters/prod (1m)"| gitops
    StgEnv --> NS1
    ProdEnv --> NS3
    GHCR -->|"pull"| devc
    GHCR -->|"pull"| prodc
    BS -->|"agent tokens: workloads + Flux CRDs"| devc
    BS -->|"agent tokens"| prodc
```

**Review gate:** every PR to `duynhlab/gitops` requires DevOps/SRE approval
(CODEOWNERS + branch protection). The only exception is the CI dev-deploy lane,
which is Flux image automation committing tag bumps to `apps/staging` directly.

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
    Flux->>Git: image automation bumps apps/staging (auto)
    Flux->>K8s: reconcile → dev runs sha-X
    Dev->>Dev: verify in dev
    Dev->>Git: Backstage "Enable Environment" / "Promote Image" → PR
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

The whole stack — three Kind clusters: mgmt (Backstage + CNPG) and one per
environment, each running Flux Operator + FluxInstance syncing its own path in
[duynhlab/gitops](https://github.com/duynhlab/gitops) — is declared in
[`deploy/helmfile.yaml.gotmpl`](deploy/helmfile.yaml.gotmpl):

```bash
./deploy/setup.sh
# Open http://localhost:7007 (kind-mgmt maps NodePort 30007 → host 7007)
```

See [deploy/README.md](deploy/README.md) for details.

## Installed Plugins

| Plugin | Purpose |
|--------|---------|
| Software Catalog | Service registry — entities discovered from `duynhlab/gitops` `catalog/*.yaml` |
| Kubernetes | Pods/logs across the environment clusters (label selector `app.kubernetes.io/name=<svc>`) |
| Flux (`@backstage-community/plugin-flux`) | HelmRelease status per env, Sync/Suspend |
| GitHub Actions (`@backstage-community/plugin-github-actions`) | **CI/CD tab** — workflow runs of the repo in `github.com/project-slug` |
| Scaffolder | `onboard-service`, `update-env-var`, `enable-environment`, `promote-image` (PR-based self-service) |
| TechDocs, Search, Notifications | Docs, full-text search, signals |

### CI/CD tab (GitHub Actions)

The CI/CD tab activates for any entity with the `github.com/project-slug`
annotation (the onboarding template sets it). The plugin calls the GitHub API
as the viewer via an OAuth popup, which needs a **GitHub OAuth App**:

1. GitHub → org **duynhlab** → Settings → Developer settings → OAuth Apps → New:
   - Homepage URL: `http://localhost:7007`
   - Authorization callback URL: `http://localhost:7007/api/auth/github/handler/frame`
2. Export the credentials and redeploy:

```bash
export AUTH_GITHUB_CLIENT_ID=<client id>
export AUTH_GITHUB_CLIENT_SECRET=<client secret>
./deploy/setup.sh   # or: GITHUB_TOKEN=$(gh auth token) helmfile -f deploy/helmfile.yaml.gotmpl apply
```

Without the OAuth App the tab renders but the popup sign-in fails — everything
else keeps working (`auth.providers.github` is only loaded when the
credentials are present, via `app-config.github-auth.yaml`).

## Project Structure

```
backstage/
├── app-config.yaml                 # Dev config (SQLite, localhost)
├── app-config.production.yaml      # In-cluster config (PostgreSQL, K8s, provider)
├── catalog/
│   ├── systems/ecommerce.yaml      # System entity
│   └── org/platform-team.yaml      # Group + User entities
├── templates/
│   ├── onboard-service/            # New service → staging PR
│   ├── update-env-var/             # Surgical one-env-var PR
│   ├── enable-environment/         # Add beta/prod-us/prod-eu
│   └── promote-image/              # Re-tag us→eu (registry)
├── packages/app/                   # Frontend (React)
├── packages/backend/               # Backend + Dockerfile
├── deploy/
│   ├── helmfile.yaml.gotmpl        # Full stack: flux, cnpg, backstage-db, backstage
│   ├── kind-{mgmt,dev,prod}.yaml   # Three Kind clusters (mgmt maps NodePort 30007 → host 7007)
│   ├── setup.sh                    # One-command bootstrap
│   └── charts/                     # Local charts: backstage, backstage-db (CNPG)
└── docs/
    ├── onboarding.md               # Dev guide + DevOps review checklist
    └── environments.md             # staging/beta/prod-us/prod-eu model, promotion, rollback
```

## Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_TOKEN` | Yes | GitHub PAT with `repo` scope (scaffolder PRs + catalog discovery). `deploy/setup.sh` takes it from `gh auth token`. |
| `AUTH_GITHUB_CLIENT_ID` / `AUTH_GITHUB_CLIENT_SECRET` | Optional | GitHub OAuth App for the CI/CD tab popup — enables `githubAuth` in the chart when exported at helmfile time. |
| `POSTGRES_*` | In-cluster | Injected by the `backstage` chart from the CNPG `backstage-db-app` secret. |

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [duynhlab/gitops](https://github.com/duynhlab/gitops) | Source of truth for staging/beta/prod-us/prod-eu deployments — all self-service PRs land here |
| [duynhlab/checkout-service](https://github.com/duynhlab/checkout-service) | Checkout pricing API (Go) — the reference service on this platform |
| [duynhlab/helm-charts](https://github.com/duynhlab/helm-charts) | Shared `mop` service chart (OCI) |
| [duynhlab/gha-workflows](https://github.com/duynhlab/gha-workflows) | Reusable CI workflows (go-check, docker-build-go, trivy, cosign) |
