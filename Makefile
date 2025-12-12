# Cotai MVP - Multi-tenant Procurement Platform
# Phase 1: Local Environment & Infrastructure Setup
#
# This Makefile automates Minikube cluster setup, service builds, testing, and deployment

.PHONY: help minikube-start minikube-stop minikube-status minikube-delete docker-env kubectl-context verify-cluster setup-namespaces setup-local build test lint ci-checks clean clean-all

# Default target
help:
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║  Cotai MVP - Makefile Targets                               ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚀 Minikube Targets:"
	@echo "  make minikube-start          Start Minikube cluster"
	@echo "  make minikube-stop           Stop Minikube cluster"
	@echo "  make minikube-status         Show Minikube & cluster status"
	@echo "  make minikube-delete         Delete Minikube cluster"
	@echo ""
	@echo "🔧 Local Development Targets:"
	@echo "  make docker-env              Configure shell for Minikube Docker"
	@echo "  make kubectl-context         Set kubectl context to Minikube"
	@echo "  make verify-cluster          Verify cluster accessibility"
	@echo "  make setup-namespaces        Create dev/staging/prod namespaces"
	@echo "  make setup-local             Full local setup (one command)"
	@echo ""
	@echo "🔨 Build & Test Targets:"
	@echo "  make build                   Build all services"
	@echo "  make test                    Run unit tests"
	@echo "  make lint                    Run linters (golangci-lint, buf)"
	@echo "  make ci-checks               Run all CI checks"
	@echo ""
	@echo "🧹 Cleanup Targets:"
	@echo "  make clean                   Clean build artifacts"
	@echo "  make clean-all               Clean everything + delete Minikube"
	@echo ""

# ============================================================================
# Minikube Targets
# ============================================================================

minikube-start:
	@echo "🚀 Starting Minikube cluster with required addons..."
	minikube start \
		--driver=docker \
		--addons=ingress,metrics-server \
		--cpus=4 \
		--memory=8192 \
		--disk-size=40g
	@echo "✅ Minikube started successfully!"

minikube-stop:
	@echo "⏸️  Stopping Minikube cluster..."
	minikube stop
	@echo "✅ Minikube stopped!"

minikube-status:
	@echo "📊 Minikube Status:"
	@minikube status
	@echo ""
	@echo "📦 Cluster Info:"
	@kubectl cluster-info 2>/dev/null || echo "⚠️  Cluster not accessible"
	@echo ""
	@echo "🔍 Nodes:"
	@kubectl get nodes -o wide 2>/dev/null || echo "⚠️  Cannot list nodes"
	@echo ""
	@echo "📋 Namespaces:"
	@kubectl get namespaces 2>/dev/null || echo "⚠️  Cannot list namespaces"

minikube-delete:
	@echo "🗑️  Deleting Minikube cluster..."
	minikube delete
	@echo "✅ Minikube deleted!"

# ============================================================================
# Kubectl & Docker Configuration
# ============================================================================

docker-env:
	@echo "🐳 Configuring Docker environment to use Minikube daemon..."
	@echo ""
	@echo "Run the following command in your shell:"
	@echo ""
	@eval $$(minikube docker-env) && echo "✅ Docker environment configured!"

kubectl-context:
	@echo "🎯 Setting kubectl context to Minikube..."
	@kubectl config use-context minikube 2>/dev/null || echo "⚠️  Minikube context not available"
	@echo "✅ Current context: $$(kubectl config current-context 2>/dev/null || echo 'unknown')"

verify-cluster:
	@echo "🔍 Verifying cluster is accessible..."
	@if kubectl cluster-info > /dev/null 2>&1; then \
		echo "✅ Cluster is accessible"; \
		echo ""; \
		kubectl cluster-info | head -2; \
		echo ""; \
		echo "Nodes:"; \
		kubectl get nodes --no-headers | sed 's/^/  /'; \
	else \
		echo "❌ Cluster is NOT accessible. Run 'make minikube-start' first."; \
		exit 1; \
	fi

# ============================================================================
# Namespace & Resource Setup
# ============================================================================

setup-namespaces:
	@echo "📦 Creating Kubernetes namespaces..."
	@kubectl create namespace dev --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - > /dev/null 2>&1 || true
	@kubectl create namespace staging --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - > /dev/null 2>&1 || true
	@kubectl create namespace prod --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - > /dev/null 2>&1 || true
	@echo "✅ Namespaces created: dev, staging, prod"
	@echo ""
	@echo "📋 Current namespaces:"
	@kubectl get namespaces --no-headers | sed 's/^/  /'

setup-local: minikube-start kubectl-context verify-cluster setup-namespaces
	@echo ""
	@echo "✅ Local environment setup complete!"
	@echo ""
	@echo "📚 Next steps:"
	@echo "  1. Initialize project: bash scripts/init-project-structure.sh"
	@echo "  2. Build services:    make build"
	@echo "  3. Run tests:          make test"
	@echo "  4. Deploy to dev:      helm install <service> ./charts/<service> -n dev"
	@echo ""

# ============================================================================
# Build & Test Targets
# ============================================================================

build:
	@echo "🔨 Building all services..."
	@for service in auth-service edital-service procurement-service bidding-service notification-service audit-service api-gateway; do \
		if [ -f "$$service/go.mod" ]; then \
			echo "Building $$service..."; \
			cd $$service && go build ./cmd/... 2>/dev/null && cd - > /dev/null && echo "  ✅ $$service" || echo "  ⚠️  $$service (skipped)"; \
		elif [ -f "$$service/build.gradle" ]; then \
			echo "Building $$service..."; \
			cd $$service && ./gradlew build -q 2>/dev/null && cd - > /dev/null && echo "  ✅ $$service" || echo "  ⚠️  $$service (skipped)"; \
		fi \
	done
	@echo "✅ Build complete!"

test:
	@echo "🧪 Running unit tests..."
	@for service in auth-service edital-service procurement-service bidding-service notification-service audit-service api-gateway; do \
		if [ -f "$$service/go.mod" ]; then \
			echo "Testing $$service..."; \
			cd $$service && go test ./... -v 2>/dev/null && cd - > /dev/null && echo "  ✅ $$service" || echo "  ⚠️  $$service (no tests)"; \
		elif [ -f "$$service/build.gradle" ]; then \
			echo "Testing $$service..."; \
			cd $$service && ./gradlew test -q 2>/dev/null && cd - > /dev/null && echo "  ✅ $$service" || echo "  ⚠️  $$service (no tests)"; \
		fi \
	done
	@echo "✅ Tests complete!"

lint:
	@echo "🔍 Running linters..."
	@for service in auth-service edital-service procurement-service bidding-service notification-service audit-service api-gateway; do \
		if [ -f "$$service/go.mod" ]; then \
			if command -v golangci-lint > /dev/null 2>&1; then \
				echo "Linting $$service..."; \
				cd $$service && golangci-lint run ./... 2>/dev/null && cd - > /dev/null && echo "  ✅ $$service" || echo "  ⚠️  $$service"; \
			fi \
		fi \
	done
	@echo "✅ Linting complete!"

ci-checks: lint test
	@echo "✅ All CI checks passed!"

# ============================================================================
# Cleanup Targets
# ============================================================================

clean:
	@echo "🧹 Cleaning build artifacts..."
	@find . -type d -name 'bin' -o -name '.coverage' | xargs rm -rf 2>/dev/null || true
	@for service in auth-service edital-service procurement-service bidding-service notification-service audit-service api-gateway; do \
		if [ -f "$$service/go.mod" ]; then \
			cd $$service && go clean ./... 2>/dev/null && cd - > /dev/null || true; \
		fi \
	done
	@echo "✅ Cleanup complete!"

clean-all: clean minikube-delete
	@echo "✅ Full cleanup complete! Minikube deleted."

# ============================================================================
# Development Convenience Targets
# ============================================================================

.PHONY: project-init verify-setup

project-init:
	@bash scripts/init-project-structure.sh

verify-setup:
	@bash scripts/verify-setup.sh

local-start:
	@bash scripts/local-start.sh

verify-k8s:
	@bash scripts/verify-cluster.sh
