# Cotai: Multi-Tenant Procurement Platform

Cotai is an enterprise-grade **SaaS platform** for multi-tenant procurement, bidding, and vendor management. It enables organizations to streamline the entire procurement lifecycle with advanced features for RFQ (Request for Quotation) management, bidding rounds, vendor evaluation, and compliance tracking.

## 🎯 Quick Links

- **[Architecture Guide](docs/arquiteture.md)** — System design, bounded contexts, and technology stack
- **[ADRs (Architecture Decision Records)](docs/adr/)** — Kafka, PostgreSQL, OpenTelemetry decisions
- **[Multi-Tenancy Model](docs/multitenancy.md)** — Row-Level Security (RLS), tenant isolation, data architecture
- **[Observability & SLOs](docs/observability.md)** — Traces, metrics, logging, and SLI definitions
- **[CI/CD Guidelines](docs/ci-cd-guidelines.md)** — Pipeline stages, gates, and deployment strategies
- **[Contributing Guide](CONTRIBUTING.md)** — Development workflow, commit conventions, and PR process
- **[Workstation Setup](scripts/setup-workstation.sh)** — Required tools and environment validation
- **[MVP Scope](docs/MVP-SCOPE.md)** — Features, acceptance criteria, and success metrics

---

## 🏗️ Architecture Overview

### Microservices Architecture

Cotai is built as a **distributed, event-driven microservices system** with the following core services:

| Service | Purpose | Language | DB |
|---------|---------|----------|-----|
| `auth-service` | OAuth2/OIDC, JWT, multi-factor authentication | Java (Spring Boot) | PostgreSQL |
| `edital-service` | Tender/RFQ creation, publication, lifecycle management | Java (Spring Boot) | PostgreSQL |
| `cotacao-service` | Quotation management, vendor responses, scoring | Java (Spring Boot) | PostgreSQL |
| `notificacao-service` | Email, SMS, in-app notifications | Go | PostgreSQL |
| `fornecedor-service` | Vendor profiles, registration, evaluation | Java (Spring Boot) | PostgreSQL |
| `extracao-service` | Document OCR, NLP, data extraction | Python | PostgreSQL |
| `estoque-service` | Inventory management, stock levels, forecasting | Java (Quarkus) | PostgreSQL |
| `chat-service` | Real-time messaging, collaboration | Go | PostgreSQL |

### Key Design Decisions

- **Protocol**: gRPC + Protobuf for service-to-service; REST for external APIs
- **Messaging**: Apache Kafka for event-driven communication with ordering guarantees per tenant
- **Database**: PostgreSQL 15+ with Row-Level Security (RLS) for multi-tenant data isolation
- **Observability**: OpenTelemetry (Jaeger for traces, Prometheus for metrics, Loki for logs)
- **Deployment**: Kubernetes with Helm charts; GitOps with ArgoCD/Flux for declarative configuration
- **Security**: OAuth2/OIDC, mTLS between services, Vault for secrets management

See [Architecture Guide](docs/arquiteture.md) for detailed design principles and trade-offs.

---

## 🚀 Quick Start

### Prerequisites

Ensure your workstation has all required tools installed. Run:

```bash
bash scripts/setup-workstation.sh
```

This validates or installs:
- `git` (2.20+), `docker` (24.0+), `minikube` (1.31+), `kubectl` (1.27+), `helm` (3.12+)
- `go` (1.21+), `python` (3.11+), `java` (17+), `maven`/`gradle`
- `golangci-lint`, `trivy`, `buf`, `kubectl-score`

### Local Development Environment

1. **Start Kubernetes cluster**:
   ```bash
   minikube start --driver=docker --addons=ingress,metrics-server
   eval $(minikube docker-env)  # Use Minikube's Docker daemon
   ```

2. **Clone and navigate to repository**:
   ```bash
   git clone https://github.com/your-org/cotai.git
   cd cotai
   ```

3. **Install dependencies** (PostgreSQL, Redis, Kafka, observability stack):
   ```bash
   make local-setup  # Installs Helm charts for dev dependencies
   ```

4. **Build all services**:
   ```bash
   make build
   ```

5. **Run tests**:
   ```bash
   make test
   ```

6. **Deploy to local cluster**:
   ```bash
   make deploy-local
   ```

7. **Access services**:
   - API Gateway: `http://localhost/api`
   - Jaeger UI: `http://localhost:16686`
   - Prometheus: `http://localhost:9090`
   - Grafana: `http://localhost:3000` (admin/admin)

### Makefile Targets

| Target | Description |
|--------|-------------|
| `make local-setup` | Initialize local Minikube cluster with dependencies |
| `make build` | Build all services and Docker images |
| `make test` | Run unit tests across all services |
| `make lint` | Run linters (golangci-lint, checkstyle, etc.) |
| `make test-integration` | Run integration tests in local cluster |
| `make deploy-local` | Deploy current images to local Minikube |
| `make deploy-staging` | Deploy to staging environment (requires credentials) |
| `make clean` | Remove local cluster and cleanup artifacts |
| `make docs` | Generate architecture and API documentation |

---

## 📋 Multi-Tenancy Model

Cotai uses **Row-Level Security (RLS) in PostgreSQL** to isolate tenant data:

1. **Single PostgreSQL instance** with multiple tenants
2. **All tables include `tenant_id`** foreign key
3. **RLS policies** automatically filter rows based on authenticated tenant
4. **JWT includes `tenant_id`** claim; API Gateway propagates via `X-Tenant-ID` header
5. **Immutable audit logs** with user_id, tenant_id, and timestamps

See [Multi-Tenancy Model](docs/multitenancy.md) for detailed implementation, schema design, and migration strategies.

---

## 📊 Observability & SLOs

### Service Level Objectives (SLOs)

| Metric | Target | P95 | P99 |
|--------|--------|-----|-----|
| **Availability** | 99.5% monthly uptime | — | — |
| **Latency (API)** | <500ms | <1000ms | <2000ms |
| **Error Rate** | <0.1% | — | — |
| **Request Rate** | 10k req/sec (scalable) | — | — |

### Instrumentation

All services export:
- **Traces**: Distributed tracing via OpenTelemetry → Jaeger
- **Metrics**: Prometheus metrics (HTTP, gRPC, database, business metrics)
- **Logs**: Structured JSON logs with correlation IDs → Loki

See [Observability & SLOs](docs/observability.md) for SLI definitions, instrumentation examples, and alerting rules.

---

## 🔐 Security & Compliance

### Authentication & Authorization

- **OAuth2/OIDC** for user identity (integrated with external IdP or built-in)
- **JWT tokens** with `sub`, `tenant_id`, `roles` claims
- **Service-to-service**: mTLS with X.509 certificates (via service mesh or cert manager)

### Data Protection

- **Encryption at rest**: PostgreSQL with encrypted volumes
- **Encryption in transit**: TLS 1.3 for all network communication
- **PII Masking**: Sensitive fields redacted in logs and traces
- **Audit Logging**: Immutable logs with tamper detection

### Secret Management

- **No credentials in repo**: Enforced via pre-commit hooks
- **Vault integration** for production secrets
- **GitHub Secrets** for CI/CD staging credentials

See [Architecture Guide](docs/arquiteture.md#security-and-compliance) for detailed security architecture.

---

## 🧪 Testing Strategy

### Test Pyramid

```
         /\          E2E Tests (slow, high confidence)
        /  \         API/Integration Tests
       /    \        Unit Tests (fast, isolated)
      /      \
```

### Running Tests

```bash
# Unit tests (fast, isolated)
make test

# Integration tests (against local services)
make test-integration

# Contract tests (gRPC API compatibility)
make test-contracts

# E2E tests (full workflows)
make test-e2e

# Coverage report
make test-coverage  # Threshold: 75% minimum
```

### Test Locations

- **Unit tests**: `*/internal/*_test.go`, `*/src/test/java/**/*Test.java`
- **Integration tests**: `*/test/integration/**`
- **Contract tests**: `*/test/contract/**`
- **E2E tests**: `./test/e2e/**`

---

## 📦 CI/CD Pipeline

The pipeline is implemented in GitHub Actions (`.github/workflows/`) with stages:

1. **Lint** → gRPC proto, code style (golangci-lint, Checkstyle, ruff)
2. **Test** → Unit + integration tests with coverage threshold
3. **Build** → Docker images (single tag = commit SHA)
4. **Security Scan** → Trivy (container), SonarQube (SAST), Snyk (dependencies)
5. **Helm Lint** → Chart validation with `helm lint` and `kubeval`
6. **Deploy to Dev** → Automatic deployment to development cluster
7. **Integration Tests** → Smoke tests against deployed services
8. **Promote to Staging** → Manual approval before staging deployment
9. **Deploy to Prod** → GitOps-based production rollout (canary or blue-green)

See [CI/CD Guidelines](docs/ci-cd-guidelines.md) for detailed pipeline configuration, secret management, and rollback procedures.

---

## 🤝 Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for:

- **Git workflow** (GitFlow with feature branches)
- **Commit conventions** (Conventional Commits: `feat:`, `fix:`, `docs:`, etc.)
- **PR checklist** (linting, testing, documentation)
- **Code review process** (CODEOWNERS, approval requirements)
- **API-first development** (proto-first gRPC design)

### Development Workflow

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes, commit with conventional format
git commit -m "feat(auth-service): add MFA support"

# Run linters and tests
make lint
make test

# Push and create PR
git push origin feature/my-feature
# GitHub: Create PR, link to issue, request review from CODEOWNERS
```

---

## 📚 Documentation Structure

```
docs/
├── arquiteture.md              # System design, DDD, polyglot stack
├── ADR/
│   ├── ADR-001-Kafka-Event-Bus.md       # Event-driven architecture decision
│   ├── ADR-002-PostgreSQL.md            # Database selection and RLS model
│   └── ADR-003-OpenTelemetry.md         # Observability stack
├── multitenancy.md             # Row-Level Security, data isolation
├── observability.md            # Traces, metrics, logs, SLOs
├── ci-cd-guidelines.md         # Pipeline stages, gates, deployment
├── MVP-SCOPE.md                # MVP features, acceptance criteria
└── CHECKLIST.md                # Phased delivery checklist (Conception → Production)
```

---

## 🛠️ Common Tasks

### Add a New Service

```bash
# 1. Create service scaffold (See Backstage templates or manual setup)
mkdir -p services/my-service/{cmd,internal,pkg,charts,proto}

# 2. Generate protobuf code
buf generate ./services/my-service/proto

# 3. Implement service with instrumentation (OpenTelemetry)
# 4. Create Helm chart
helm create services/my-service/charts/my-service-chart

# 5. Add CI/CD workflow
cp .github/workflows/service-template.yml .github/workflows/my-service.yml

# 6. Commit and push
git checkout -b feature/add-my-service
git add services/my-service/
git commit -m "feat: add my-service"
```

### Deploy to Production

```bash
# 1. Ensure all tests pass
make test-all

# 2. Tag release
git tag -s -m "Release v1.2.3" v1.2.3

# 3. Push tag (triggers CI/CD release workflow)
git push origin v1.2.3

# 4. GitHub: Monitor release workflow; once complete, approve ArgoCD sync
# 5. Verify deployment
kubectl get deployments -n prod -w
```

### Debug Production Issue

```bash
# Check service logs
kubectl logs -f deployment/cotacao-service -n prod --tail=100

# View traces in Jaeger (forwarded locally)
kubectl port-forward svc/jaeger-query 16686:16686 -n observability
# Open http://localhost:16686

# Check metrics in Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n observability
# Open http://localhost:9090

# Query logs in Grafana/Loki
kubectl port-forward svc/grafana 3000:3000 -n observability
# Open http://localhost:3000
```

---

## 📈 Performance & Scaling

### Horizontal Scaling

- **Stateless services**: Scale replicas via `HorizontalPodAutoscaler` based on CPU/memory/custom metrics
- **Stateful services**: Use Helm StatefulSets with PersistentVolumes (PostgreSQL, Redis)
- **Message queues**: Kafka consumer groups automatically distribute partitions across replicas

### Caching Strategy

- **HTTP caching**: CDN (CloudFlare, GCP Cloud CDN) for public APIs and static content
- **Distributed cache**: Redis Cluster for session, vendor data, computed results
- **In-process cache**: Local caches with TTL for frequently accessed data

### Database Optimization

- **Indexing**: Indexes on `tenant_id`, `user_id`, timestamps, and foreign keys
- **Partitioning**: Time-based partitioning for large tables (audit logs, events)
- **Read replicas**: For analytical queries and reporting
- **Connection pooling**: PgBouncer or cloud-native options

---

## 🐛 Troubleshooting

### Service not starting?

1. Check logs: `kubectl logs deployment/my-service -n dev`
2. Check readiness probe: `kubectl describe pod <pod-name> -n dev`
3. Verify database connectivity: Check `DATABASE_URL` environment variable
4. Check traces in Jaeger for startup errors

### High latency?

1. Check metrics in Prometheus: HTTP request duration, gRPC call latency
2. Identify bottleneck (DB, external API, compute)
3. Check database query plans: `EXPLAIN ANALYZE` on slow queries
4. Review traces in Jaeger to pinpoint slow spans

### Pod OutOfMemory?

1. Check memory requests/limits in Helm values
2. Profile application: Use Go pprof, Java Flight Recorder
3. Adjust `resources.requests.memory` and `resources.limits.memory` in Helm values
4. Consider increasing replica count instead of single large pod

---

## 📞 Support & Community

- **Issues**: GitHub Issues (classified by service/domain)
- **Discussions**: GitHub Discussions for RFCs and architecture questions
- **Slack**: Internal team channel `#cotai-dev`
- **On-call**: PagerDuty for production incidents

---

## 📄 License

[Specify License — e.g., MIT, Apache 2.0, proprietary]

---

## 👥 Authors & Maintainers

See [CODEOWNERS](CODEOWNERS) for service ownership and review assignments.

---

**Last Updated**: December 2025  
**Maintained By**: Platform & Infrastructure Teams
