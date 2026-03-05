# Developer Platform (Backstage)

Internal Developer Platform built with [Backstage](https://backstage.io) for the `duynhlab` microservices ecosystem.

Provides a unified portal for service catalog, Flux GitOps-based deployment, Kubernetes monitoring, software templates, and TechDocs -- all driven by YAML configuration.

## Architecture

```mermaid
flowchart TD
    subgraph devWorkflow ["Developer Workflow"]
        DevPush["Dev pushes code"]
        CI["GitHub Actions CI\n(test, build, push image)"]
        Registry["ghcr.io/duynhne/*"]
        DevPush --> CI --> Registry
    end

    subgraph backstagePortal ["Backstage Portal (:7007)"]
        Catalog["Software Catalog"]
        FluxTab["Flux Tab\n(HelmRelease status, sync)"]
        K8sTab["Kubernetes Tab\n(pods, logs)"]
        DeployTemplate["Deploy Template\n(self-service CD)"]
        FluxRuntime["Flux Runtime Page"]
    end

    subgraph k8sCluster ["Kubernetes Cluster"]
        subgraph fluxSystem ["Flux Operator + Controllers"]
            FluxOp["Flux Operator"]
            SrcCtrl["source-controller"]
            HelmCtrl["helm-controller"]
        end
        subgraph apps ["Microservice HelmReleases"]
            HR["auth, user, product,\ncart, order, review,\nnotification, shipping, frontend"]
        end
        PG["PostgreSQL"]
    end

    subgraph github ["GitHub"]
        ServiceRepos["9 service repos\n(source code)"]
        HomelabRepo["homelab repo\n(GitOps manifests)"]
    end

    DeployTemplate -->|"Creates PR"| HomelabRepo
    SrcCtrl -->|"Watches"| HomelabRepo
    HelmCtrl -->|"Reconciles"| HR
    HelmCtrl -->|"Pulls images"| Registry
    Catalog -->|"catalog entities"| backstagePortal
    backstagePortal -->|"K8s API + RBAC"| k8sCluster
```

## Developer Deployment Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant BS as Backstage
    participant GH as GitHub
    participant Flux as Flux
    participant K8s as Cluster

    Note over Dev: CI built image v1.2.3
    Dev->>BS: Click "Deploy" in Catalog
    Dev->>BS: Select service, tag, environment
    BS->>GH: Create PR to homelab repo
    Note over GH: PR merged
    Flux->>GH: Detect change (1 min)
    Flux->>K8s: Reconcile HelmRelease
    Dev->>BS: See green status in Flux tab
```

## Prerequisites

- **Node.js** 22 or 24
- **Yarn** 4.4.1 (included via `.yarnrc.yml`)
- **Docker** (for building production image)
- **GitHub Personal Access Token** with `repo` scope

## Quick Start (Local Development)

```bash
# 1. Clone
git clone https://github.com/duynhlab/backstage.git
cd backstage

# 2. Set GitHub token
export GITHUB_TOKEN=ghp_your_token_here

# 3. Install dependencies
corepack enable
corepack yarn install

# 4. Start dev server (frontend :3000, backend :7007)
corepack yarn start
```

> **Linux Users**: If `yarn install` fails, prefix commands with `corepack` to ensure Yarn 4.x is used.

Open http://localhost:3000 in your browser. Local development uses **SQLite in-memory** database.

## Deploy to Kind Cluster (Production-like)

```bash
# One-command setup: Kind cluster + PostgreSQL + Flux Operator + Backstage
./deploy/overlays/kind/setup.sh
```

Or step by step -- see [deploy/README.md](deploy/README.md).

```bash
# Build and load Docker image
corepack yarn tsc
corepack yarn build:backend
corepack yarn build-image
kind load docker-image backstage --name backstage-dev

# Access Backstage
kubectl port-forward -n backstage svc/backstage 7007:7007
# Open http://localhost:7007
```

## Available Scripts

| Command | Description |
|---------|-------------|
| `corepack yarn start` | Start frontend + backend in development mode |
| `corepack yarn tsc` | TypeScript type check |
| `corepack yarn build:backend` | Build backend for production |
| `corepack yarn build:all` | Build all packages |
| `corepack yarn build-image` | Build Docker image (run `build:backend` first) |
| `corepack yarn test` | Run tests |
| `corepack yarn lint:all` | Lint all packages |
| `corepack yarn clean` | Clean build artifacts |

## Installed Plugins

| Plugin | Package | Purpose |
|--------|---------|---------|
| Software Catalog | `@backstage/plugin-catalog` | Service registry from catalog YAML |
| Kubernetes | `@backstage/plugin-kubernetes` | Pod status, logs, events per service |
| Flux | `@backstage-community/plugin-flux` | HelmRelease status, Sync/Suspend, OCI sources |
| Software Templates | `@backstage/plugin-scaffolder` | Create services + deploy via UI form |
| TechDocs | `@backstage/plugin-techdocs` | Docs rendered from markdown in service repos |
| Search | `@backstage/plugin-search` | Full-text search across catalog and docs |

## Project Structure

```
backstage/
├── app-config.yaml                 # Dev config (SQLite, localhost)
├── app-config.production.yaml      # Production config (PostgreSQL, K8s)
├── catalog/                        # Catalog entities (single-repo approach)
│   ├── systems/ecommerce.yaml      # System definition
│   ├── components/                 # 1 file per service (9 total)
│   │   ├── auth.yaml
│   │   ├── user.yaml
│   │   ├── product.yaml
│   │   ├── cart.yaml
│   │   ├── order.yaml
│   │   ├── review.yaml
│   │   ├── notification.yaml
│   │   ├── shipping.yaml
│   │   └── frontend.yaml
│   └── org/platform-team.yaml      # Group + User entities
├── templates/                      # Scaffolder templates
│   └── deploy-service/             # Dev self-service deploy template
├── packages/
│   ├── app/                        # Frontend (React)
│   │   └── src/
│   │       ├── App.tsx             # Routes (Flux runtime, deploy)
│   │       └── components/
│   │           ├── Root/Root.tsx   # Sidebar navigation
│   │           └── catalog/
│   │               └── EntityPage.tsx  # Entity tabs (K8s, Flux)
│   └── backend/                    # Backend (Node.js)
│       ├── src/index.ts            # Plugin registration
│       └── Dockerfile              # Production image
├── deploy/                         # Kubernetes deployment manifests
│   ├── overlays/kind/              # Kind cluster config + setup script
│   ├── base/                       # Backstage K8s resources (Kustomize base)
│   └── flux/                       # Flux Operator + RBAC
├── docs/                           # Documentation
│   └── flux-integration.md         # Dev team Flux guide
├── examples/                       # Backstage default examples
└── .github/workflows/ci.yml        # CI: build + push to GHCR
```

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_TOKEN` | Yes | GitHub PAT with `repo` scope |
| `POSTGRES_HOST` | Production | PostgreSQL host |
| `POSTGRES_PORT` | Production | PostgreSQL port (default: 5432) |
| `POSTGRES_USER` | Production | PostgreSQL user |
| `POSTGRES_PASSWORD` | Production | PostgreSQL password |

### Catalog Sources

All catalog entities live in `catalog/` (single-repo approach). Configured in `app-config.yaml` / `app-config.production.yaml`:

- **9 microservices**: individual YAML files in `catalog/components/`
- **System**: `catalog/systems/ecommerce.yaml`
- **Organization**: `catalog/org/platform-team.yaml`
- **Software Templates**: `templates/deploy-service/template.yaml`

Each component maps to a HelmRelease in `duynhlab/homelab` via `backstage.io/kubernetes-id` annotation.

### Flux Integration

See [docs/flux-integration.md](docs/flux-integration.md) for the full dev team guide including:
- How to add Kubernetes/Flux annotations to your service
- How to label HelmReleases for Backstage discovery
- How to use the Deploy Service template

## CI/CD

GitHub Actions workflow (`.github/workflows/ci.yml`) on push/PR to `main`:

1. `yarn install --immutable`
2. `yarn tsc` - Type check
3. `yarn build:backend` - Build backend
4. Build + push Docker image to `ghcr.io/duynhlab/backstage/backstage` (on merge to `main`)

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [duynhlab/homelab](https://github.com/duynhlab/homelab) | GitOps manifests (HelmReleases, infra, Flux config) |
| [duynhlab/auth-service](https://github.com/duynhlab/auth-service) | Auth microservice |
| [duynhlab/user-service](https://github.com/duynhlab/user-service) | User microservice |
| [duynhlab/product-service](https://github.com/duynhlab/product-service) | Product microservice |
| [duynhlab/cart-service](https://github.com/duynhlab/cart-service) | Cart microservice |
| [duynhlab/order-service](https://github.com/duynhlab/order-service) | Order microservice |
| [duynhlab/review-service](https://github.com/duynhlab/review-service) | Review microservice |
| [duynhlab/notification-service](https://github.com/duynhlab/notification-service) | Notification microservice |
| [duynhlab/shipping-service](https://github.com/duynhlab/shipping-service) | Shipping microservice |
| [duynhlab/frontend](https://github.com/duynhlab/frontend) | Frontend web application |
