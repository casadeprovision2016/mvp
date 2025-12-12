#!/bin/bash
set -euo pipefail

# ==============================================================================
# Cotai MVP - Local Development Dependencies Setup
# ==============================================================================
# This script provisions all infrastructure dependencies for local development:
# - PostgreSQL (for all services requiring database)
# - Redis (for caching layer)
# - Prometheus + Grafana (metrics and visualization)
# - Jaeger (distributed tracing)
# - RabbitMQ (optional message broker)
#
# Prerequisites:
# - kubectl configured with local cluster (Minikube/Kind/Docker Desktop)
# - Helm 3.x installed
# - Sufficient cluster resources (4 CPU, 8GB RAM recommended)
#
# Usage:
#   ./scripts/setup-dependencies.sh [OPTIONS]
#
# Options:
#   --namespace <name>     Namespace for dependencies (default: deps)
#   --skip-rabbitmq       Skip RabbitMQ installation
#   --skip-observability  Skip Prometheus/Grafana/Jaeger installation
#   --help                Display this help message
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
NAMESPACE="deps"
SKIP_RABBITMQ=false
SKIP_OBSERVABILITY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --skip-rabbitmq)
      SKIP_RABBITMQ=true
      shift
      ;;
    --skip-observability)
      SKIP_OBSERVABILITY=true
      shift
      ;;
    --help)
      head -n 25 "$0" | tail -n 18
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# ==============================================================================
# Helper Functions
# ==============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisite() {
  local cmd=$1
  local name=$2
  
  if ! command -v "$cmd" &> /dev/null; then
    log_error "$name is not installed. Please install it first."
    exit 1
  fi
}

wait_for_pods() {
  local namespace=$1
  local label=$2
  local timeout=${3:-300}
  
  log_info "Waiting for pods with label '$label' to be ready (timeout: ${timeout}s)..."
  
  if kubectl wait --for=condition=ready pod \
    -l "$label" \
    -n "$namespace" \
    --timeout="${timeout}s" 2>/dev/null; then
    return 0
  else
    log_warning "Some pods may not be ready yet. Check with: kubectl get pods -n $namespace -l $label"
    return 1
  fi
}

# ==============================================================================
# Prerequisites Check
# ==============================================================================

log_info "Checking prerequisites..."
check_prerequisite "kubectl" "kubectl"
check_prerequisite "helm" "Helm"

# Check if kubectl can connect to cluster
if ! kubectl cluster-info &> /dev/null; then
  log_error "Cannot connect to Kubernetes cluster. Please ensure your cluster is running."
  exit 1
fi

log_success "Prerequisites check passed"

# ==============================================================================
# Namespace Creation
# ==============================================================================

log_info "Creating namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
log_success "Namespace '$NAMESPACE' ready"

# ==============================================================================
# Helm Repository Setup
# ==============================================================================

log_info "Adding Helm repositories..."

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts

log_info "Updating Helm repositories..."
helm repo update

log_success "Helm repositories configured"

# ==============================================================================
# PostgreSQL Installation
# ==============================================================================

log_info "Installing PostgreSQL..."

# Check if already installed
if helm list -n "$NAMESPACE" | grep -q "^postgresql\s"; then
  log_warning "PostgreSQL already installed. Skipping..."
else
  helm install postgresql bitnami/postgresql \
    --namespace "$NAMESPACE" \
    --set auth.postgresPassword=devpassword123 \
    --set auth.database=cotai_dev \
    --set auth.username=cotai_user \
    --set auth.password=devpassword123 \
    --set primary.persistence.enabled=false \
    --set primary.resources.requests.memory=256Mi \
    --set primary.resources.requests.cpu=250m \
    --set primary.resources.limits.memory=512Mi \
    --set primary.resources.limits.cpu=500m \
    --set metrics.enabled=true \
    --set metrics.serviceMonitor.enabled=false
  
  wait_for_pods "$NAMESPACE" "app.kubernetes.io/name=postgresql" 180
  log_success "PostgreSQL installed successfully"
fi

# ==============================================================================
# Redis Installation
# ==============================================================================

log_info "Installing Redis..."

if helm list -n "$NAMESPACE" | grep -q "^redis\s"; then
  log_warning "Redis already installed. Skipping..."
else
  helm install redis bitnami/redis \
    --namespace "$NAMESPACE" \
    --set architecture=standalone \
    --set auth.enabled=true \
    --set auth.password=devpassword123 \
    --set master.persistence.enabled=false \
    --set master.resources.requests.memory=128Mi \
    --set master.resources.requests.cpu=100m \
    --set master.resources.limits.memory=256Mi \
    --set master.resources.limits.cpu=200m \
    --set metrics.enabled=true \
    --set metrics.serviceMonitor.enabled=false
  
  wait_for_pods "$NAMESPACE" "app.kubernetes.io/name=redis" 120
  log_success "Redis installed successfully"
fi

# ==============================================================================
# RabbitMQ Installation (Optional)
# ==============================================================================

if [ "$SKIP_RABBITMQ" = false ]; then
  log_info "Installing RabbitMQ..."
  
  if helm list -n "$NAMESPACE" | grep -q "^rabbitmq\s"; then
    log_warning "RabbitMQ already installed. Skipping..."
  else
    helm install rabbitmq bitnami/rabbitmq \
      --namespace "$NAMESPACE" \
      --set auth.username=cotai_user \
      --set auth.password=devpassword123 \
      --set persistence.enabled=false \
      --set resources.requests.memory=256Mi \
      --set resources.requests.cpu=200m \
      --set resources.limits.memory=512Mi \
      --set resources.limits.cpu=500m \
      --set metrics.enabled=true \
      --set metrics.serviceMonitor.enabled=false
    
    wait_for_pods "$NAMESPACE" "app.kubernetes.io/name=rabbitmq" 180
    log_success "RabbitMQ installed successfully"
  fi
else
  log_info "Skipping RabbitMQ installation (--skip-rabbitmq flag set)"
fi

# ==============================================================================
# Observability Stack Installation (Optional)
# ==============================================================================

if [ "$SKIP_OBSERVABILITY" = false ]; then
  
  # Prometheus + Grafana Stack
  log_info "Installing Prometheus + Grafana stack..."
  
  if helm list -n "$NAMESPACE" | grep -q "^prometheus\s"; then
    log_warning "Prometheus stack already installed. Skipping..."
  else
    helm install prometheus prometheus-community/kube-prometheus-stack \
      --namespace "$NAMESPACE" \
      --set prometheus.prometheusSpec.retention=7d \
      --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
      --set prometheus.prometheusSpec.resources.requests.cpu=200m \
      --set grafana.enabled=true \
      --set grafana.adminPassword=admin \
      --set grafana.resources.requests.memory=128Mi \
      --set grafana.resources.requests.cpu=100m \
      --set alertmanager.enabled=false
    
    wait_for_pods "$NAMESPACE" "app.kubernetes.io/name=prometheus" 240
    wait_for_pods "$NAMESPACE" "app.kubernetes.io/name=grafana" 120
    log_success "Prometheus + Grafana installed successfully"
  fi
  
  # Jaeger
  log_info "Installing Jaeger..."
  
  if helm list -n "$NAMESPACE" | grep -q "^jaeger\s"; then
    log_warning "Jaeger already installed. Skipping..."
  else
    helm install jaeger jaegertracing/jaeger \
      --namespace "$NAMESPACE" \
      --set provisionDataStore.cassandra=false \
      --set allInOne.enabled=true \
      --set storage.type=memory \
      --set allInOne.resources.requests.memory=256Mi \
      --set allInOne.resources.requests.cpu=200m \
      --set agent.enabled=false \
      --set collector.enabled=false \
      --set query.enabled=false
    
    wait_for_pods "$NAMESPACE" "app.kubernetes.io/name=jaeger" 120
    log_success "Jaeger installed successfully"
  fi
  
else
  log_info "Skipping observability stack installation (--skip-observability flag set)"
fi

# ==============================================================================
# Verification & Summary
# ==============================================================================

echo ""
echo "================================================================================"
log_success "🎉 All dependencies installed successfully!"
echo "================================================================================"
echo ""

log_info "Deployed services in namespace '$NAMESPACE':"
kubectl get pods -n "$NAMESPACE" -o wide

echo ""
echo "================================================================================"
log_info "📋 Connection Information"
echo "================================================================================"

echo ""
echo "PostgreSQL:"
echo "  Host: postgresql.$NAMESPACE.svc.cluster.local"
echo "  Port: 5432"
echo "  Database: cotai_dev"
echo "  Username: cotai_user"
echo "  Password: devpassword123"
echo "  Root Password: devpassword123"
echo ""
echo "  Port-forward command:"
echo "    kubectl port-forward svc/postgresql 5432:5432 -n $NAMESPACE"

echo ""
echo "Redis:"
echo "  Host: redis-master.$NAMESPACE.svc.cluster.local"
echo "  Port: 6379"
echo "  Password: devpassword123"
echo ""
echo "  Port-forward command:"
echo "    kubectl port-forward svc/redis-master 6379:6379 -n $NAMESPACE"

if [ "$SKIP_RABBITMQ" = false ]; then
  echo ""
  echo "RabbitMQ:"
  echo "  Host: rabbitmq.$NAMESPACE.svc.cluster.local"
  echo "  Port: 5672 (AMQP), 15672 (Management UI)"
  echo "  Username: cotai_user"
  echo "  Password: devpassword123"
  echo ""
  echo "  Port-forward commands:"
  echo "    kubectl port-forward svc/rabbitmq 15672:15672 -n $NAMESPACE  # Management UI"
  echo "    kubectl port-forward svc/rabbitmq 5672:5672 -n $NAMESPACE    # AMQP"
  echo "  Management UI: http://localhost:15672"
fi

if [ "$SKIP_OBSERVABILITY" = false ]; then
  echo ""
  echo "Prometheus:"
  echo "  Port-forward command:"
  echo "    kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n $NAMESPACE"
  echo "  UI: http://localhost:9090"
  
  echo ""
  echo "Grafana:"
  echo "  Port-forward command:"
  echo "    kubectl port-forward svc/prometheus-grafana 3000:80 -n $NAMESPACE"
  echo "  UI: http://localhost:3000"
  echo "  Username: admin"
  echo "  Password: admin"
  
  echo ""
  echo "Jaeger:"
  echo "  Port-forward command:"
  echo "    kubectl port-forward svc/jaeger-query 16686:16686 -n $NAMESPACE"
  echo "  UI: http://localhost:16686"
fi

echo ""
echo "================================================================================"
log_info "🚀 Next Steps"
echo "================================================================================"
echo ""
echo "1. Deploy services using Helm:"
echo "   helm install auth-service ./auth-service/charts/auth-service -f values-dev.yaml -n dev"
echo ""
echo "2. Verify service connectivity to dependencies"
echo ""
echo "3. Check logs:"
echo "   kubectl logs -f deployment/<service-name> -n dev"
echo ""
echo "4. Access observability tools using port-forward commands above"
echo ""
echo "================================================================================"

log_success "Setup complete! Happy coding! 🎉"
