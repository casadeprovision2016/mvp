# edital-service

Domain service for edital-service in Cotai MVP.

## Overview

edital-service is a microservice responsible for [define specific domain responsibility].

## Structure

```
edital-service/
├── cmd/                    # Application entrypoints
├── internal/               # Core business logic (not exposed)
├── pkg/                    # Shared utilities
├── proto/                  # Protocol buffer definitions (gRPC)
├── charts/                 # Helm chart for Kubernetes deployment
├── tests/                  # Integration and smoke tests
├── docker/                 # Dockerfile and build context
├── go.mod                  # Go module definition
├── configs/                # Configuration files
└── README.md               # This file
```

## Quick Start

### Prerequisites

- Go 1.21+
- Docker
- Minikube (for local Kubernetes)
- kubectl

### Build

```bash
cd edital-service
go mod tidy
go build ./cmd/...
```

### Run

```bash
cd edital-service
go run ./cmd/main.go
```

Server will start on port 50051 (gRPC) by default.

### Test

```bash
go test ./... -v
```

### Docker

```bash
docker build -f docker/Dockerfile -t cotai-edital-service:latest .
docker run -p 50051:50051 cotai-edital-service:latest
```

## Configuration

Configure via environment variables:

```bash
export SERVICE_NAME=edital-service
export PORT=50051
export ENVIRONMENT=development
export DATABASE_URL=postgresql://user:pass@localhost/db
export REDIS_URL=redis://localhost:6379
```

See `.env.example` for all available variables.

## API Documentation

### gRPC Services

Protocol buffer definitions are in `proto/` directory.

Generate Go code:
```bash
buf generate
```

## Observability

This service exports:

- **Traces**: OpenTelemetry → Jaeger
- **Metrics**: Prometheus
- **Logs**: Structured JSON to stdout

Health check endpoint: `GET http://localhost:50051/health`

## Deployment

Deploy to Kubernetes:

```bash
helm install edital-service ./charts/ -f charts/values-dev.yaml -n dev
```

See `charts/README.md` for detailed Helm configuration.

## Contributing

See `../CONTRIBUTING.md` for development workflow, code standards, and PR process.

## References

- Architecture: `../docs/arquiteture.md`
- Observability: `../docs/observability.md`
- Multi-tenancy: `../docs/multitenancy.md`
- Naming Schema: `../docs/ARTIFACT-NAMING.md`

---

**Last Updated**: December 2025
