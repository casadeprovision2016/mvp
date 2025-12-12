# CI/CD Guidelines — Cotai

**Versão**: 1.0  
**Data**: Dezembro 2025

---

## 1. Visão Geral do Pipeline

```
Developer Push → GitHub
        ↓
  .github/workflows/ci.yml
        ↓
  ┌─────────────────────────────────┐
  │  LINT & BUILD GATES             │
  │  - Proto lint (buf)             │
  │  - Code format (gofmt, spotbugs)│
  │  - Dependency scan (Snyk)       │
  │  - Unit tests (coverage > 80%)  │
  └─────────────────────────────────┘
        ↓
  ┌─────────────────────────────────┐
  │  BUILD & SECURITY GATES         │
  │  - Docker build                 │
  │  - Container scan (Trivy)       │
  │  - SAST (SonarQube)             │
  └─────────────────────────────────┘
        ↓
  ┌─────────────────────────────────┐
  │  REGISTRY & DEPLOYMENT          │
  │  - Push para Artifact Registry  │
  │  - Helm chart lint              │
  │  - Deploy staging (Blue/Green)  │
  │  - Integration tests (staging)  │
  └─────────────────────────────────┘
        ↓
  ┌─────────────────────────────────┐
  │  PRODUCTION (Manual Approval)   │
  │  - Deploy production (Canário)  │
  │  - Smoke tests                  │
  │  - Rollback ready               │
  └─────────────────────────────────┘
```

---

## 2. Lint & Validation Gates

### 2.1 Proto Files (buf)

**Quando**: Qualquer alteração em arquivos `.proto`.

```bash
# Lint: verificar estilo, imports, etc
buf lint proto/

# Breaking changes: garantir compatibilidade backward
buf breaking --against .

# Format: auto-format
buf format proto/ --write
```

**CI Step**:

```yaml
- name: Proto Lint
  run: |
    buf lint proto/
    buf breaking --against .
```

### 2.2 Go Code

**Golangci-lint** (múltiplos linters):

```bash
golangci-lint run ./...
```

**Configuração** (`.golangci.yml`):

```yaml
linters:
  enable:
    - gofmt
    - goimports
    - govet
    - ineffassign
    - deadcode
    - unused
    - gosimple
    - staticcheck
    - misspell

issues:
  exclude-rules:
    - path: _test\.go$
      linters:
        - gocyclo
```

### 2.3 Java Code

**Checkstyle + SpotBugs + PMD**:

```gradle
// build.gradle
plugins {
  id 'checkstyle'
  id 'com.github.spotbugs' version '6.0.7'
  id 'pmd'
}

checkstyle {
  configFile = file("${rootDir}/config/checkstyle.xml")
}

spotbugs {
  spotbugsVersion = '4.7.3'
}

pmd {
  toolVersion = '6.54.0'
}

tasks.named('check') {
  dependsOn 'checkstyleMain', 'spotbugsMain', 'pmdMain'
}
```

**CI Step**:

```yaml
- name: Java Quality Checks
  run: ./gradlew check
```

### 2.4 Dependency Scanning (Snyk)

```bash
# Scan dependencies for vulnerabilities
snyk test --file=go.mod --severity-threshold=high
snyk test --file=build.gradle --severity-threshold=high
```

**Falar com**: Infra team para Snyk API token.

---

## 3. Build Gates

### 3.1 Unit Tests

**Cobertura mínima**: 80%.

**Go**:

```bash
go test -v -coverprofile=coverage.out ./...
go tool cover -func=coverage.out | tail -1
# Output: total: (coverage) of statements
# Falha se < 80%
```

**Java**:

```gradle
jacocoTestReport {
  afterEvaluate {
    classDirectories.setFrom(files(classDirectories.files.collect {
      fileTree(dir: it, exclude: [
        '**/config/**',
        '**/dto/**'
      ])
    }))
  }
}

tasks.jacocoTestCoverageVerification {
  violationRules {
    rule {
      element = 'PACKAGE'
      excludes = ['**.config', '**.dto']
      limit {
        counter = 'LINE'
        value = 'COVEREDRATIO'
        minimum = 0.80
      }
    }
  }
}
```

### 3.2 Docker Build

```dockerfile
# Dockerfile (multi-stage)
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -o cotacao-service ./cmd/main.go

FROM alpine:3.18
RUN apk --no-cache add ca-certificates
COPY --from=builder /app/cotacao-service /usr/local/bin/
EXPOSE 8080
CMD ["cotacao-service"]
```

**CI Step**:

```yaml
- name: Build Docker Image
  run: |
    docker build -t ${{ env.REGISTRY }}/cotacao-service:${{ github.sha }} .
    
- name: Push to Artifact Registry
  run: |
    docker push ${{ env.REGISTRY }}/cotacao-service:${{ github.sha }}
```

### 3.3 Container Scan (Trivy)

```bash
# Scan image for vulnerabilities
trivy image --severity HIGH,CRITICAL \
  ${REGISTRY}/cotacao-service:${GIT_SHA}

# Falha se encontrar HIGH/CRITICAL
```

---

## 4. Helm Chart Validation

### 4.1 Helm Lint

```bash
# Validar sintaxe do Helm chart
helm lint charts/cotacao-service/

# Output:
# 1 chart(s) linted, 0 chart(s) failed
```

### 4.2 kubeval

```bash
# Validar manifests contra Kubernetes schema
kubeval charts/cotacao-service/templates/*.yaml

# Output:
# charts/cotacao-service/templates/deployment.yaml: valid
```

### 4.3 Chart Testing (ct)

```bash
# Lint + install test em kind cluster
ct lint --chart-dirs charts/

ct install --chart-dirs charts/ \
  --helm-extra-args="--values charts/cotacao-service/values-test.yaml"
```

---

## 5. Deploy Stages

### 5.1 Deploy Staging (Automated)

Após sucesso de todos os gates, deploy automático em staging com **Blue/Green**:

```yaml
- name: Deploy Staging
  run: |
    helm upgrade --install cotacao-service-staging \
      charts/cotacao-service/ \
      --namespace staging \
      --values charts/cotacao-service/values-staging.yaml \
      --set image.tag=${{ github.sha }}
    
    # Health check
    kubectl rollout status deployment/cotacao-service-staging -n staging --timeout=5m
```

### 5.2 Integration Tests (Staging)

```yaml
- name: Integration Tests
  run: |
    # Aguardar pods estarem ready
    kubectl wait --for=condition=ready pod -l app=cotacao-service -n staging --timeout=2m
    
    # Executar testes
    ./scripts/integration-tests.sh staging
```

### 5.3 Deploy Production (Manual Gate)

```yaml
- name: Approval Gate
  uses: trstringer/manual-approval@v1
  with:
    secret: ${{ secrets.GITHUB_TOKEN }}
    approvers: devops-team,eng-leads
    issue-title: "Deploy to Production: cotacao-service"

- name: Deploy Production (Canary)
  run: |
    # 10% de tráfego para nova versão
    helm upgrade cotacao-service \
      charts/cotacao-service/ \
      --namespace production \
      --values charts/cotacao-service/values-prod.yaml \
      --set image.tag=${{ github.sha }} \
      --set istio.canary.weight=10
    
    # Monitor por 10 minutos
    ./scripts/monitor-canary.sh 10
    
    # Se OK, 100%
    helm upgrade cotacao-service \
      charts/cotacao-service/ \
      --set istio.canary.weight=100
```

---

## 6. Exemplo: Workflow Completo (GitHub Actions)

```yaml
# .github/workflows/ci.yml
name: CI/CD Pipeline

on:
  push:
    branches: [main, develop]
    paths:
      - 'services/cotacao-service/**'
      - 'proto/**'
      - '.github/workflows/ci.yml'
  pull_request:
    branches: [main, develop]

env:
  REGISTRY: us-central1-docker.pkg.dev
  GCP_PROJECT: cotai-prod
  SERVICE_NAME: cotacao-service

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      
      - name: Proto Lint
        run: |
          go install github.com/bufbuild/buf/cmd/buf@latest
          buf lint proto/
          buf breaking --against .
      
      - name: Go Lint
        run: |
          go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
          golangci-lint run ./...
      
      - name: Snyk Scan
        run: |
          npm install -g snyk
          snyk test --file=go.mod --severity-threshold=high

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      
      - name: Unit Tests
        run: |
          go test -v -race -coverprofile=coverage.out ./...
          
          # Check coverage
          COVERAGE=$(go tool cover -func=coverage.out | tail -1 | awk '{print $3}' | cut -d'%' -f1)
          if (( $(echo "$COVERAGE < 80" | bc -l) )); then
            echo "Coverage $COVERAGE% is below 80%"
            exit 1
          fi
      
      - name: Upload Coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.out

  build:
    needs: [lint, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}
      
      - name: Setup Cloud SDK
        uses: google-github-actions/setup-gcloud@v1
      
      - name: Build Docker Image
        run: |
          docker build -t ${{ env.REGISTRY }}/${{ env.GCP_PROJECT }}/${{ env.SERVICE_NAME }}:${{ github.sha }} .
      
      - name: Push to Artifact Registry
        run: |
          gcloud auth configure-docker ${{ env.REGISTRY }}
          docker push ${{ env.REGISTRY }}/${{ env.GCP_PROJECT }}/${{ env.SERVICE_NAME }}:${{ github.sha }}
      
      - name: Container Scan (Trivy)
        run: |
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:latest image --severity HIGH,CRITICAL \
            ${{ env.REGISTRY }}/${{ env.GCP_PROJECT }}/${{ env.SERVICE_NAME }}:${{ github.sha }}

  helm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Helm Lint
        run: |
          helm lint charts/${{ env.SERVICE_NAME }}/
      
      - name: Kubeval
        run: |
          docker run --rm -v $(pwd):/workspace:ro \
            instrumenta/kubeval:latest \
            charts/${{ env.SERVICE_NAME }}/templates/*.yaml

  deploy-staging:
    needs: [build, helm]
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/develop'
    steps:
      - uses: actions/checkout@v4
      
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}
      
      - name: Setup Cloud SDK
        uses: google-github-actions/setup-gcloud@v1
      
      - name: Get GKE Credentials
        run: |
          gcloud container clusters get-credentials staging --zone us-central1-a
      
      - name: Deploy to Staging
        run: |
          helm upgrade --install ${{ env.SERVICE_NAME }}-staging \
            charts/${{ env.SERVICE_NAME }}/ \
            --namespace staging \
            --create-namespace \
            --values charts/${{ env.SERVICE_NAME }}/values-staging.yaml \
            --set image.tag=${{ github.sha }} \
            --wait --timeout 5m
      
      - name: Integration Tests
        run: |
          ./scripts/integration-tests.sh staging

  deploy-prod:
    needs: deploy-staging
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    environment:
      name: production
    steps:
      - uses: actions/checkout@v4
      
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}
      
      - name: Setup Cloud SDK
        uses: google-github-actions/setup-gcloud@v1
      
      - name: Get GKE Credentials
        run: |
          gcloud container clusters get-credentials production --zone us-central1-a
      
      - name: Deploy to Production (Canary)
        run: |
          helm upgrade ${{ env.SERVICE_NAME }} \
            charts/${{ env.SERVICE_NAME }}/ \
            --namespace production \
            --values charts/${{ env.SERVICE_NAME }}/values-prod.yaml \
            --set image.tag=${{ github.sha }} \
            --set istio.canary.weight=10 \
            --wait --timeout 5m
      
      - name: Monitor Canary (10 min)
        run: ./scripts/monitor-canary.sh 10
      
      - name: Complete Canary (100%)
        run: |
          helm upgrade ${{ env.SERVICE_NAME }} \
            charts/${{ env.SERVICE_NAME }}/ \
            --set istio.canary.weight=100
```

---

## 7. Secrets Management

### 7.1 GitHub Secrets (Staging/CI)

```
SNYK_TOKEN          — Snyk API token
GCP_SA_KEY          — Google Cloud Service Account JSON
SLACK_WEBHOOK_URL   — Slack notifications
```

### 7.2 Vault (Production)

Para secrets sensíveis (DB password, API keys), usar **HashiCorp Vault**:

```hcl
# Vault policy
path "secret/data/cotacao-service/*" {
  capabilities = ["read"]
}
```

**Acesso no pod**:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cotacao-service
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/agent-inject-secret-database: "secret/data/cotacao-service/db"
    vault.hashicorp.com/role: "cotacao-service"
```

---

## 8. Monitoring & Alerts

### 8.1 CI Pipeline Status

```yaml
- name: Notify Slack (Failure)
  if: failure()
  run: |
    curl -X POST ${{ secrets.SLACK_WEBHOOK_URL }} \
      -d '{
        "text": "❌ CI Pipeline failed for ${{ env.SERVICE_NAME }}",
        "attachments": [{
          "color": "danger",
          "fields": [{
            "title": "Commit",
            "value": "${{ github.sha }}"
          }, {
            "title": "Author",
            "value": "${{ github.actor }}"
          }]
        }]
      }'
```

### 8.2 Deployment Status

```yaml
- name: Notify Slack (Success)
  if: success()
  run: |
    curl -X POST ${{ secrets.SLACK_WEBHOOK_URL }} \
      -d '{
        "text": "✅ ${{ env.SERVICE_NAME }} deployed to production"
      }'
```

---

## 9. Best Practices Checklist

- [ ] **Proto-first**: Sempre update `.proto` antes de código.
- [ ] **Coverage**: Manter > 80% test coverage.
- [ ] **Immutable tags**: Use git SHA ou semver, nunca "latest".
- [ ] **Helm values**: Sempre override via values-staging.yaml, values-prod.yaml.
- [ ] **Canary deploys**: Production sempre via canary (10% → 100%).
- [ ] **Manual gates**: Production requer aprovação (GitHub environments).
- [ ] **Rollback ready**: Ter comando rollback testado regularmente.
- [ ] **Secrets**: Nunca commit credentials; usar Vault ou GitHub Secrets.
- [ ] **Monitoring**: Alertas para deployment failures + performance degradation.

---

## 10. Referências

- [buf CLI Documentation](https://buf.build/docs/reference/cli)
- [golangci-lint](https://golangci-lint.run/usage/configuration/)
- [Trivy Security Scanning](https://aquasecurity.github.io/trivy/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

**Status**: Approved for Implementation  
**Mantido por**: DevOps + Platform Team
