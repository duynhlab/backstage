# Flux Integration Guide for Dev Team

This guide explains how Backstage integrates with Flux Operator to provide GitOps-based deployment visibility and self-service deploy for the duynhlab microservices ecosystem.

## How It Works

```mermaid
flowchart TD
    subgraph devWorkflow ["Developer Workflow"]
        DevPush["Dev pushes code\nto service repo"]
        CI["GitHub Actions CI\n(test, build, push image)"]
        Registry["Container Registry\n(ghcr.io/duynhne/*)"]
        DevPush --> CI --> Registry
    end

    subgraph backstagePortal ["Backstage Portal"]
        Login["Dev opens Backstage"]
        Catalog["Software Catalog\n(view all services)"]
        EntityPage["Service Detail Page"]
        FluxTab["Flux Tab\n(HelmRelease status, sync)"]
        K8sTab["Kubernetes Tab\n(pods, logs, events)"]
        DeployBtn["Deploy / Promote"]
        ScaffolderForm["Fill form:\n- Service\n- Image tag\n- Environment"]
        Login --> Catalog --> EntityPage
        EntityPage --> FluxTab
        EntityPage --> K8sTab
        EntityPage --> DeployBtn --> ScaffolderForm
    end

    subgraph gitopsFlow ["GitOps Flow"]
        PR["Scaffolder creates PR\nto homelab repo"]
        Review["PR Review / Auto-merge"]
        GitRepo["homelab repo"]
        ScaffolderForm --> PR --> Review --> GitRepo
    end

    subgraph k8sCluster ["Kubernetes Cluster"]
        FluxSrc["Flux source-controller"]
        FluxHelm["Flux helm-controller"]
        Pods["Updated Pods"]
        GitRepo -->|"Flux detects change"| FluxSrc
        FluxSrc --> FluxHelm --> Pods
    end

    Pods -->|"Status visible in\nBackstage"| FluxTab
```

## Deploy Sequence

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant BS as Backstage Portal
    participant GH as GitHub
    participant Flux as Flux Controllers
    participant K8s as Kubernetes

    Note over Dev: CI built ghcr.io/duynhne/auth-service/auth:v1.2.3

    Dev->>BS: Open auth in Catalog
    Dev->>BS: Click "Deploy New Version"
    Dev->>BS: Fill form (service, tag, env)
    BS->>GH: Create PR to homelab repo
    GH-->>Dev: PR link shown

    Note over GH: PR merged
    Flux->>GH: Detect change (polling 1m)
    Flux->>K8s: Reconcile HelmRelease
    K8s-->>Flux: Rolling update done

    Dev->>BS: Check Flux tab
    BS-->>Dev: Status: Ready, v1.2.3
```

## Setting Up Your Service

### Step 1: Catalog Entity

Each service has a catalog entity in `catalog/components/<service>.yaml` with these annotations:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: auth
  annotations:
    backstage.io/kubernetes-id: auth
    backstage.io/kubernetes-namespace: auth
    github.com/project-slug: duynhlab/auth-service
spec:
  type: service
  lifecycle: production
  owner: platform-team
  system: duynhlab-ecommerce
```

### Step 2: HelmRelease Labels

In `duynhlab/homelab/kubernetes/apps/auth.yaml`, the HelmRelease must have a matching label:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: auth
  namespace: auth
  labels:
    backstage.io/kubernetes-id: auth
spec:
  interval: 10m
  chartRef:
    kind: OCIRepository
    name: mop-chart-oci
    namespace: flux-system
  values:
    image:
      repository: ghcr.io/duynhne/auth-service/auth
      tag: latest
```

### How Matching Works

```mermaid
flowchart LR
    subgraph catalogEntity ["catalog/components/auth.yaml"]
        A["annotations:\n  backstage.io/kubernetes-id: auth"]
    end
    subgraph helmRelease ["HelmRelease"]
        B["labels:\n  backstage.io/kubernetes-id: auth"]
    end
    catalogEntity -->|"values must\nbe identical"| helmRelease
```

Backstage reads the annotation from the catalog entity, then queries the Kubernetes API for all Flux CRDs (HelmRelease, Kustomization, OCIRepository, etc.) that have a matching label. This is how the Flux tab shows the right resources for each service.

### Service Mapping

| Service | HelmRelease | Namespace | Image |
|---------|-------------|-----------|-------|
| auth | `auth` | auth | `ghcr.io/duynhne/auth-service/auth` |
| user | `user` | user | `ghcr.io/duynhne/user-service/user` |
| product | `product` | product | `ghcr.io/duynhne/product-service/product` |
| cart | `cart` | cart | `ghcr.io/duynhne/cart-service/cart` |
| order | `order` | order | `ghcr.io/duynhne/order-service/order` |
| review | `review` | review | `ghcr.io/duynhne/review-service/review` |
| notification | `notification` | notification | `ghcr.io/duynhne/notification-service/notification` |
| shipping | `shipping` | shipping | `ghcr.io/duynhne/shipping-service/shipping` |
| frontend | `frontend` | default | `ghcr.io/duynhne/frontend/frontend` |

All services use the shared Helm chart from `oci://ghcr.io/duyhenryer/charts/mop` (OCIRepository `mop-chart-oci`).

## Deploying a New Version

1. Open Backstage at `http://localhost:7007`
2. Navigate to your service in the **Software Catalog**
3. Click **Create...** in the sidebar
4. Select **Deploy Service** template
5. Fill in:
   - **Service Name**: select your service (auth, user, product, etc.)
   - **Image Tag**: the version to deploy (e.g. `v1.2.3`)
   - **Environment**: dev / staging / production
6. Click **Create**
7. Backstage creates a PR to the `duynhlab/homelab` repo
8. Once the PR is merged, Flux automatically deploys the new version
9. Check the **Flux tab** on your service page to see the status

## Monitoring Flux Status

### Entity Page - Flux Tab

Each service page in Backstage has a **Flux** tab showing:
- **HelmReleases**: deployment status, version, last reconciliation time
- **Kustomizations**: applied manifests status
- **Sources**: OCIRepository sync status
- **Sync button**: force immediate reconciliation
- **Suspend/Resume**: temporarily pause deployments

### Flux Runtime Page

Access `/flux-runtime` from the sidebar to see cluster-wide Flux status:
- All Flux controllers and their versions
- Global reconciliation status

## Troubleshooting

### Flux tab shows "No resources found"
- Verify `backstage.io/kubernetes-id` annotation exists in the catalog entity
- Verify the HelmRelease has a matching `backstage.io/kubernetes-id` label
- Check that Backstage ServiceAccount has RBAC permissions (`flux-view-flux-system`)

### HelmRelease shows "Failed"
- Check Flux logs: `kubectl -n flux-system logs deployment/helm-controller`
- Check the HelmRelease status: `kubectl -n <service> describe helmrelease <name>`
- Verify the Helm chart exists and image is pullable

### Sync button does not work
- Verify `backstage-flux-patch` ClusterRole and ClusterRoleBinding are applied
- Check that the Backstage ServiceAccount has patch permissions

### Cannot access Kubernetes tab
- Verify `kubernetes` section exists in `app-config.yaml` / `app-config.production.yaml`
- Check the cluster URL and authentication method
