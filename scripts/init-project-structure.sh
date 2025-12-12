#!/bin/bash

###############################################################################
# Cotai MVP Project Structure Initialization
#
# Purpose: Initialize all service directories, shared directories, and
#          placeholder files according to Phase 1 specifications
# Usage: bash scripts/init-project-structure.sh
###############################################################################

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📁 Initializing Cotai MVP Project Structure${NC}"
echo ""

# Define core services
SERVICES=(
    "auth-service"
    "edital-service"
    "procurement-service"
    "bidding-service"
    "notification-service"
    "audit-service"
    "api-gateway"
)

# Define shared directories
SHARED_DIRS=(
    "kubernetes"
    "terraform"
    "proto"
)

# Create shared directories
echo -e "${BLUE}🔨 Creating shared directories...${NC}"
for dir in "${SHARED_DIRS[@]}"; do
    mkdir -p "$dir"
    echo -e "  ${GREEN}✅${NC} $dir"
done
echo ""

# Create service directories
echo -e "${BLUE}🔨 Creating service directories...${NC}"
for service in "${SERVICES[@]}"; do
    mkdir -p "$service"/{cmd,internal,pkg,configs,tests,charts,proto,docker}
    touch "$service"/{configs,tests,docker}/.gitkeep
    echo -e "  ${GREEN}✅${NC} $service"
done
echo ""

# Create service README templates
echo -e "${BLUE}📝 Creating service README files...${NC}"
for service in "${SERVICES[@]}"; do
    cat > "$service/README.md" << EOF
# $service

Domain service for $service in Cotai MVP.

## Overview

$service is a microservice responsible for [define specific domain responsibility].

## Structure

\`\`\`
$service/
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
\`\`\`

## Quick Start

### Prerequisites

- Go 1.21+
- Docker
- Minikube (for local Kubernetes)
- kubectl

### Build

\`\`\`bash
cd $service
go mod tidy
go build ./cmd/...
\`\`\`

### Run

\`\`\`bash
cd $service
go run ./cmd/main.go
\`\`\`

Server will start on port 50051 (gRPC) by default.

### Test

\`\`\`bash
go test ./... -v
\`\`\`

### Docker

\`\`\`bash
docker build -f docker/Dockerfile -t cotai-$service:latest .
docker run -p 50051:50051 cotai-$service:latest
\`\`\`

## Configuration

Configure via environment variables:

\`\`\`bash
export SERVICE_NAME=$service
export PORT=50051
export ENVIRONMENT=development
export DATABASE_URL=postgresql://user:pass@localhost/db
export REDIS_URL=redis://localhost:6379
\`\`\`

See \`.env.example\` for all available variables.

## API Documentation

### gRPC Services

Protocol buffer definitions are in \`proto/\` directory.

Generate Go code:
\`\`\`bash
buf generate
\`\`\`

## Observability

This service exports:

- **Traces**: OpenTelemetry → Jaeger
- **Metrics**: Prometheus
- **Logs**: Structured JSON to stdout

Health check endpoint: \`GET http://localhost:50051/health\`

## Deployment

Deploy to Kubernetes:

\`\`\`bash
helm install $service ./charts/ -f charts/values-dev.yaml -n dev
\`\`\`

See \`charts/README.md\` for detailed Helm configuration.

## Contributing

See \`../CONTRIBUTING.md\` for development workflow, code standards, and PR process.

## References

- Architecture: \`../docs/arquiteture.md\`
- Observability: \`../docs/observability.md\`
- Multi-tenancy: \`../docs/multitenancy.md\`
- Naming Schema: \`../docs/ARTIFACT-NAMING.md\`

---

**Last Updated**: December 2025
EOF
    echo -e "  ${GREEN}✅${NC} $service/README.md"
done
echo ""

# Create .env.example files
echo -e "${BLUE}📝 Creating .env.example files...${NC}"
for service in "${SERVICES[@]}"; do
    cat > "$service/.env.example" << EOF
# $service Configuration

# Service Identity
SERVICE_NAME=$service
PORT=50051
ENVIRONMENT=development

# Database (PostgreSQL)
DATABASE_URL=postgresql://user:password@localhost:5432/cotai
DATABASE_POOL_SIZE=20

# Cache (Redis)
REDIS_URL=redis://localhost:6379/0

# Observability
JAEGER_AGENT_HOST=localhost
JAEGER_AGENT_PORT=6831
PROMETHEUS_PORT=8090

# Multi-tenancy
JWT_SECRET=your-secret-key-change-in-production
JWT_ISSUER=https://auth.cotai.local
JWT_AUDIENCE=$service

# Logging
LOG_LEVEL=info
LOG_FORMAT=json

# Feature Flags
FEATURE_RLS_ENABLED=true
FEATURE_AUDIT_ENABLED=true
EOF
    echo -e "  ${GREEN}✅${NC} $service/.env.example"
done
echo ""

# Create .golangci.yml for Go projects
echo -e "${BLUE}📝 Creating .golangci.yml...${NC}"
cat > .golangci.yml << 'EOF'
run:
  timeout: 5m
  modules-download-mode: readonly

linters:
  enable:
    - gofmt
    - goimports
    - ineffassign
    - misspell
    - revive
    - vet
    - staticcheck
    - gosimple
    - unconvert
    - errcheck
    - gocritic

linters-settings:
  revive:
    min-confidence: 0.8

issues:
  exclude-rules:
    - path: _test\.go
      linters:
        - errcheck
        - gocritic
EOF
echo -e "  ${GREEN}✅${NC} .golangci.yml"
echo ""

# Create buf.yaml for protocol buffers
echo -e "${BLUE}📝 Creating buf.yaml...${NC}"
cat > buf.yaml << 'EOF'
version: v1

build:
  roots:
    - proto

lint:
  use:
    - DEFAULT
    - COMMENTS
  except:
    - PACKAGE_VERSION_SUFFIX

breaking:
  use:
    - FILE
  except:
    - FILE_SAME_PACKAGE
EOF
echo -e "  ${GREEN}✅${NC} buf.yaml"
echo ""

# Create proto directory structure
echo -e "${BLUE}🔨 Creating proto directory structure...${NC}"
mkdir -p proto/v1
touch proto/v1/.gitkeep
echo -e "  ${GREEN}✅${NC} proto/v1"
echo ""

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ Project Structure Initialization Complete          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📂 Created $(echo "${SERVICES[@]}" | wc -w) services with standard Go layout"
echo "📂 Created $(echo "${SHARED_DIRS[@]}" | wc -w) shared directories"
echo ""
echo -e "${YELLOW}📚 Next Steps:${NC}"
echo "  1. Verify cluster:    make verify-cluster"
echo "  2. Build services:    make build"
echo "  3. Run tests:         make test"
echo "  4. Deploy to dev:     make deploy-local"
echo ""
