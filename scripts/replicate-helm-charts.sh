#!/bin/bash
set -euo pipefail

# Script to replicate Helm chart structure from auth-service to other services
# Usage: ./replicate-helm-charts.sh

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Services to replicate to (excluding auth-service as it's the source)
SERVICES=(
  "edital-service"
  "procurement-service"
  "bidding-service"
  "notification-service"
  "audit-service"
  "api-gateway"
)

SOURCE_SERVICE="auth-service"
SOURCE_CHART_DIR="/home/felipe/dev/mvp/${SOURCE_SERVICE}/charts/${SOURCE_SERVICE}"

echo -e "${GREEN}=== Helm Chart Replication Script ===${NC}"
echo -e "Source: ${SOURCE_SERVICE}"
echo -e "Target services: ${SERVICES[*]}"
echo ""

# Function to replicate chart to a service
replicate_chart() {
  local service=$1
  local target_chart_dir="/home/felipe/dev/mvp/${service}/charts/${service}"
  
  echo -e "${YELLOW}Processing ${service}...${NC}"
  
  # Create charts directory
  mkdir -p "${target_chart_dir}/templates"
  
  # Copy all files from source
  cp -r "${SOURCE_CHART_DIR}"/* "${target_chart_dir}/"
  
  # Replace service-specific strings in all files
  find "${target_chart_dir}" -type f \( -name "*.yaml" -o -name "*.tpl" -o -name "*.txt" \) -exec sed -i "s/auth-service/${service}/g" {} +
  find "${target_chart_dir}" -type f \( -name "*.yaml" -o -name "*.tpl" -o -name "*.txt" \) -exec sed -i "s/Auth Service/${service//-/ } Service/g" {} +
  find "${target_chart_dir}" -type f \( -name "*.yaml" -o -name "*.tpl" -o -name "*.txt" \) -exec sed -i "s/cotai-auth/cotai-${service%-service}/g" {} +
  find "${target_chart_dir}" -type f \( -name "*.yaml" -o -name "*.tpl" -o -name "*.txt" \) -exec sed -i "s/cotai_auth/${service//-/_}/g" {} +
  
  # Service-specific adjustments
  case "${service}" in
    "api-gateway")
      # API Gateway doesn't need PostgreSQL/Redis dependencies
      sed -i '/dependencies:/,/tags:/d' "${target_chart_dir}/Chart.yaml"
      sed -i '/postgresql:/,/^$/d' "${target_chart_dir}/values.yaml"
      sed -i '/redis:/,/^$/d' "${target_chart_dir}/values.yaml"
      sed -i '/postgresql:/,/^$/d' "${target_chart_dir}/values-dev.yaml"
      sed -i '/redis:/,/^$/d' "${target_chart_dir}/values-dev.yaml"
      # API Gateway uses HTTP/REST, not just gRPC
      sed -i 's/grpcPort: 50051/httpPort: 8080/' "${target_chart_dir}/values.yaml"
      ;;
    "notification-service")
      # Notification service doesn't need PostgreSQL (event-driven)
      sed -i '/- name: postgresql/,/tags:/d' "${target_chart_dir}/Chart.yaml"
      sed -i '/postgresql:/,/enabled: false/d' "${target_chart_dir}/values.yaml"
      sed -i '/postgresql:/,/resources:/d' "${target_chart_dir}/values-dev.yaml"
      ;;
    "audit-service")
      # Audit service might use different database (keep PostgreSQL but adjust)
      sed -i 's/DATABASE_NAME: cotai_audit/DATABASE_NAME: cotai_audit_log/' "${target_chart_dir}/values.yaml"
      ;;
  esac
  
  # Update dependencies
  echo "  Updating Helm dependencies..."
  (cd "${target_chart_dir}" && helm dependency update > /dev/null 2>&1) || true
  
  # Lint the chart
  echo "  Linting chart..."
  if helm lint "${target_chart_dir}" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓ Chart linted successfully${NC}"
  else
    echo -e "  ${RED}✗ Chart linting failed${NC}"
    helm lint "${target_chart_dir}"
  fi
  
  echo ""
}

# Main execution
for service in "${SERVICES[@]}"; do
  replicate_chart "${service}"
done

echo -e "${GREEN}=== Replication Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Review each service's Chart.yaml for service-specific dependencies"
echo "2. Adjust values.yaml for service-specific configurations"
echo "3. Test rendering: helm template <service> <chart-dir> -f <values-file>"
echo "4. Deploy to development: helm install <service> <chart-dir> -f values-dev.yaml"
