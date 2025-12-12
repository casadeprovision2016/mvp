# Local Development Deployment Guide

## 🎯 Overview

This guide covers deploying the Cotai MVP platform to a local Kubernetes cluster for development purposes. All services run with in-cluster dependencies (PostgreSQL, Redis, RabbitMQ) and full observability stack.

---

## 📋 Prerequisites

### Required Tools

| Tool | Version | Installation |
|------|---------|--------------|
| **Docker** | 20.10+ | [Install Docker](https://docs.docker.com/get-docker/) |
| **kubectl** | 1.27+ | [Install kubectl](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | 3.12+ | [Install Helm](https://helm.sh/docs/intro/install/) |
| **Kubernetes Cluster** | 1.27+ | Minikube, Kind, or Docker Desktop |

### Cluster Options

#### Option 1: Minikube (Recommended for Development)
```bash
# Install Minikube
# macOS: brew install minikube
# Linux: curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Start cluster with recommended resources
minikube start --cpus=4 --memory=8192 --disk-size=40g --driver=docker

# Enable addons
minikube addons enable metrics-server
minikube addons enable ingress

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

#### Option 2: Kind (Kubernetes in Docker)
```bash
# Install Kind
# macOS: brew install kind
# Linux: curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# Create cluster with config
cat <<EOF | kind create cluster --name cotai-dev --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

# Verify
kubectl cluster-info --context kind-cotai-dev
```

#### Option 3: Docker Desktop Kubernetes
```bash
# Enable Kubernetes in Docker Desktop settings
# Settings > Kubernetes > Enable Kubernetes > Apply & Restart

# Verify
kubectl config use-context docker-desktop
kubectl get nodes
```

### Resource Requirements

| Component | CPU | Memory | Disk |
|-----------|-----|--------|------|
| **Cluster** | 4 cores | 8 GB | 40 GB |
| **Dependencies** | 1.5 cores | 2 GB | - |
| **Services (7)** | 2 cores | 4 GB | - |
| **Observability** | 0.5 cores | 1.5 GB | - |

---

## 🚀 Step 1: Deploy Infrastructure Dependencies

Run the automated setup script to install PostgreSQL, Redis, RabbitMQ, and observability tools:

```bash
cd /home/felipe/dev/mvp

# Full installation (recommended)
./scripts/setup-dependencies.sh

# Custom namespace
./scripts/setup-dependencies.sh --namespace dev-deps

# Skip RabbitMQ (if not using event-driven features)
./scripts/setup-dependencies.sh --skip-rabbitmq

# Skip observability (for minimal setup)
./scripts/setup-dependencies.sh --skip-observability

# Help
./scripts/setup-dependencies.sh --help
```

### What Gets Installed

| Component | Chart | Purpose | Resources |
|-----------|-------|---------|-----------|
| **PostgreSQL** | bitnami/postgresql:12.0.1 | Primary database | 250m CPU / 256Mi RAM |
| **Redis** | bitnami/redis:17.0.11 | Cache layer | 100m CPU / 128Mi RAM |
| **RabbitMQ** | bitnami/rabbitmq | Message broker (optional) | 200m CPU / 256Mi RAM |
| **Prometheus** | prometheus-community/kube-prometheus-stack | Metrics collection | 200m CPU / 512Mi RAM |
| **Grafana** | (included in Prometheus stack) | Metrics visualization | 100m CPU / 128Mi RAM |
| **Jaeger** | jaegertracing/jaeger | Distributed tracing | 200m CPU / 256Mi RAM |

### Verify Installation

```bash
# Check all pods are running
kubectl get pods -n deps

# Expected output (all Running):
# NAME                                  READY   STATUS    RESTARTS   AGE
# postgresql-0                          1/1     Running   0          2m
# redis-master-0                        1/1     Running   0          2m
# rabbitmq-0                            1/1     Running   0          2m
# prometheus-kube-prometheus-operator   1/1     Running   0          2m
# prometheus-grafana-xxx                3/3     Running   0          2m
# jaeger-xxx                            1/1     Running   0          2m

# Check services
kubectl get svc -n deps
```

---

## 🔧 Step 2: Configure Service Values

Update service Helm values to point to local dependencies:

### Development Values Template

Each service has a `values-dev.yaml` that's pre-configured for local development. Verify these settings:

```yaml
# Example: auth-service/charts/auth-service/values-dev.yaml
env:
  DATABASE_HOST: postgresql.deps.svc.cluster.local  # ✅ Correct
  REDIS_HOST: redis-master.deps.svc.cluster.local   # ✅ Correct
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://jaeger-collector.deps.svc.cluster.local:4317"

postgresql:
  enabled: false  # ✅ Using shared PostgreSQL in deps namespace

redis:
  enabled: false  # ✅ Using shared Redis in deps namespace
```

### Initialize Databases

Each service may need its own database in PostgreSQL:

```bash
# Port-forward PostgreSQL
kubectl port-forward svc/postgresql 5432:5432 -n deps &

# Connect and create databases
psql -h localhost -U cotai_user -d cotai_dev -W
# Password: devpassword123

# Create service-specific databases
CREATE DATABASE cotai_auth;
CREATE DATABASE cotai_edital;
CREATE DATABASE cotai_procurement;
CREATE DATABASE cotai_bidding;
CREATE DATABASE cotai_notification;
CREATE DATABASE cotai_audit;

# Exit
\q

# Stop port-forward
killall kubectl
```

Or use automated script:

```bash
# Create script
cat > scripts/init-databases.sh <<'EOF'
#!/bin/bash
PGPASSWORD=devpassword123 psql -h localhost -p 5432 -U cotai_user -d postgres <<SQL
CREATE DATABASE IF NOT EXISTS cotai_auth;
CREATE DATABASE IF NOT EXISTS cotai_edital;
CREATE DATABASE IF NOT EXISTS cotai_procurement;
CREATE DATABASE IF NOT EXISTS cotai_bidding;
CREATE DATABASE IF NOT EXISTS cotai_notification;
CREATE DATABASE IF NOT EXISTS cotai_audit;
SQL
EOF

chmod +x scripts/init-databases.sh

# Run (requires port-forward to be active)
kubectl port-forward svc/postgresql 5432:5432 -n deps &
sleep 2
./scripts/init-databases.sh
killall kubectl
```

---

## 🚢 Step 3: Deploy Services

### Deploy Individual Service

```bash
# Create namespace for services
kubectl create namespace dev

# Deploy auth-service
helm install auth-service ./auth-service/charts/auth-service \
  -f ./auth-service/charts/auth-service/values-dev.yaml \
  --namespace dev \
  --create-namespace

# Check deployment
kubectl get pods -n dev -l app.kubernetes.io/name=auth-service
kubectl logs -f deployment/auth-service -n dev
```

### Deploy All Services

```bash
# Create deployment script
cat > scripts/deploy-all-local.sh <<'EOF'
#!/bin/bash
set -euo pipefail

NAMESPACE=${1:-dev}
SERVICES=(auth edital procurement bidding notification audit api-gateway)

echo "Deploying all services to namespace: $NAMESPACE"

for service in "${SERVICES[@]}"; do
  service_name="${service}-service"
  chart_path="./${service_name}/charts/${service_name}"
  
  echo "Deploying ${service_name}..."
  
  helm upgrade --install "${service_name}" "${chart_path}" \
    -f "${chart_path}/values-dev.yaml" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait --timeout 5m
  
  echo "✅ ${service_name} deployed"
done

echo "🎉 All services deployed successfully!"
EOF

chmod +x scripts/deploy-all-local.sh

# Execute
./scripts/deploy-all-local.sh dev
```

### Verify Deployments

```bash
# Check all pods
kubectl get pods -n dev

# Check services
kubectl get svc -n dev

# Check ingress (if using)
kubectl get ingress -n dev

# Describe specific service
kubectl describe deployment auth-service -n dev

# Check resource usage
kubectl top pods -n dev
```

---

## 🔍 Step 4: Access and Testing

### Port-Forward Services

```bash
# Auth Service (gRPC)
kubectl port-forward svc/auth-service 50051:50051 -n dev &

# API Gateway (HTTP)
kubectl port-forward svc/api-gateway 8080:8080 -n dev &

# PostgreSQL
kubectl port-forward svc/postgresql 5432:5432 -n deps &

# Redis
kubectl port-forward svc/redis-master 6379:6379 -n deps &

# RabbitMQ Management UI
kubectl port-forward svc/rabbitmq 15672:15672 -n deps &

# Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n deps &

# Grafana
kubectl port-forward svc/prometheus-grafana 3000:80 -n deps &

# Jaeger
kubectl port-forward svc/jaeger-query 16686:16686 -n deps &

# View all port-forwards
jobs
```

### Test gRPC Service

```bash
# Install grpcurl if not already
# macOS: brew install grpcurl
# Linux: go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest

# List services
grpcurl -plaintext localhost:50051 list

# Health check
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check

# Call service method (example)
grpcurl -plaintext -d '{"username":"test","password":"test123"}' \
  localhost:50051 auth.v1.AuthService/Login
```

### Test HTTP Service (API Gateway)

```bash
# Health check
curl http://localhost:8080/health

# API call
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test123"}'
```

### Access Observability Tools

| Tool | URL | Credentials |
|------|-----|-------------|
| **Prometheus** | http://localhost:9090 | - |
| **Grafana** | http://localhost:3000 | admin / admin |
| **Jaeger** | http://localhost:16686 | - |
| **RabbitMQ Management** | http://localhost:15672 | cotai_user / devpassword123 |

---

## 📊 Step 5: Verify Observability

### Check Metrics in Prometheus

1. Open http://localhost:9090
2. Query: `up{namespace="dev"}` (should show all services)
3. Query: `http_requests_total` (should show HTTP metrics)
4. Query: `grpc_server_handled_total` (should show gRPC metrics)

### View Dashboards in Grafana

1. Open http://localhost:3000 (admin/admin)
2. Navigate to Dashboards
3. Import Kubernetes dashboards:
   - Kubernetes / Compute Resources / Namespace (Pods)
   - Kubernetes / Compute Resources / Workload
4. Create custom dashboard for Cotai services

### Trace Requests in Jaeger

1. Open http://localhost:16686
2. Select service from dropdown (e.g., "auth-service")
3. Click "Find Traces"
4. Click on a trace to see distributed tracing timeline

---

## 🐛 Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n dev

# Describe pod for events
kubectl describe pod <pod-name> -n dev

# Check logs
kubectl logs <pod-name> -n dev

# Check previous logs (if pod restarted)
kubectl logs <pod-name> -n dev --previous

# Common issues:
# - Image pull errors: Check image name and tag
# - CrashLoopBackOff: Check logs for application errors
# - Pending: Insufficient cluster resources (check with: kubectl describe node)
```

### Database Connection Errors

```bash
# Verify PostgreSQL is running
kubectl get pods -n deps -l app.kubernetes.io/name=postgresql

# Check PostgreSQL logs
kubectl logs -f postgresql-0 -n deps

# Test connection from service pod
kubectl exec -it <service-pod> -n dev -- sh
# Inside pod:
nc -zv postgresql.deps.svc.cluster.local 5432
# or
psql -h postgresql.deps.svc.cluster.local -U cotai_user -d cotai_auth
```

### Redis Connection Errors

```bash
# Verify Redis is running
kubectl get pods -n deps -l app.kubernetes.io/name=redis

# Test connection
kubectl exec -it <service-pod> -n dev -- sh
# Inside pod:
redis-cli -h redis-master.deps.svc.cluster.local -a devpassword123 ping
```

### Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints -n dev

# Check service ports
kubectl get svc <service-name> -n dev

# Port-forward directly to pod (bypass service)
kubectl port-forward <pod-name> 50051:50051 -n dev
```

### Out of Resources

```bash
# Check cluster resource usage
kubectl top nodes
kubectl top pods -A

# Free up resources
kubectl delete pod <pod-name> -n dev --force
minikube stop && minikube start

# Increase cluster resources (Minikube)
minikube delete
minikube start --cpus=6 --memory=12288
```

---

## 🧹 Cleanup

### Delete Services

```bash
# Delete all services
helm uninstall auth-service -n dev
helm uninstall edital-service -n dev
# ... repeat for all services

# Or delete namespace (removes all)
kubectl delete namespace dev
```

### Delete Dependencies

```bash
# Uninstall dependencies
helm uninstall postgresql -n deps
helm uninstall redis -n deps
helm uninstall rabbitmq -n deps
helm uninstall prometheus -n deps
helm uninstall jaeger -n deps

# Or delete namespace
kubectl delete namespace deps
```

### Delete Cluster

```bash
# Minikube
minikube delete

# Kind
kind delete cluster --name cotai-dev

# Docker Desktop: Disable Kubernetes in settings
```

---

## 📚 Additional Resources

- [Helm Chart Documentation](../auth-service/charts/auth-service/README.md)
- [Service Configuration Guide](../docs/INFRASTRUCTURE-DECISIONS.md)
- [GCP Deployment Guide](./DEPLOYMENT-GCP.md)
- [Validation Checklist](./DEPLOYMENT-VALIDATION.md)

---

## 🎯 Quick Reference

### Essential Commands

```bash
# Deploy dependencies
./scripts/setup-dependencies.sh

# Deploy all services
./scripts/deploy-all-local.sh dev

# Check status
kubectl get pods -n dev -n deps

# View logs
kubectl logs -f deployment/<service> -n dev

# Port-forward service
kubectl port-forward svc/<service> <local-port>:<service-port> -n dev

# Restart service
kubectl rollout restart deployment/<service> -n dev

# Scale service
kubectl scale deployment/<service> --replicas=2 -n dev

# Delete everything
kubectl delete namespace dev deps
```

---

**Last Updated**: December 2024  
**Maintainer**: Cotai DevOps Team
