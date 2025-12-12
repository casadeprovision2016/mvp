#!/bin/bash

###############################################################################
# Cotai MVP - Local Development Startup
#
# Purpose: One-command startup of local development environment
# Usage: bash scripts/local-start.sh
###############################################################################

set -e

echo "🚀 Starting Cotai MVP local development environment..."
echo ""

# Check Minikube
echo "🔍 Checking Minikube status..."
if ! minikube status > /dev/null 2>&1; then
    echo "  ⚠️  Minikube not running. Starting..."
    make minikube-start
else
    echo "  ✅ Minikube is running"
fi
echo ""

# Set kubectl context
echo "🎯 Setting kubectl context to Minikube..."
make kubectl-context
echo ""

# Verify cluster
echo "🔍 Verifying cluster accessibility..."
make verify-cluster
echo ""

echo "✅ Local environment is ready!"
echo ""
echo "📚 Quick Reference:"
echo "  View status:        make minikube-status"
echo "  Build services:     make build"
echo "  Run tests:          make test"
echo "  Initialize project: bash scripts/init-project-structure.sh"
echo "  Deploy to dev:      helm install <service> ./charts/<service> -n dev"
echo ""
