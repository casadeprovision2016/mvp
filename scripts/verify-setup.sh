#!/bin/bash

###############################################################################
# Cotai MVP - Workstation Verification
#
# Purpose: Verify that all required development tools are installed
# Usage: bash scripts/verify-setup.sh
###############################################################################

# Note: NOT using 'set -e' to allow non-blocking validation of tools

echo "🔍 Verifying Cotai MVP workstation setup..."
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TOOLS_OK=0
TOOLS_MISSING=0

# Check each required tool
check_tool() {
    local tool=$1
    local min_version=$2
    
    if command -v "$tool" &> /dev/null; then
        echo -e "  ${GREEN}✅${NC} $tool (installed)"
        ((TOOLS_OK++))
    else
        echo -e "  ${RED}❌${NC} $tool (NOT INSTALLED)"
        ((TOOLS_MISSING++))
    fi
}

echo "📦 Required Tools:"
check_tool "git" "2.20"
check_tool "docker" "24.0"
check_tool "minikube" "1.31"
check_tool "kubectl" "1.27"
check_tool "helm" "3.12"
check_tool "go" "1.21"
check_tool "python3" "3.11"
check_tool "golangci-lint" "1.54"
check_tool "trivy" "0.45"
check_tool "buf" "1.28"
echo ""

# Optional tools
echo "📚 Optional Tools:"
check_tool "make" "-"
check_tool "java" "17"
check_tool "gradle" "-"
echo ""

# Cluster status
echo "🖥️  Cluster Status:"
if minikube status > /dev/null 2>&1; then
    echo -e "  ${GREEN}✅${NC} Minikube is running"
else
    echo -e "  ${YELLOW}⚠️${NC} Minikube is not running (run: make minikube-start)"
fi
echo ""

# Git configuration
echo "🔧 Git Configuration:"
if git config user.name > /dev/null 2>&1; then
    echo -e "  ${GREEN}✅${NC} git user.name configured"
else
    echo -e "  ${RED}❌${NC} git user.name not configured (run: git config --global user.name 'Your Name')"
fi

if git config user.email > /dev/null 2>&1; then
    echo -e "  ${GREEN}✅${NC} git user.email configured"
else
    echo -e "  ${RED}❌${NC} git user.email not configured (run: git config --global user.email 'your.email@example.com')"
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════╗"
if [ $TOOLS_MISSING -eq 0 ]; then
    echo -e "║ Setup Verification: ${GREEN}✅ PASSED${NC}                         ║"
else
    echo -e "║ Setup Verification: ${RED}⚠️  INCOMPLETE${NC}                     ║"
fi
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "Tools OK: $TOOLS_OK"
if [ $TOOLS_MISSING -gt 0 ]; then
    echo "Missing: $TOOLS_MISSING (see above)"
    echo ""
    echo "💡 Install missing tools with: bash scripts/setup-workstation.sh"
    exit 1
else
    echo "✅ All required tools are installed!"
fi
echo ""
