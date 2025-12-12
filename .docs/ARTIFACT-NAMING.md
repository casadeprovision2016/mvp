# Container & Helm Naming Schema — Cotai

**Version**: 1.0  
**Date**: December 2025  
**Purpose**: Standardize naming conventions for container images, Helm charts, and related artifacts

---

## Overview

Cotai uses a consistent naming schema across all environments (dev, staging, production) to enable:
- **Reproducible builds**: Image tags based on git commit SHA
- **Version tracking**: Semantic versioning for releases
- **Multi-tenant isolation**: Environment-aware naming
- **Artifact traceability**: Link artifacts to source code and deployments

---

## Container Image Naming Schema

### Image Registry

```
REGISTRY = gcr.io/PROJECT_ID
```

Where `PROJECT_ID` is your GCP project (e.g., `cotai-prod`, `cotai-staging`).

### Image Repository (Naming Convention)

```
REGISTRY/cotai-SERVICE_NAME:TAG
```

#### Example

```
gcr.io/cotai-prod/cotai-auth-service:abc123def456
gcr.io/cotai-prod/cotai-edital-service:v1.2.3
gcr.io/cotai-prod/cotai-cotacao-service:main.20250101.001
```

### Service Names

Use **lowercase**, **alphanumeric + hyphens**, no underscores or dots:

| Service | Image Name |
|---------|-----------|
| Auth Service | `cotai-auth-service` |
| Edital (Tender) Service | `cotai-edital-service` |
| Cotação (Quotation) Service | `cotai-cotacao-service` |
| Notificação (Notification) Service | `cotai-notificacao-service` |
| Fornecedor (Vendor) Service | `cotai-fornecedor-service` |
| Extração (Extraction) Service | `cotai-extracao-service` |
| Estoque (Inventory) Service | `cotai-estoque-service` |
| Chat Service | `cotai-chat-service` |

### Tag Strategy

Tags identify a specific image and enable multiple versions:

#### 1. Development Builds (Ephemeral)

**Pattern**: `git-commit-sha`

```
TAG = $(git rev-parse --short HEAD)

# Example
cotai-auth-service:a1b2c3d4
```

**Usage**: 
- Local development builds
- CI builds before merge
- Dev cluster deployments (auto-recreate on each push)

**Retention**: 7 days (auto-cleanup)

#### 2. Release Tags (Production)

**Pattern**: `vMAJOR.MINOR.PATCH`

```
TAG = vMAJOR.MINOR.PATCH

# Examples
cotai-auth-service:v1.0.0
cotai-edital-service:v1.2.3
cotai-cotacao-service:v2.1.0
```

**Usage**:
- Published releases to production
- Pinned versions for stable deployments
- Rollback reference

**Retention**: Permanent (or policy-based, e.g., keep last 10 releases)

**Creation**:
```bash
# Tag in git (source of truth)
git tag -s -m "Release v1.2.3" v1.2.3

# Tag in artifact registry (automatic via CI)
docker tag cotai-auth-service:git-sha gcr.io/cotai-prod/cotai-auth-service:v1.2.3
docker push gcr.io/cotai-prod/cotai-auth-service:v1.2.3
```

#### 3. Semantic Tags (Convenience)

**Pattern**: `latest`, `stable`, `main`, `develop`

```
TAG = latest | stable | main | develop

# Examples (optional, use cautiously)
gcr.io/cotai-prod/cotai-auth-service:latest     # Latest commit on main
gcr.io/cotai-prod/cotai-auth-service:stable     # Latest release tag
```

**Usage**:
- CI/CD references (not recommended for production)
- Local testing convenience
- Branch tracking (e.g., `main`, `develop`)

**Caution**: Mutable tags can cause unexpected behavior. Prefer explicit version tags.

#### 4. Pre-release Tags (Optional)

**Pattern**: `vMAJOR.MINOR.PATCH-PRERELEASE`

```
TAG = vMAJOR.MINOR.PATCH-alpha.N
    | vMAJOR.MINOR.PATCH-beta.N
    | vMAJOR.MINOR.PATCH-rc.N

# Examples
cotai-auth-service:v1.2.0-alpha.1
cotai-edital-service:v1.2.0-beta.2
cotai-cotacao-service:v1.2.0-rc.1
```

**Usage**:
- Beta releases to staging
- Release candidates before production
- Feature preview for selected users

---

## Helm Chart Naming Schema

### Chart Directory Structure

```
charts/
├── cotai-auth-service/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml
│   ├── values-staging.yaml
│   ├── values-prod.yaml
│   └── templates/
├── cotai-edital-service/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml
│   ├── values-staging.yaml
│   ├── values-prod.yaml
│   └── templates/
└── [more services...]
```

### Chart Naming Convention

**Pattern**: `cotai-SERVICE_NAME`

```yaml
# Chart.yaml
name: cotai-auth-service
description: Cotai Authentication Service
version: 1.0.0          # Chart version (increment with chart changes)
appVersion: "1.0.0"     # Application version (matches image tag)
```

#### Chart Name Examples

| Service | Chart Name |
|---------|-----------|
| Auth Service | `cotai-auth-service` |
| Edital Service | `cotai-edital-service` |
| Cotação Service | `cotai-cotacao-service` |
| Notificação Service | `cotai-notificacao-service` |

### Chart Versioning

**Chart Version**: Increments independently of application version.

```yaml
version: MAJOR.MINOR.PATCH

# Examples
version: 1.0.0   # Initial chart release
version: 1.0.1   # Patch: fix readiness probe
version: 1.1.0   # Minor: add new config parameter
version: 2.0.0   # Major: breaking change (e.g., new dependency)
```

**App Version**: Matches the application (service) version.

```yaml
appVersion: "1.2.3"     # Matches docker image tag v1.2.3
```

### Chart Release Versioning (Optional)

For published Helm charts (in OCI registry or Helm repo):

```
REGISTRY/charts/cotai-SERVICE_NAME:vMAJOR.MINOR.PATCH

# Examples
gcr.io/cotai-prod/charts/cotai-auth-service:v1.0.0
oci://charts.cotai.io/cotai-edital-service:v1.2.3
```

---

## Kubernetes Resource Naming

### Deployment Names

**Pattern**: `cotai-SERVICE_NAME` or `SERVICE_NAME` (context-dependent)

```yaml
# deployment.yaml
metadata:
  name: cotai-auth-service
  namespace: default  # or environment-specific namespace
```

### Service Names

```yaml
# service.yaml
metadata:
  name: cotai-auth-service
  # Internal DNS: cotai-auth-service.default.svc.cluster.local
```

### Namespace Names

```
NAMESPACE = default | dev | staging | prod

# Example deployments
kubectl apply -f charts/cotai-auth-service/ -n dev
kubectl apply -f charts/cotai-auth-service/ -n staging
kubectl apply -f charts/cotai-auth-service/ -n prod
```

---

## Configuration Values Files

### Environment-Specific Values

```
values.yaml              # Default/shared values
values-dev.yaml          # Development overrides
values-staging.yaml      # Staging overrides
values-prod.yaml         # Production overrides
```

#### Example: values-prod.yaml

```yaml
# Production: High availability, resource limits, replicas
replicaCount: 3

image:
  repository: gcr.io/cotai-prod/cotai-auth-service
  tag: v1.2.3             # Pinned release version
  pullPolicy: IfNotPresent

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1024Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

podSecurityContext:
  runAsNonRoot: true
  fsReadOnlyRootFilesystem: true

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values:
                  - cotai-auth-service
          topologyKey: kubernetes.io/hostname
```

#### Example: values-dev.yaml

```yaml
# Development: Single replica, minimal resources
replicaCount: 1

image:
  repository: gcr.io/cotai-dev/cotai-auth-service
  tag: main               # Latest from main branch
  pullPolicy: Always

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 200m
    memory: 512Mi

autoscaling:
  enabled: false

podSecurityContext:
  runAsNonRoot: false
```

---

## CI/CD Pipeline Integration

### Build & Push Script

```bash
#!/bin/bash
# scripts/build_and_push.sh

set -euo pipefail

SERVICE=${1:-auth-service}
GIT_SHA=$(git rev-parse --short HEAD)
REGISTRY="gcr.io/cotai-prod"
IMAGE_NAME="cotai-${SERVICE}"

echo "[INFO] Building ${IMAGE_NAME}:${GIT_SHA}"

# Build
docker build \
  -t "${REGISTRY}/${IMAGE_NAME}:${GIT_SHA}" \
  -f "services/${SERVICE}/Dockerfile" \
  "services/${SERVICE}/"

# Push
docker push "${REGISTRY}/${IMAGE_NAME}:${GIT_SHA}"

# Tag release if on version tag
if [[ "${CI_COMMIT_TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "[INFO] Tagging release: ${CI_COMMIT_TAG}"
  docker tag "${REGISTRY}/${IMAGE_NAME}:${GIT_SHA}" "${REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_TAG}"
  docker push "${REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_TAG}"
fi

echo "[OK] Image pushed: ${REGISTRY}/${IMAGE_NAME}:${GIT_SHA}"
```

### Helm Deployment (CI/CD)

```bash
#!/bin/bash
# scripts/deploy.sh

set -euo pipefail

SERVICE=${1:-auth-service}
ENVIRONMENT=${2:-dev}
IMAGE_TAG=${3:-main}

CHART_PATH="charts/cotai-${SERVICE}"
VALUES_FILE="${CHART_PATH}/values-${ENVIRONMENT}.yaml"

echo "[INFO] Deploying ${SERVICE} to ${ENVIRONMENT}"

helm upgrade --install "cotai-${SERVICE}" "${CHART_PATH}" \
  -f "${VALUES_FILE}" \
  --namespace "${ENVIRONMENT}" \
  --create-namespace \
  --set "image.tag=${IMAGE_TAG}" \
  --wait

echo "[OK] Deployment complete"
```

### GitHub Actions Example

```yaml
# .github/workflows/auth-service.yml
name: Auth Service

on:
  push:
    branches: [main, develop]
    paths:
      - "services/auth-service/**"
      - ".github/workflows/auth-service.yml"
  pull_request:
    branches: [main, develop]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set image tag
        id: tag
        run: echo "TAG=$(git rev-parse --short HEAD)" >> $GITHUB_OUTPUT
      
      - name: Build image
        run: |
          docker build \
            -t gcr.io/cotai-prod/cotai-auth-service:${{ steps.tag.outputs.TAG }} \
            services/auth-service/
      
      - name: Push to registry
        run: |
          docker push gcr.io/cotai-prod/cotai-auth-service:${{ steps.tag.outputs.TAG }}
      
      - name: Deploy to dev
        if: github.ref == 'refs/heads/develop'
        run: |
          bash scripts/deploy.sh auth-service dev ${{ steps.tag.outputs.TAG }}
      
      - name: Create release tag
        if: startsWith(github.ref, 'refs/tags/v')
        run: |
          docker tag \
            gcr.io/cotai-prod/cotai-auth-service:${{ steps.tag.outputs.TAG }} \
            gcr.io/cotai-prod/cotai-auth-service:${GITHUB_REF#refs/tags/}
          docker push gcr.io/cotai-prod/cotai-auth-service:${GITHUB_REF#refs/tags/}
```

---

## Best Practices

### 1. Image Tagging

✅ **DO**:
- Use git commit SHA for dev/CI builds
- Use semantic versions (vX.Y.Z) for releases
- Tag before pushing: `docker tag source target`
- Include timestamp in metadata (LABEL in Dockerfile)

❌ **DON'T**:
- Use mutable tags in production (except for convenience tags like `latest`)
- Change image contents after tagging
- Use branch names as primary tags (ephemeral)

### 2. Chart Versioning

✅ **DO**:
- Increment chart version independently of app version
- Sync appVersion with image tag
- Use semantic versioning
- Document changes in CHANGELOG

❌ **DON'T**:
- Keep chart version = app version (confusing)
- Skip chart updates when helm templates change
- Use `latest` in production deployments

### 3. Registry Organization

✅ **DO**:
- Organize images by service: `PROJECT/cotai-SERVICE`
- Use consistent naming across all environments
- Clean up old dev images (retention policy: 7 days)
- Store charts in OCI registry (same as images)

❌ **DON'T**:
- Mix services in unnamed registries
- Use different naming in dev vs prod
- Keep all dev images forever (storage cost)

### 4. Configuration Management

✅ **DO**:
- Use separate `values-ENV.yaml` for each environment
- Override image.tag via command line (immutable)
- Store secrets in Vault/Secret Manager, not in values files
- Version control all non-secret configuration

❌ **DON'T**:
- Hardcode image tags in charts
- Store credentials in values files
- Use same config for dev and prod
- Modify charts for environment-specific behavior

---

## Troubleshooting

### Image Pull Failures

```bash
# Check image exists in registry
gcloud container images list --repository=gcr.io/cotai-prod | grep cotai-auth-service

# Check pull credentials
kubectl get secrets -n prod | grep docker
```

### Chart Validation

```bash
# Lint chart
helm lint charts/cotai-auth-service/

# Validate rendered templates
helm template cotai-auth-service charts/cotai-auth-service/ \
  -f charts/cotai-auth-service/values-prod.yaml \
  | kubeval

# Dry-run deployment
helm upgrade --install --dry-run cotai-auth-service charts/cotai-auth-service/ \
  -f charts/cotai-auth-service/values-prod.yaml \
  -n prod
```

---

## References

- [Semantic Versioning](https://semver.org/)
- [Helm Documentation](https://helm.sh/docs/)
- [Container Registry Best Practices](https://cloud.google.com/artifact-registry/docs)
- [Kubernetes Naming Conventions](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/)

---

**Last Updated**: December 2025  
**Maintained By**: Platform Engineering Team
