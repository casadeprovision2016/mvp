# GCP Production Deployment Guide

## 🎯 Overview

This guide covers deploying the Cotai MVP platform to Google Cloud Platform (GCP) for staging and production environments. Infrastructure is provisioned using Terraform for repeatability and version control.

---

## 📋 Prerequisites

###Tools Required

| Tool | Version | Purpose |
|------|---------|---------|
| **gcloud CLI** | Latest | GCP interaction |
| **Terraform** | 1.5+ | Infrastructure as Code |
| **kubectl** | 1.27+ | Kubernetes management |
| **Helm** | 3.12+ | Service deployment |

### Installation

```bash
# gcloud CLI
# macOS: brew install --cask google-cloud-sdk
# Linux: curl https://sdk.cloud.google.com | bash

# Terraform
# macOS: brew install terraform
# Linux: https://developer.hashicorp.com/terraform/downloads

# Authenticate with GCP
gcloud auth login
gcloud auth application-default login
```

### GCP Project Setup

```bash
# Set project variables
export GCP_PROJECT_ID="cotai-production"
export GCP_REGION="us-central1"
export GCP_ZONE="us-central1-a"

# Create project (if needed)
gcloud projects create $GCP_PROJECT_ID --name="Cotai Production"

# Set default project
gcloud config set project $GCP_PROJECT_ID

# Enable required APIs
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  sqladmin.googleapis.com \
  redis.googleapis.com \
  pubsub.googleapis.com \
  secretmanager.googleapis.com \
  cloudresourcemanager.googleapis.com \
  servicenetworking.googleapis.com \
  cloudtrace.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com
```

---

## 🏗️ Infrastructure Architecture

### GCP Resources Overview

```
GCP Project: cotai-production
├── VPC Network: cotai-vpc
│   ├── Subnet: gke-subnet (10.0.0.0/20)
│   ├── Subnet: services-subnet (10.1.0.0/20)
│   └── Private Service Connection
├── GKE Cluster: cotai-gke-prod
│   ├── Node Pool: general-pool (e2-standard-4, 3-10 nodes)
│   └── Node Pool: spot-pool (e2-standard-4, 0-5 nodes)
├── Cloud SQL: cotai-postgres-prod (db-n1-standard-2, HA)
├── Memorystore Redis: cotai-redis-prod (5GB, Standard tier)
├── Cloud Pub/Sub:
│   ├── Topics: edital-events, bidding-events, notification-events
│   └── Subscriptions: (per service)
├── Secret Manager: (JWT secrets, DB passwords, API keys)
└── Cloud Storage: cotai-backups-prod
```

---

## 📁 Step 1: Terraform Infrastructure Setup

### Directory Structure

```bash
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
├── modules/
│   ├── gke/
│   ├── cloud-sql/
│   ├── memorystore/
│   ├── vpc/
│   └── pubsub/
└── README.md
```

### Initialize Terraform

```bash
cd terraform/environments/prod

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan changes
terraform plan -out=tfplan

# Apply (create infrastructure)
terraform apply tfplan
```

---

## 🌐 Step 2: VPC and Networking

### Terraform Module: VPC

Create `terraform/modules/vpc/main.tf`:

```hcl
variable "project_id" {}
variable "region" {}
variable "network_name" { default = "cotai-vpc" }

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "gke_subnet" {
  name          = "gke-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }

  private_ip_google_access = true
}

resource "google_compute_global_address" "private_ip_range" {
  name          = "private-service-connection"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
  project       = var.project_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "subnet_name" {
  value = google_compute_subnetwork.gke_subnet.name
}
```

---

## ☸️ Step 3: GKE Cluster Provisioning

### Terraform Module: GKE

Create `terraform/modules/gke/main.tf`:

```hcl
variable "project_id" {}
variable "region" {}
variable "network" {}
variable "subnetwork" {}
variable "cluster_name" { default = "cotai-gke-prod" }

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  # VPC-native cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Network policy
  network_policy {
    enabled = true
  }

  # Binary Authorization
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }
}

resource "google_container_node_pool" "general_pool" {
  name       = "general-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  project    = var.project_id

  initial_node_count = 3

  autoscaling {
    min_node_count = 3
    max_node_count = 10
  }

  node_config {
    machine_type = "e2-standard-4"
    disk_size_gb = 100
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env = "production"
      pool = "general"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

resource "google_container_node_pool" "spot_pool" {
  name       = "spot-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  project    = var.project_id

  initial_node_count = 0

  autoscaling {
    min_node_count = 0
    max_node_count = 5
  }

  node_config {
    machine_type = "e2-standard-4"
    disk_size_gb = 100
    disk_type    = "pd-standard"
    spot         = true

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env  = "production"
      pool = "spot"
    }

    taint {
      key    = "workload-type"
      value  = "batch"
      effect = "NO_SCHEDULE"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}
```

### Connect to GKE Cluster

```bash
# Get cluster credentials
gcloud container clusters get-credentials cotai-gke-prod \
  --region us-central1 \
  --project cotai-production

# Verify connection
kubectl cluster-info
kubectl get nodes
```

---

## 🗄️ Step 4: Cloud SQL (PostgreSQL)

### Terraform Module: Cloud SQL

Create `terraform/modules/cloud-sql/main.tf`:

```hcl
variable "project_id" {}
variable "region" {}
variable "network_id" {}
variable "instance_name" { default = "cotai-postgres-prod" }

resource "google_sql_database_instance" "postgres" {
  name             = var.instance_name
  database_version = "POSTGRES_15"
  region           = var.region
  project          = var.project_id

  settings {
    tier              = "db-n1-standard-2"
    availability_type = "REGIONAL"  # High availability
    disk_size         = 100
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      require_ssl     = true
    }

    database_flags {
      name  = "max_connections"
      value = "200"
    }

    database_flags {
      name  = "shared_buffers"
      value = "2097152"  # 2GB in 8kB pages
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
    }
  }

  deletion_protection = true
}

resource "google_sql_database" "databases" {
  for_each = toset([
    "cotai_auth",
    "cotai_edital",
    "cotai_procurement",
    "cotai_bidding",
    "cotai_notification",
    "cotai_audit"
  ])

  name     = each.key
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
}

resource "google_sql_user" "app_user" {
  name     = "cotai_app"
  instance = google_sql_database_instance.postgres.name
  password = random_password.app_password.result
  project  = var.project_id
}

resource "random_password" "app_password" {
  length  = 32
  special = true
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "cotai-db-password"
  project   = var.project_id

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.app_password.result
}

output "instance_connection_name" {
  value = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  value = google_sql_database_instance.postgres.private_ip_address
}
```

### Cloud SQL Proxy (for GKE connection)

```bash
# Deploy Cloud SQL Proxy as sidecar in Helm values
# values-prod.yaml additions:
cloudSqlProxy:
  enabled: true
  instanceConnectionName: "cotai-production:us-central1:cotai-postgres-prod"
  serviceAccount: "cloud-sql-proxy@cotai-production.iam.gserviceaccount.com"
```

---

## 📦 Step 5: Memorystore Redis

### Terraform Module: Memorystore

Create `terraform/modules/memorystore/main.tf`:

```hcl
variable "project_id" {}
variable "region" {}
variable "network_id" {}
variable "instance_name" { default = "cotai-redis-prod" }

resource "google_redis_instance" "cache" {
  name           = var.instance_name
  tier           = "STANDARD_HA"
  memory_size_gb = 5
  region         = var.region
  project        = var.project_id

  authorized_network = var.network_id

  redis_version = "REDIS_7_0"

  display_name = "Cotai Production Redis"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 2
        minutes = 0
      }
    }
  }
}

output "host" {
  value = google_redis_instance.cache.host
}

output "port" {
  value = google_redis_instance.cache.port
}
```

---

## 📨 Step 6: Cloud Pub/Sub

### Terraform Module: Pub/Sub

Create `terraform/modules/pubsub/main.tf`:

```hcl
variable "project_id" {}

locals {
  topics = {
    "edital-events"       = { retention = "7d" }
    "bidding-events"      = { retention = "7d" }
    "notification-events" = { retention = "3d" }
    "audit-events"        = { retention = "30d" }
  }
}

resource "google_pubsub_topic" "topics" {
  for_each = local.topics

  name    = each.key
  project = var.project_id

  message_retention_duration = each.value.retention
}

resource "google_pubsub_topic" "dead_letter_topics" {
  for_each = local.topics

  name    = "${each.key}-dlq"
  project = var.project_id
}

resource "google_pubsub_subscription" "subscriptions" {
  for_each = local.topics

  name    = "${each.key}-sub"
  topic   = google_pubsub_topic.topics[each.key].name
  project = var.project_id

  ack_deadline_seconds = 60

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topics[each.key].id
    max_delivery_attempts = 5
  }

  expiration_policy {
    ttl = "2678400s"  # 31 days
  }
}

output "topic_names" {
  value = [for topic in google_pubsub_topic.topics : topic.name]
}
```

---

## 🔐 Step 7: Secret Manager & Workload Identity

### Create Secrets

```bash
# Create secrets in Secret Manager
gcloud secrets create cotai-jwt-secret \
  --data-file=- \
  --replication-policy=automatic \
  --project=cotai-production <<EOF
$(openssl rand -base64 32)
EOF

gcloud secrets create cotai-auth-db-password \
  --data-file=- \
  --replication-policy=automatic \
  --project=cotai-production <<EOF
$(openssl rand -base64 24)
EOF

# Grant access to GKE service accounts (via Workload Identity)
gcloud iam service-accounts create auth-service-sa \
  --project=cotai-production

gcloud projects add-iam-policy-binding cotai-production \
  --member="serviceAccount:auth-service-sa@cotai-production.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Bind Kubernetes SA to GCP SA
gcloud iam service-accounts add-iam-policy-binding \
  auth-service-sa@cotai-production.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:cotai-production.svc.id.goog[production/auth-service]" \
  --project=cotai-production
```

### Install External Secrets Operator

```bash
# Add Helm repo
helm repo add external-secrets https://charts.external-secrets.io

# Install operator
helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace
```

See [External Secrets documentation](./EXTERNAL-SECRETS.md) for detailed configuration.

---

## 🚀 Step 8: Deploy Services to GKE

```bash
# Update Helm values with production endpoints
# values-prod.yaml should have:
# DATABASE_HOST: <Cloud SQL private IP>
# REDIS_HOST: <Memorystore host>

# Deploy services
for service in auth edital procurement bidding notification audit api-gateway; do
  helm upgrade --install "${service}-service" \
    "./${service}-service/charts/${service}-service" \
    -f "./${service}-service/charts/${service}-service/values-prod.yaml" \
    --set image.tag="v1.0.0" \
    --namespace production \
    --create-namespace \
    --atomic --wait --timeout 10m
done

# Verify
kubectl get pods -n production
kubectl get svc -n production
```

---

## 📊 Step 9: Monitoring & Observability

### Cloud Monitoring Integration

```bash
# GKE automatically sends logs to Cloud Logging
# View logs
gcloud logging read "resource.type=k8s_container" --limit 50

# Create log-based metrics
gcloud logging metrics create error_rate \
  --description="Application error rate" \
  --log-filter='severity=ERROR'
```

### Alerting Policies

```bash
# Create alert for high error rate
gcloud alpha monitoring policies create \
  --notification-channels=<CHANNEL_ID> \
  --display-name="High Error Rate" \
  --condition-display-name="Error rate > 1%" \
  --condition-threshold-value=0.01 \
  --condition-threshold-duration=300s
```

---

## 💰 Step 10: Cost Optimization

### Enable Committed Use Discounts

```bash
# Purchase 1-year commitment (37% discount)
gcloud compute commitments create cotai-commitment \
  --region=us-central1 \
  --resources=vcpu=16,memory=64GB \
  --plan=twelve-month
```

### Setup Cloud Billing Alerts

```bash
# Create budget alert
gcloud billing budgets create \
  --billing-account=<BILLING_ACCOUNT_ID> \
  --display-name="Cotai Production Budget" \
  --budget-amount=1500USD \
  --threshold-rule=percent=80 \
  --threshold-rule=percent=100
```

---

## 🧹 Cleanup (Development/Testing Only)

```bash
# Destroy Terraform infrastructure
cd terraform/environments/prod
terraform destroy

# Or manually delete resources
gcloud container clusters delete cotai-gke-prod --region=us-central1
gcloud sql instances delete cotai-postgres-prod
gcloud redis instances delete cotai-redis-prod --region=us-central1
```

---

## 📚 Additional Resources

- [Terraform Modules](../terraform/modules/)
- [External Secrets Configuration](./EXTERNAL-SECRETS.md)
- [Deployment Validation](./DEPLOYMENT-VALIDATION.md)
- [Cost Optimization Guide](./COST-OPTIMIZATION.md)

---

**Last Updated**: December 2024  
**Maintainer**: Cotai DevOps Team
