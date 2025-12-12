#!/bin/bash

###############################################################################
# Cotai Workstation Setup & Validation Script
#
# Purpose: Validate or install required tools for Cotai development
# Usage: bash scripts/setup-workstation.sh
#
# Supported Platforms: Linux (Ubuntu/Debian), macOS
# Requirements: bash 4+, sudo access for package installation
###############################################################################

set -euo pipefail

# Configuration
REQUIRED_TOOLS=(
  "git:2.20"
  "docker:24.0"
  "minikube:1.31"
  "kubectl:1.27"
  "helm:3.12"
  "go:1.21"
  "python:3.11"
  "java:17"
  "golangci-lint:1.54"
  "trivy:0.45"
  "buf:1.28"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOOLS_OK=0
TOOLS_MISSING=0
TOOLS_OUTDATED=0

###############################################################################
# Helper Functions
###############################################################################

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# Compare semantic versions
# Returns 0 if installed >= required, 1 otherwise
version_gte() {
  local installed=$1
  local required=$2
  
  # Handle 'v' prefix (e.g., 'v1.21.0' → '1.21.0')
  installed="${installed#v}"
  required="${required#v}"
  
  # Simple comparison: convert to integers for major.minor.patch
  # For complex versions, use sort -V
  printf '%s\n%s' "$required" "$installed" | sort -V -C
}

###############################################################################
# Tool Checks
###############################################################################

check_git() {
  local required="2.20"
  if command -v git &> /dev/null; then
    local installed=$(git --version | awk '{print $3}')
    if version_gte "$installed" "$required"; then
      log_success "git $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "git $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "git not found"
    ((TOOLS_MISSING++))
    install_git
  fi
}

check_docker() {
  local required="24.0"
  if command -v docker &> /dev/null; then
    local installed=$(docker --version | awk '{print $3}' | sed 's/,//')
    if version_gte "$installed" "$required"; then
      log_success "docker $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "docker $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "docker not found"
    ((TOOLS_MISSING++))
    install_docker
  fi
}

check_minikube() {
  local required="1.31"
  if command -v minikube &> /dev/null; then
    local installed=$(minikube version | grep -oP 'v\K[0-9.]+' | head -1)
    if version_gte "$installed" "$required"; then
      log_success "minikube $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "minikube $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "minikube not found"
    ((TOOLS_MISSING++))
    install_minikube
  fi
}

check_kubectl() {
  local required="1.27"
  if command -v kubectl &> /dev/null; then
    local installed=$(kubectl version --client --short 2>/dev/null | grep -oP 'v\K[0-9.]+' | head -1)
    if version_gte "$installed" "$required"; then
      log_success "kubectl $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "kubectl $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "kubectl not found"
    ((TOOLS_MISSING++))
    install_kubectl
  fi
}

check_helm() {
  local required="3.12"
  if command -v helm &> /dev/null; then
    local installed=$(helm version --short 2>/dev/null | grep -oP 'v\K[0-9.]+' | head -1)
    if version_gte "$installed" "$required"; then
      log_success "helm $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "helm $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "helm not found"
    ((TOOLS_MISSING++))
    install_helm
  fi
}

check_go() {
  local required="1.21"
  if command -v go &> /dev/null; then
    local installed=$(go version | grep -oP 'go\K[0-9.]+' | head -1)
    if version_gte "$installed" "$required"; then
      log_success "go $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "go $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "go not found"
    ((TOOLS_MISSING++))
    install_go
  fi
}

check_python() {
  local required="3.11"
  if command -v python3 &> /dev/null; then
    local installed=$(python3 --version 2>&1 | grep -oP 'Python \K[0-9.]+')
    if version_gte "$installed" "$required"; then
      log_success "python3 $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "python3 $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "python3 not found"
    ((TOOLS_MISSING++))
    install_python
  fi
}

check_java() {
  local required="17"
  if command -v java &> /dev/null; then
    local installed=$(java -version 2>&1 | grep -oP 'version "\K[0-9.]+' | head -1 | cut -d. -f1)
    if [[ -z "$installed" ]]; then
      installed=$(java -version 2>&1 | grep -oP '"?\K[0-9]+' | head -1)
    fi
    if [[ "$installed" -ge "$required" ]]; then
      log_success "java $installed (required: >= $required)"
      ((TOOLS_OK++))
    else
      log_warn "java $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "java not found"
    ((TOOLS_MISSING++))
    install_java
  fi
}

check_golangci_lint() {
  local required="1.54"
  if command -v golangci-lint &> /dev/null; then
    local installed=$(golangci-lint --version | grep -oP 'version \K[0-9.]+' | head -1)
    if version_gte "$installed" "$required"; then
      log_success "golangci-lint $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "golangci-lint $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "golangci-lint not found"
    ((TOOLS_MISSING++))
    install_golangci_lint
  fi
}

check_trivy() {
  local required="0.45"
  if command -v trivy &> /dev/null; then
    local installed=$(trivy --version 2>&1 | grep -oP 'version \K[0-9.]+' | head -1)
    if version_gte "$installed" "$required"; then
      log_success "trivy $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "trivy $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "trivy not found"
    ((TOOLS_MISSING++))
    install_trivy
  fi
}

check_buf() {
  local required="1.28"
  if command -v buf &> /dev/null; then
    local installed=$(buf --version 2>&1 | grep -oP '[0-9.]+' | head -1)
    if version_gte "$installed" "$required"; then
      log_success "buf $installed (required: $required)"
      ((TOOLS_OK++))
    else
      log_warn "buf $installed (required: >= $required)"
      ((TOOLS_OUTDATED++))
    fi
  else
    log_error "buf not found"
    ((TOOLS_MISSING++))
    install_buf
  fi
}

###############################################################################
# Tool Installation (Platform-Specific)
###############################################################################

detect_os() {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      echo "$ID"
    fi
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  fi
}

install_git() {
  log_warn "Please install git manually or use your package manager:"
  if [[ $(detect_os) == "ubuntu" ]] || [[ $(detect_os) == "debian" ]]; then
    echo "  sudo apt-get install -y git"
  elif [[ $(detect_os) == "macos" ]]; then
    echo "  brew install git"
  fi
}

install_docker() {
  log_warn "Please install Docker Desktop or follow: https://docs.docker.com/get-docker/"
}

install_minikube() {
  log_info "Installing minikube..."
  if [[ $(detect_os) == "macos" ]]; then
    command -v brew &> /dev/null && brew install minikube || \
      curl -LO https://github.com/kubernetes/minikube/releases/download/v1.32.0/minikube-darwin-amd64 && \
      chmod +x minikube-darwin-amd64 && \
      sudo mv minikube-darwin-amd64 /usr/local/bin/minikube
  else
    curl -LO https://github.com/kubernetes/minikube/releases/download/v1.32.0/minikube-linux-amd64 && \
    chmod +x minikube-linux-amd64 && \
    sudo mv minikube-linux-amd64 /usr/local/bin/minikube
  fi
  log_success "minikube installed"
}

install_kubectl() {
  log_info "Installing kubectl..."
  if [[ $(detect_os) == "macos" ]]; then
    command -v brew &> /dev/null && brew install kubectl || \
      curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl" && \
      chmod +x kubectl && \
      sudo mv kubectl /usr/local/bin/
  else
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    sudo mv kubectl /usr/local/bin/
  fi
  log_success "kubectl installed"
}

install_helm() {
  log_info "Installing helm..."
  if [[ $(detect_os) == "macos" ]]; then
    command -v brew &> /dev/null && brew install helm || \
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
  log_success "helm installed"
}

install_go() {
  log_warn "Please install Go 1.21+ from: https://go.dev/dl/"
  if [[ $(detect_os) == "ubuntu" ]] || [[ $(detect_os) == "debian" ]]; then
    echo "  Or: sudo apt-get install -y golang-1.21"
  elif [[ $(detect_os) == "macos" ]]; then
    echo "  Or: brew install go"
  fi
}

install_python() {
  log_warn "Please install Python 3.11+ from: https://www.python.org/downloads/"
  if [[ $(detect_os) == "ubuntu" ]] || [[ $(detect_os) == "debian" ]]; then
    echo "  Or: sudo apt-get install -y python3.11 python3.11-venv"
  elif [[ $(detect_os) == "macos" ]]; then
    echo "  Or: brew install python@3.11"
  fi
}

install_java() {
  log_warn "Please install Java 17+ (OpenJDK or Oracle JDK)"
  if [[ $(detect_os) == "ubuntu" ]] || [[ $(detect_os) == "debian" ]]; then
    echo "  sudo apt-get install -y openjdk-17-jdk"
  elif [[ $(detect_os) == "macos" ]]; then
    echo "  brew install openjdk@17"
  fi
}

install_golangci_lint() {
  log_info "Installing golangci-lint..."
  curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin" v1.54.2
  log_success "golangci-lint installed"
}

install_trivy() {
  log_info "Installing trivy..."
  if [[ $(detect_os) == "macos" ]]; then
    command -v brew &> /dev/null && brew install aquasecurity/trivy/trivy || \
      curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
  else
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
  fi
  log_success "trivy installed"
}

install_buf() {
  log_info "Installing buf..."
  BUF_VERSION="1.28.1"
  if [[ $(detect_os) == "macos" ]]; then
    curl -sSL "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-Darwin-x86_64.tar.gz" | tar xz -C /usr/local/bin
  else
    curl -sSL "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-Linux-x86_64.tar.gz" | tar xz -C /usr/local/bin
  fi
  log_success "buf installed"
}

###############################################################################
# Additional Checks
###############################################################################

check_docker_daemon() {
  log_info "Checking Docker daemon..."
  if docker ps &> /dev/null; then
    log_success "Docker daemon is running"
  else
    log_error "Docker daemon is not running. Please start Docker and try again."
    return 1
  fi
}

check_disk_space() {
  log_info "Checking available disk space..."
  local available=$(df -h . | tail -1 | awk '{print $4}' | sed 's/G//')
  if (( $(echo "$available > 50" | bc -l) )); then
    log_success "Sufficient disk space available (${available}G free)"
  else
    log_warn "Low disk space (${available}G free). Recommend 50G+ for Kubernetes + development"
  fi
}

check_git_config() {
  log_info "Checking git configuration..."
  if ! git config user.name &> /dev/null; then
    log_warn "git user.name not configured. Run: git config --global user.name 'Your Name'"
  fi
  if ! git config user.email &> /dev/null; then
    log_warn "git user.email not configured. Run: git config --global user.email 'your.email@example.com'"
  fi
}

###############################################################################
# Main
###############################################################################

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║   Cotai Workstation Setup & Validation                     ║"
  echo "║   Ensuring all development tools are installed & updated   ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""

  log_info "Starting system checks..."
  echo ""

  # Detect OS
  local os=$(detect_os)
  log_info "Detected OS: $os"
  echo ""

  # Check all tools
  log_info "Checking required tools..."
  check_git
  check_docker
  check_minikube
  check_kubectl
  check_helm
  check_go
  check_python
  check_java
  check_golangci_lint
  check_trivy
  check_buf
  echo ""

  # Additional checks
  check_docker_daemon || exit 1
  echo ""
  check_disk_space
  echo ""
  check_git_config
  echo ""

  # Summary
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║   Setup Summary                                            ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  log_success "Tools OK: $TOOLS_OK"
  if [[ $TOOLS_OUTDATED -gt 0 ]]; then
    log_warn "Tools Outdated: $TOOLS_OUTDATED"
  fi
  if [[ $TOOLS_MISSING -gt 0 ]]; then
    log_error "Tools Missing: $TOOLS_MISSING"
  fi
  echo ""

  if [[ $TOOLS_MISSING -eq 0 && $TOOLS_OUTDATED -eq 0 ]]; then
    log_success "✓ All tools validated successfully!"
    echo ""
    log_info "Next steps:"
    echo "  1. Start local Kubernetes cluster: make local-setup"
    echo "  2. Build services: make build"
    echo "  3. Run tests: make test"
    echo "  4. Deploy locally: make deploy-local"
    echo ""
    return 0
  else
    log_error "✗ Please install missing tools or update outdated ones"
    echo ""
    return 1
  fi
}

main "$@"
