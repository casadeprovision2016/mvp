#!/bin/bash

###############################################################################
# Cotai MVP - Service Scaffolding Tool
#
# Purpose: Generate complete microservice boilerplate with Go/gRPC structure
# Usage: bash scripts/scaffold-service.sh SERVICE_NAME
#
# Example:
#   bash scripts/scaffold-service.sh user-service
#   bash scripts/scaffold-service.sh payment-service
###############################################################################

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}❌ Error: SERVICE_NAME is required${NC}"
    echo ""
    echo "Usage: bash scripts/scaffold-service.sh <SERVICE_NAME>"
    echo ""
    echo "Examples:"
    echo "  bash scripts/scaffold-service.sh user-service"
    echo "  bash scripts/scaffold-service.sh payment-service"
    echo "  bash scripts/scaffold-service.sh order-service"
    echo ""
    exit 1
fi

SERVICE_NAME=$1
SERVICE_DIR="services/$SERVICE_NAME"
GO_MODULE="github.com/cotai/mvp/$SERVICE_NAME"

# Validate service name format
if ! [[ $SERVICE_NAME =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*-service$ ]]; then
    echo -e "${RED}❌ Error: Invalid service name format${NC}"
    echo ""
    echo "Service names must:"
    echo "  - Start with lowercase letter"
    echo "  - Contain only lowercase letters, numbers, and hyphens"
    echo "  - End with '-service' suffix"
    echo "  - Use hyphens for word separation (e.g., user-service, payment-service)"
    echo ""
    exit 1
fi

# Check if service already exists
if [ -d "$SERVICE_DIR" ]; then
    echo -e "${YELLOW}⚠️  Service directory already exists: $SERVICE_DIR${NC}"
    read -p "Continue and overwrite? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 0
    fi
fi

echo -e "${BLUE}🔨 Scaffolding service: ${GREEN}$SERVICE_NAME${NC}"
echo ""

# Create directory structure
echo -e "${BLUE}📁 Creating directories...${NC}"
mkdir -p "$SERVICE_DIR"/{cmd/$SERVICE_NAME,internal/{config,handlers,models,repository,service},pkg,proto,charts/{templates,envs},tests/{unit,integration},docker,configs}
echo -e "  ${GREEN}✅${NC} Directory structure created"

# Create go.mod
echo -e "${BLUE}📝 Creating go.mod...${NC}"
cat > "$SERVICE_DIR/go.mod" << 'EOF'
module github.com/cotai/mvp/SERVICE_PLACEHOLDER

go 1.21

require (
	google.golang.org/grpc v1.60.0
	google.golang.org/protobuf v1.31.0
	github.com/joho/godotenv v1.5.1
	go.opentelemetry.io/api v1.24.0
	go.opentelemetry.io/sdk v1.24.0
	go.opentelemetry.io/otel/exporters/jaeger/otlptrace/otlptracehttp v1.24.0
	github.com/sirupsen/logrus v1.9.3
)
EOF
# Replace placeholder
sed -i "s|SERVICE_PLACEHOLDER|$SERVICE_NAME|g" "$SERVICE_DIR/go.mod"
echo -e "  ${GREEN}✅${NC} go.mod created"

# Create main.go
echo -e "${BLUE}📝 Creating main.go...${NC}"
cat > "$SERVICE_DIR/cmd/$SERVICE_NAME/main.go" << 'MAINEOF'
package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	"go.opentelemetry.io/api/trace"

	"SERVICE_MODULE/internal/config"
	"SERVICE_MODULE/internal/handlers"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to load config: %v\n", err)
		os.Exit(1)
	}

	// Initialize tracer (OpenTelemetry)
	// tp, err := jaegerSDK.New(cfg.JaegerAddr)
	// defer tp.Shutdown(context.Background())
	// tracer := tp.Tracer("SERVICE_NAME")

	// Create gRPC server
	grpcServer := grpc.NewServer()

	// Register handlers
	// pb.RegisterSERVICEServiceServer(grpcServer, handlers.NewServiceServer())

	// Listen on port
	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", cfg.Port))
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to listen: %v\n", err)
		os.Exit(1)
	}
	defer listener.Close()

	fmt.Printf("🚀 SERVICE_NAME listening on port %d\n", cfg.Port)

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := grpcServer.Serve(listener); err != nil {
			fmt.Fprintf(os.Stderr, "server error: %v\n", err)
			os.Exit(1)
		}
	}()

	// Wait for shutdown signal
	<-sigChan
	fmt.Println("\n⏹️  Shutting down gracefully...")
	grpcServer.GracefulStop()
}
MAINEOF
# Replace placeholders
sed -i "s|SERVICE_MODULE|$GO_MODULE|g" "$SERVICE_DIR/cmd/$SERVICE_NAME/main.go"
sed -i "s|SERVICE_NAME|$SERVICE_NAME|g" "$SERVICE_DIR/cmd/$SERVICE_NAME/main.go"
echo -e "  ${GREEN}✅${NC} main.go created"

# Create config package
echo -e "${BLUE}📝 Creating config/config.go...${NC}"
cat > "$SERVICE_DIR/internal/config/config.go" << 'CONFIGEOF'
package config

import (
	"fmt"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	Port         int
	Environment  string
	DatabaseURL  string
	RedisURL     string
	JaegerAddr   string
	KafkaBrokers string
}

func Load() (*Config, error) {
	// Load .env file if it exists
	_ = godotenv.Load()

	cfg := &Config{
		Port:        getEnvInt("SERVICE_PORT", 50051),
		Environment: getEnvString("ENVIRONMENT", "development"),
		DatabaseURL: getEnvString("DATABASE_URL", "postgres://localhost/cotai_SERVICE_NAME"),
		RedisURL:    getEnvString("REDIS_URL", "redis://localhost:6379"),
		JaegerAddr:  getEnvString("JAEGER_AGENT_HOST", "localhost") + ":" + getEnvString("JAEGER_AGENT_PORT", "6831"),
		KafkaBrokers: getEnvString("KAFKA_BROKERS", "localhost:9092"),
	}

	if err := cfg.Validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

func (c *Config) Validate() error {
	if c.Port <= 0 || c.Port > 65535 {
		return fmt.Errorf("invalid port: %d", c.Port)
	}
	return nil
}

func getEnvString(key, defaultValue string) string {
	if val, exists := os.LookupEnv(key); exists {
		return val
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if val, exists := os.LookupEnv(key); exists {
		if intVal, err := strconv.Atoi(val); err == nil {
			return intVal
		}
	}
	return defaultValue
}
CONFIGEOF
# Replace placeholders
sed -i "s|SERVICE_NAME|$SERVICE_NAME|g" "$SERVICE_DIR/internal/config/config.go"
echo -e "  ${GREEN}✅${NC} config/config.go created"

# Create empty handlers.go
echo -e "${BLUE}📝 Creating handlers/handlers.go...${NC}"
cat > "$SERVICE_DIR/internal/handlers/handlers.go" << 'HANDLEREOF'
package handlers

// ServiceServer implements the gRPC service
type ServiceServer struct {
	// Add dependencies here
}

// NewServiceServer creates a new service server
func NewServiceServer() *ServiceServer {
	return &ServiceServer{}
}
HANDLEREOF
echo -e "  ${GREEN}✅${NC} handlers/handlers.go created"

# Create Dockerfile
echo -e "${BLUE}📝 Creating Dockerfile...${NC}"
cat > "$SERVICE_DIR/docker/Dockerfile" << 'DOCKEREOF'
# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /app/service ./cmd/SERVICE_NAME/main.go

# Runtime stage
FROM alpine:latest

WORKDIR /app

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

# Copy binary from builder
COPY --from=builder /app/service .

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:50051/health || exit 1

EXPOSE 50051

CMD ["./service"]
DOCKEREOF
sed -i "s|SERVICE_NAME|$SERVICE_NAME|g" "$SERVICE_DIR/docker/Dockerfile"
echo -e "  ${GREEN}✅${NC} Dockerfile created"

# Create .env.example
echo -e "${BLUE}📝 Creating .env.example...${NC}"
cat > "$SERVICE_DIR/.env.example" << 'ENVEOF'
# Service Configuration
SERVICE_PORT=50051
ENVIRONMENT=development

# Database
DATABASE_URL=postgres://user:password@localhost:5432/cotai_SERVICE_NAME

# Redis
REDIS_URL=redis://localhost:6379

# Message Broker
KAFKA_BROKERS=localhost:9092

# Observability
JAEGER_AGENT_HOST=localhost
JAEGER_AGENT_PORT=6831
LOG_LEVEL=info

# Service Discovery
SERVICE_NAME=SERVICE_NAME
SERVICE_VERSION=1.0.0
ENVEOF
sed -i "s|SERVICE_NAME|$SERVICE_NAME|g" "$SERVICE_DIR/.env.example"
echo -e "  ${GREEN}✅${NC} .env.example created"

# Create README
echo -e "${BLUE}📝 Creating README.md...${NC}"
cat > "$SERVICE_DIR/README.md" << 'READMEEOF'
# SERVICE_NAME

**gRPC Microservice** for the Cotai MVP platform.

## Quick Start

### Prerequisites
- Go 1.21+
- Docker
- Protocol Buffer compiler (protoc)

### Setup

1. **Copy environment file**
   ```bash
   cp .env.example .env
   ```

2. **Install dependencies**
   ```bash
   go mod download
   go mod tidy
   ```

3. **Build the service**
   ```bash
   go build -o bin/SERVICE_NAME ./cmd/SERVICE_NAME/main.go
   ```

4. **Run the service**
   ```bash
   ./bin/SERVICE_NAME
   ```

### Docker Build

```bash
docker build -f docker/Dockerfile -t cotai-SERVICE_NAME:latest .
docker run -p 50051:50051 --env-file .env cotai-SERVICE_NAME:latest
```

## Project Structure

- `cmd/SERVICE_NAME/` - Service entrypoint (main.go)
- `internal/`
  - `config/` - Configuration loading and validation
  - `handlers/` - gRPC service handlers
  - `models/` - Domain models and entities
  - `repository/` - Data access layer
  - `service/` - Business logic layer
- `pkg/` - Shared utilities and helpers
- `proto/` - Protocol Buffer definitions
- `charts/` - Kubernetes Helm charts
- `tests/` - Unit and integration tests
- `docker/` - Docker build files

## Configuration

See `.env.example` for all available environment variables.

Key variables:
- `SERVICE_PORT` - gRPC server port (default: 50051)
- `DATABASE_URL` - PostgreSQL connection string
- `REDIS_URL` - Redis connection string
- `KAFKA_BROKERS` - Kafka broker addresses
- `JAEGER_AGENT_HOST` - Jaeger agent for tracing
- `LOG_LEVEL` - Logging level (debug, info, warn, error)

## Development

### Generate Protocol Buffers

```bash
buf lint proto/
buf generate proto/
```

### Run Tests

```bash
go test ./...
go test -v ./... # Verbose output
go test -cover ./... # With coverage
```

### Linting

```bash
golangci-lint run ./...
```

## Kubernetes Deployment

### Helm Chart

```bash
helm install SERVICE_NAME ./charts \
  -f charts/envs/values-dev.yaml \
  -n dev
```

### View Deployment

```bash
kubectl get deployment -n dev | grep SERVICE_NAME
kubectl logs -n dev -l app=SERVICE_NAME
```

## Observability

- **Metrics**: Prometheus endpoints at `/metrics`
- **Traces**: Jaeger integration via OpenTelemetry
- **Logs**: Structured JSON logs to stdout

See `docs/observability.md` for configuration details.

## Contributing

Please follow the conventions in `CONTRIBUTING.md` at the repository root.

## License

Proprietary - Cotai MVP
READMEEOF
sed -i "s|SERVICE_NAME|$SERVICE_NAME|g" "$SERVICE_DIR/README.md"
echo -e "  ${GREEN}✅${NC} README.md created"

# Create .gitkeep files for empty directories
echo -e "${BLUE}📁 Creating .gitkeep files...${NC}"
touch "$SERVICE_DIR"/{pkg,tests/unit,tests/integration,proto}/.gitkeep
echo -e "  ${GREEN}✅${NC} .gitkeep files created"

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ Service Scaffolded Successfully! ${GREEN}✅${NC}              ║"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📦 Service created at: ${GREEN}$SERVICE_DIR${NC}"
echo ""
echo "📚 Next Steps:"
echo "  1. Navigate to service:    cd $SERVICE_DIR"
echo "  2. Update .env:            cp .env.example .env"
echo "  3. Install dependencies:   go mod download && go mod tidy"
echo "  4. Generate protobuf code: buf generate proto/"
echo "  5. Build:                  go build -o bin/$SERVICE_NAME ./cmd/$SERVICE_NAME/main.go"
echo "  6. Run tests:              go test ./..."
echo ""
echo "💡 Tips:"
echo "  - Define gRPC services in proto/v1/*.proto"
echo "  - Implement handlers in internal/handlers/"
echo "  - Add business logic in internal/service/"
echo "  - Create Helm values in charts/envs/"
echo ""
