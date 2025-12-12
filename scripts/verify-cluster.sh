#!/bin/bash

###############################################################################
# Cotai MVP - Kubernetes Cluster Verification
#
# Purpose: Verify local Kubernetes cluster is accessible and configured correctly
# Usage: bash scripts/verify-cluster.sh
###############################################################################

set -e

echo "🔍 Verifying Kubernetes Cluster Setup..."
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check cluster access
echo -e "${BLUE}📡 Cluster Access:${NC}"
if kubectl cluster-info > /dev/null 2>&1; then
    echo -e "  ${GREEN}✅${NC} kubectl is accessible"
    kubectl cluster-info 2>/dev/null | head -2 | sed 's/^/    /'
else
    echo -e "  ${RED}❌${NC} kubectl cannot access cluster"
    echo "    Run: make minikube-start"
    exit 1
fi
echo ""

# Check nodes
echo -e "${BLUE}🔍 Nodes:${NC}"
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODES" -gt 0 ]; then
    echo -e "  ${GREEN}✅${NC} $NODES node(s) available"
    kubectl get nodes -o wide 2>/dev/null | tail -n +2 | sed 's/^/    /'
else
    echo -e "  ${RED}❌${NC} No nodes available"
    exit 1
fi
echo ""

# Check namespaces
echo -e "${BLUE}📦 Namespaces:${NC}"
echo "  Expected namespaces: dev, staging, prod"
echo ""
kubectl get namespaces 2>/dev/null | tail -n +2 | sed 's/^/    /'
echo ""

# Check required addons
echo -e "${BLUE}🔧 Addons Status:${NC}"
INGRESS=$(minikube addons list 2>/dev/null | grep -c "ingress.*enabled" || echo "0")
METRICS=$(minikube addons list 2>/dev/null | grep -c "metrics-server.*enabled" || echo "0")

if [ "$INGRESS" -gt 0 ]; then
    echo -e "  ${GREEN}✅${NC} ingress addon is enabled"
else
    echo -e "  ${YELLOW}⚠️${NC} ingress addon is disabled (run: minikube addons enable ingress)"
fi

if [ "$METRICS" -gt 0 ]; then
    echo -e "  ${GREEN}✅${NC} metrics-server addon is enabled"
else
    echo -e "  ${YELLOW}⚠️${NC} metrics-server addon is disabled (run: minikube addons enable metrics-server)"
fi
echo ""

# Check API server availability
echo -e "${BLUE}🌐 API Server Health:${NC}"
API_STATUS=$(kubectl api-resources 2>/dev/null | wc -l)
if [ "$API_STATUS" -gt 0 ]; then
    echo -e "  ${GREEN}✅${NC} API server is responsive"
else
    echo -e "  ${RED}❌${NC} API server is not responsive"
    exit 1
fi
echo ""

# Check service endpoints
echo -e "${BLUE}📡 Service Endpoints:${NC}"
kubectl get endpoints -n kube-system 2>/dev/null | grep -E "kubernetes|kube-apiserver" | sed 's/^/  /'
echo ""

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ Cluster Verification: ${GREEN}✅ READY${NC}                      ║"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo "✅ Kubernetes cluster is ready for deployment!"
echo ""
echo "📚 Next Steps:"
echo "  1. Create namespaces:      make setup-namespaces"
echo "  2. Initialize project:     bash scripts/init-project-structure.sh"
echo "  3. Build services:         make build"
echo "  4. Deploy to dev:          helm install <service> ./charts/<service> -n dev"
echo ""
