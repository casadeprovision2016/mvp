# Cotai MVP — Developer Quick Reference

## 🚀 Getting Started (5 minutes)

### 1. First-Time Setup
```bash
# Navigate to project root
cd /home/felipe/dev/mvp

# Verify tools are installed
bash scripts/verify-setup.sh

# Start local environment (starts Minikube, configures kubectl)
bash scripts/local-start.sh
```

### 2. Verify Everything Works
```bash
# Check cluster is ready
make verify-cluster

# List services
kubectl get all -n dev

# Build all services
make build
```

---

## 📋 Daily Development Tasks

### Building Services
```bash
# Build single service
cd auth-service
go build -o bin/auth-service ./cmd/auth-service/main.go

# Build all services
make build

# Build specific service via Makefile
make build-auth-service
```

### Testing
```bash
# Run all tests
make test

# Run tests for one service
cd auth-service
go test ./...

# Run tests with coverage
go test -cover ./...
```

### Code Quality
```bash
# Lint all services
make lint

# Lint one service
cd auth-service
golangci-lint run ./...

# Format code
go fmt ./...
goimports -w .
```

### Running Services Locally
```bash
# Start a service
cd auth-service
cp .env.example .env
go run ./cmd/auth-service/main.go

# Service will listen on port specified in SERVICE_PORT (.env)
# Default: 50051

# Verify service is running
curl localhost:50051/health
```

---

## 🔧 Common Development Scenarios

### Adding a New Microservice
```bash
# Generate boilerplate for new service
bash scripts/scaffold-service.sh my-service

# Navigate to new service
cd my-service

# Download dependencies
go mod download && go mod tidy

# Verify structure
ls -la cmd/ internal/ proto/ charts/
```

### Working with Protocol Buffers
```bash
# Lint proto files
buf lint proto/

# Check for breaking changes
buf breaking --against .git#branch=main

# Generate Go code from proto definitions
buf generate proto/

# Result: Generated code in internal/pb/
```

### Kubernetes Deployment
```bash
# Create namespaces (only needed once)
make setup-namespaces

# Deploy service to dev namespace
helm install auth-service ./auth-service/charts \
  -f auth-service/charts/values-dev.yaml \
  -n dev

# Check deployment status
kubectl get deployment auth-service -n dev
kubectl rollout status deployment/auth-service -n dev

# View logs
kubectl logs -f deployment/auth-service -n dev

# Port forward to access service locally
kubectl port-forward svc/auth-service 50051:50051 -n dev

# Delete deployment
helm uninstall auth-service -n dev
```

### Environment Configuration
```bash
# Each service has environment template
cat auth-service/.env.example

# Copy and customize for local development
cp auth-service/.env.example auth-service/.env
nano auth-service/.env

# Key variables:
# - SERVICE_PORT: gRPC server port (default 50051)
# - DATABASE_URL: PostgreSQL connection
# - REDIS_URL: Redis connection
# - JAEGER_AGENT_HOST: Distributed tracing
# - LOG_LEVEL: Logging verbosity
```

### Checking Service Health
```bash
# Verify cluster is healthy
make verify-cluster

# Check all service statuses
kubectl get all -n dev

# Describe a specific deployment
kubectl describe deployment auth-service -n dev

# Check pod events
kubectl describe pod -l app=auth-service -n dev

# View all logs at once
kubectl logs -l app=auth-service -n dev --tail=100
```

---

## 📁 Project Structure Reference

### Per-Service Layout
```
service-name/
├── cmd/service-name/
│   └── main.go                    ← Service entrypoint
├── internal/
│   ├── config/
│   │   └── config.go              ← Configuration loading
│   ├── handlers/
│   │   └── handlers.go            ← gRPC service implementation
│   ├── models/
│   │   └── domain.go              ← Domain entities
│   ├── repository/
│   │   └── repository.go          ← Data access layer
│   └── service/
│       └── service.go             ← Business logic
├── pkg/                           ← Shared utilities
├── proto/                         ← Protocol Buffer definitions
├── charts/                        ← Kubernetes Helm charts
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml
│   ├── values-staging.yaml
│   ├── values-prod.yaml
│   └── templates/
├── tests/
│   ├── unit/
│   └── integration/
├── docker/
│   └── Dockerfile                 ← Multi-stage build
├── configs/
│   └── config.example.yaml
├── .env.example                   ← Environment variables
├── go.mod                         ← Dependencies
├── go.sum                         ← Dependency lock
└── README.md                      ← Service documentation
```

### Root Directories
```
/home/felipe/dev/mvp/
├── Makefile                       ← Main automation
├── .golangci.yml                  ← Go linting config
├── buf.yaml                       ← Protocol Buffer config
├── scripts/                       ← Automation scripts
├── kubernetes/                    ← Shared K8s manifests
├── terraform/                     ← IaC (infrastructure)
├── proto/v1/                      ← Shared protobuf definitions
├── docs/                          ← Documentation
│   ├── CHECKLIST.md
│   ├── arquiteture.md
│   ├── observability.md
│   └── adr/
├── [7 services]                   ← auth-service, edital-service, etc.
└── README.md                      ← Project overview
```

---

## 🔐 Secrets & Configuration Management

### Local Development (Never in Git)
```bash
# Always use .env files, never commit them
cp service-name/.env.example service-name/.env

# Add to .gitignore (already done)
echo ".env" >> .gitignore

# Load env vars when running service
export $(cat service-name/.env | xargs)
go run ./cmd/service-name/main.go
```

### Environment Variable Checklist
Each service needs these variables in `.env`:

```env
# Service Configuration
SERVICE_PORT=50051
ENVIRONMENT=development

# Database (PostgreSQL with RLS for multi-tenancy)
DATABASE_URL=postgres://user:password@localhost:5432/cotai_auth_service
DATABASE_POOL_SIZE=10
DATABASE_TIMEOUT=30s

# Cache
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=
REDIS_DB=0

# Message Broker
KAFKA_BROKERS=localhost:9092
KAFKA_GROUP_ID=auth-service-group
KAFKA_COMPRESSION=snappy

# Observability
JAEGER_AGENT_HOST=localhost
JAEGER_AGENT_PORT=6831
LOG_LEVEL=info

# Service Discovery
SERVICE_NAME=auth-service
SERVICE_VERSION=1.0.0
INSTANCE_ID=auth-service-pod-1

# Security (never hardcode in repo)
API_KEY=
SECRET_KEY=
JWT_SECRET=
```

---

## 📊 Makefile Quick Reference

```bash
make help                    # Show all targets
make minikube-start          # Start local cluster
make minikube-stop           # Stop cluster
make setup-local             # Full local setup (Minikube + namespaces)
make build                   # Build all services
make test                    # Run all tests
make lint                    # Lint all services
make ci-checks               # Run linting + proto validation
make verify-cluster          # Check cluster health
make docker-env              # Set Minikube Docker daemon
make clean                   # Clean build artifacts
make clean-all               # Full reset
```

---

## 🐛 Troubleshooting

### Minikube Issues
```bash
# Minikube won't start
minikube delete
minikube start --driver=docker --addons=ingress,metrics-server

# Check Minikube logs
minikube logs

# Check Minikube status
minikube status
```

### kubectl Context Issues
```bash
# See available contexts
kubectl config get-contexts

# Switch to Minikube
kubectl config use-context minikube

# Verify connection
kubectl cluster-info
```

### Service Won't Build
```bash
# Download dependencies
go mod download
go mod tidy

# Clear cache
go clean -cache -modcache -i -r

# Verify Go version (need 1.21+)
go version
```

### Service Won't Deploy
```bash
# Check Helm chart for errors
helm lint ./charts

# Validate Kubernetes manifests
helm template auth-service ./charts | kubeval

# Check service logs
kubectl logs -f deployment/auth-service -n dev

# Check pod events
kubectl describe pod -l app=auth-service -n dev
```

### Port Already in Use
```bash
# Find process using port
lsof -i :50051

# Kill process (if safe)
kill -9 <PID>

# Or use different port in .env
SERVICE_PORT=50052
```

---

## 📚 Important Files & References

| File | Purpose |
|------|---------|
| `README.md` | Project overview, quick-start, troubleshooting |
| `CONTRIBUTING.md` | Git workflow, code standards, PR process |
| `Makefile` | Build automation, Minikube targets |
| `CHECKLIST.md` | Phased delivery checklist (Phase 0-5) |
| `PHASE-1-SUMMARY.md` | This phase's detailed summary |
| `docs/arquiteture.md` | Architecture, design decisions, patterns |
| `docs/observability.md` | SLI/SLO definitions, observability setup |
| `docs/adr/` | Architecture Decision Records |
| `.golangci.yml` | Go linting configuration |
| `buf.yaml` | Protocol Buffer configuration |

---

## 🎯 Next Steps After Phase 1

1. **Implement Core Services** (Phase 2)
   - Define gRPC service contracts in proto/v1/
   - Implement handlers and business logic
   - Set up database migrations

2. **Add Observability** (Phase 2)
   - Instrument with OpenTelemetry
   - Create Prometheus metrics
   - Set up Jaeger tracing

3. **Create CI/CD Pipeline** (Phase 4)
   - GitHub Actions workflow
   - Build and push containers
   - Deploy to dev/staging/prod

4. **Production Hardening** (Phase 5)
   - Security policies (RBAC, NetworkPolicy)
   - Autoscaling configuration
   - High-availability setup

---

## 💡 Tips for Success

1. **Always start with `make verify-cluster`** — ensures environment is ready
2. **Use `go fmt` and `goimports` before commits** — keep code clean
3. **Run `golangci-lint` locally** — catch issues early
4. **Check service logs early** — `kubectl logs` is your best friend
5. **Use `.env.example` as template** — never commit `.env` files
6. **Keep services small and focused** — single responsibility principle
7. **Write tests as you code** — not after
8. **Use color output** — all scripts use ✅/❌ for easy scanning
9. **Read error messages carefully** — they usually tell you what's wrong
10. **Document as you go** — update README.md when adding features

---

**Happy coding! 🚀**
