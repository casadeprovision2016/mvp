# Infrastructure as Code - Deployment Decisions

## Overview
This document outlines the infrastructure provisioning decisions for the Cotai MVP microservices platform, focusing on cluster dependencies, deployment strategies, and rationale for technology choices across development, staging, and production environments.

## Dependency Management Strategy

### PostgreSQL Database

| Environment | Provisioning Method | Rationale | Cost Consideration |
|-------------|---------------------|-----------|-------------------|
| **Development** | Bitnami Helm Chart (in-cluster) | Fast local development, no external dependencies, easy teardown | Zero cost (runs in local Minikube/Kind) |
| **Staging** | Google Cloud SQL (managed) | Pre-production environment mirrors production, automated backups | ~$50-100/month for db-f1-micro |
| **Production** | Google Cloud SQL with HA | Automated backups, point-in-time recovery, automatic failover, security patches, connection pooling | ~$200-500/month for db-n1-standard-2 with HA |

**Key Configuration Decisions**:
- **SSL Mode**: `require` in staging/prod, `disable` in dev
- **Connection Pooling**: PgBouncer sidecar in production for connection management
- **Backup Strategy**: Automated daily backups with 7-day retention (prod), 3-day (staging)
- **Migration from Local to Cloud**:
  - Use Cloud SQL Proxy in Kubernetes for secure connections
  - Enable Private Service Connect for VPC-native clusters
  - Use Workload Identity for authentication (no passwords in pods)

---

### Redis Cache

| Environment | Provisioning Method | Rationale | Cost Consideration |
|-------------|---------------------|-----------|-------------------|
| **Development** | Bitnami Helm Chart (standalone) | Simple setup, no persistence needed for dev | Zero cost (local) |
| **Staging** | Google Memorystore for Redis (Basic tier) | Low-latency, managed service, automatic patching | ~$25-50/month for 1GB Basic |
| **Production** | Memorystore for Redis (Standard tier with HA) | Automatic failover, read replicas, 99.9% SLA | ~$100-200/month for 5GB Standard |

**Key Configuration Decisions**:
- **Persistence**: Disabled in dev (ephemeral), AOF in staging/prod
- **Eviction Policy**: `allkeys-lru` for cache use cases
- **Connection**: VPC-native connectivity (private IP only)
- **High Availability**: Standard tier with automatic failover in production

---

### Message Broker (RabbitMQ / Pub/Sub)

| Environment | Provisioning Method | Rationale | Cost Consideration |
|-------------|---------------------|-----------|-------------------|
| **Development** | Bitnami RabbitMQ Helm Chart | Local development, message inspection via management UI | Zero cost (local) |
| **Staging** | Google Cloud Pub/Sub | Serverless, no infrastructure to manage, automatic scaling | Pay-per-use: ~$10-30/month |
| **Production** | Cloud Pub/Sub with regional endpoints | Serverless, global distribution, automatic scaling, 99.95% SLA | Pay-per-use: ~$50-200/month depending on volume |

**Migration Path**:
- **Phase 1 (MVP)**: Use RabbitMQ for development
- **Phase 2 (Production)**: Migrate to Cloud Pub/Sub for serverless scalability
- **Alternative**: Cloud Run for RabbitMQ if AMQP protocol compatibility is required

**Key Configuration Decisions**:
- **Message Retention**: 7 days in Pub/Sub
- **Dead Letter Topics**: Configured for failed message handling
- **Ordering**: Message ordering enabled for critical workflows (bidding, procurement)
- **Authentication**: Service account-based (Workload Identity)

---

### Observability Stack

#### Metrics: Prometheus & Grafana

| Environment | Provisioning Method | Rationale | Cost Consideration |
|-------------|---------------------|-----------|-------------------|
| **Development** | Prometheus Community Helm Chart | Full stack locally, instant feedback | Zero cost (local) |
| **Staging** | Managed Service for Prometheus (GMP) | Managed, no maintenance, integrated with Cloud Monitoring | ~$20-50/month for small workload |
| **Production** | Managed Service for Prometheus + Cloud Monitoring | Centralized metrics, long-term storage, alerting via Cloud Monitoring | ~$100-300/month depending on metric volume |

**Key Configuration Decisions**:
- **Scrape Interval**: 30s for all services
- **Retention**: 15 days local (dev), 90 days Cloud Monitoring (prod)
- **Dashboards**: Grafana in dev, Cloud Monitoring dashboards in prod
- **Alerting**: Prometheus Alertmanager in dev, Cloud Monitoring Alerts in prod

#### Logs: Fluentd / Cloud Logging

| Environment | Provisioning Method | Rationale | Cost Consideration |
|-------------|---------------------|-----------|-------------------|
| **Development** | `kubectl logs` + local log aggregation | Simple, no infrastructure | Zero cost |
| **Staging/Production** | Cloud Logging (GKE native integration) | Centralized logging, log-based metrics, long-term storage | ~$50-200/month (first 50GB free) |

**Key Configuration Decisions**:
- **Log Format**: Structured JSON logs with correlation IDs
- **Log Levels**: DEBUG in dev, INFO in staging, WARN in prod
- **Sampling**: No sampling in dev/staging, 10% sampling for verbose logs in prod
- **Retention**: 30 days in staging, 90 days in prod
- **Export**: Critical logs exported to BigQuery for long-term analysis

#### Tracing: Jaeger / Cloud Trace

| Environment | Provisioning Method | Rationale | Cost Consideration |
|-------------|---------------------|-----------|-------------------|
| **Development** | Jaeger All-in-One Helm Chart | Local trace inspection, debugging | Zero cost |
| **Staging/Production** | Cloud Trace (GCP native) | Managed service, integrated with Cloud Monitoring, automatic trace sampling | ~$20-100/month (first 2.5M spans free) |

**Key Configuration Decisions**:
- **Sampling Rate**: 100% in dev, 50% in staging, 10% in prod
- **Trace Context**: W3C Trace Context standard for interoperability
- **Integration**: OpenTelemetry SDK in all services
- **Exporter**: OTLP exporter to Cloud Trace in prod

---

## Secret Management

| Environment | Method | Rationale |
|-------------|--------|-----------|
| **Development** | Kubernetes Secrets (base64) | Simple, local only, acceptable for dev |
| **Staging** | External Secrets Operator + GCP Secret Manager | Centralized secret management, audit logging |
| **Production** | External Secrets Operator + GCP Secret Manager + Secret Rotation | Enterprise-grade secret management, automatic rotation, audit logs |

**Implementation**:
```yaml
# Example: ExternalSecret for database credentials
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: auth-db-credentials
spec:
  secretStoreRef:
    name: gcpsm-secret-store
    kind: SecretStore
  target:
    name: auth-db-credentials
  data:
    - secretKey: password
      remoteRef:
        key: cotai-auth-db-password
```

**Key Configuration Decisions**:
- **Secret Rotation**: 90-day rotation for database passwords in prod
- **Access Control**: IAM-based access with Workload Identity
- **Audit**: All secret access logged in Cloud Audit Logs
- **Encryption**: Customer-managed encryption keys (CMEK) for sensitive secrets in prod

---

## Cost Optimization Strategies

### Development Environment
- **Goal**: Zero external costs
- **Strategy**: All services run in local Kubernetes (Minikube/Kind)
- **Estimated Cost**: $0/month

### Staging Environment
- **Goal**: Minimal cost while mirroring production
- **Infrastructure**:
  - GKE Autopilot cluster (1-3 nodes): ~$100/month
  - Cloud SQL (db-f1-micro): ~$50/month
  - Memorystore Redis (1GB): ~$25/month
  - Cloud Logging/Monitoring: ~$30/month
  - Cloud Storage (backups): ~$10/month
- **Estimated Cost**: ~$215/month

### Production Environment
- **Goal**: High availability and reliability
- **Infrastructure**:
  - GKE Autopilot cluster (3-10 nodes with autoscaling): ~$500/month
  - Cloud SQL HA (db-n1-standard-2): ~$300/month
  - Memorystore Redis HA (5GB): ~$150/month
  - Cloud Pub/Sub: ~$100/month (volume-dependent)
  - Cloud Logging/Monitoring: ~$200/month
  - Cloud Storage (backups): ~$50/month
  - Cloud Trace: ~$50/month
- **Estimated Cost**: ~$1,350/month

**Cost Reduction Tactics**:
- Use **Spot VMs** for non-critical batch workloads (70% discount)
- Enable **Committed Use Discounts** for predictable workloads (37% discount)
- Implement **autoscaling** to scale down during low-traffic periods
- Use **Regional** resources instead of Multi-regional where possible

---

## Network Architecture

### Development
- **Type**: Host network (Minikube/Kind)
- **Service Discovery**: CoreDNS within cluster
- **Ingress**: NodePort services

### Staging & Production
- **Type**: VPC-native GKE cluster with IP aliasing
- **Private Cluster**: Nodes have private IPs only, API server accessible via authorized networks
- **Service Mesh**: Istio (optional) for advanced traffic management, mTLS
- **Ingress**: NGINX Ingress Controller with Google Cloud Load Balancer
- **Egress**: Cloud NAT for outbound connections
- **Network Policies**: Enabled in production for pod-to-pod traffic control

**Key Network Configuration**:
```yaml
# Example NetworkPolicy for auth-service
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: auth-service-netpol
spec:
  podSelector:
    matchLabels:
      app: auth-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
      - podSelector:
          matchLabels:
            app: api-gateway
      ports:
      - protocol: TCP
        port: 50051
  egress:
    - to:
      - podSelector:
          matchLabels:
            app: postgres
      ports:
      - protocol: TCP
        port: 5432
```

---

## Deployment Strategy

### Helm Chart Structure
- **Base Values**: `values.yaml` contains all parameters with sensible defaults
- **Environment Overrides**: `values-{env}.yaml` override only environment-specific values
- **Templates**: Reusable templates with conditionals for environment-specific resources
- **Dependencies**: Conditional dependency loading (`postgresql.enabled`, `redis.enabled`)

### Deployment Process
1. **Development**: `helm install -f values-dev.yaml`
2. **Staging**: `helm upgrade --install -f values-staging.yaml`
3. **Production**: `helm upgrade --install -f values-prod.yaml --atomic --wait`

### GitOps with ArgoCD (Future Phase)
- **Repository**: Single Git repository as source of truth
- **Sync Strategy**: Automated sync for dev/staging, manual approval for prod
- **Rollback**: Automatic rollback on health check failures

---

## Security Considerations

### Development
- Minimal security (local only)
- Plain HTTP acceptable
- Hardcoded test credentials in values-dev.yaml

### Staging & Production
- **mTLS**: Service-to-service encryption via Istio or manual TLS
- **TLS Termination**: At ingress with Let's Encrypt certificates
- **Workload Identity**: No service account keys, IAM-based authentication
- **Pod Security Standards**: Restricted profile enforced
- **Network Policies**: Deny-all-by-default with explicit allow rules
- **Image Scanning**: Vulnerability scanning in Artifact Registry
- **Binary Authorization**: Only signed images deployed to production

---

## Backup & Disaster Recovery

### Database Backups
- **Cloud SQL**: Automated daily backups with 7-day retention (prod), 3-day (staging)
- **Point-in-time Recovery**: Enabled for production (transaction log retention)
- **Export**: Weekly full exports to Cloud Storage for long-term retention

### Application State
- **Stateless Design**: All application state in databases/Redis
- **Configuration**: Helm charts in Git (GitOps)
- **Secrets**: Backed up in Secret Manager with automatic replication

### Recovery Time Objectives (RTO/RPO)
- **Development**: RTO: N/A, RPO: N/A (ephemeral)
- **Staging**: RTO: 4 hours, RPO: 1 hour
- **Production**: RTO: 1 hour, RPO: 15 minutes

---

## Migration Checklist

When promoting from dev → staging → prod:

### Database Migration
- [ ] Export schema and data from local PostgreSQL
- [ ] Import into Cloud SQL instance
- [ ] Update `DATABASE_HOST` in values file to Cloud SQL proxy or private IP
- [ ] Verify SSL connection (`DATABASE_SSL_MODE: require`)
- [ ] Test connection from application pods

### Redis Migration
- [ ] No data migration needed (cache is ephemeral)
- [ ] Update `REDIS_HOST` to Memorystore endpoint
- [ ] Verify VPC connectivity
- [ ] Test Redis commands from application pods

### Secret Migration
- [ ] Create secrets in GCP Secret Manager
- [ ] Deploy External Secrets Operator to cluster
- [ ] Create SecretStore resource pointing to Secret Manager
- [ ] Create ExternalSecret resources for each service
- [ ] Verify secrets are synced to Kubernetes

### Observability Migration
- [ ] Update `OTEL_EXPORTER_OTLP_ENDPOINT` to Cloud Trace endpoint
- [ ] Configure log aggregation to Cloud Logging
- [ ] Set up dashboards in Cloud Monitoring
- [ ] Configure alerting policies
- [ ] Test trace and metric collection

---

## Maintenance & Operations

### Routine Tasks
- **Weekly**: Review Cloud Monitoring dashboards and alerts
- **Monthly**: Patch cluster nodes and upgrade GKE version
- **Quarterly**: Review and optimize costs, update Helm charts

### Incident Response
1. Check Cloud Monitoring for alerts and SLO violations
2. Review logs in Cloud Logging
3. Analyze traces in Cloud Trace for slow requests
4. Scale services if needed: `kubectl scale deployment <service> --replicas=N`
5. Rollback if necessary: `helm rollback <release> <revision>`

### Capacity Planning
- Monitor HPA metrics and adjust thresholds
- Review Cloud SQL performance insights for query optimization
- Scale Memorystore Redis instance if hit rate drops below 80%
- Add cluster nodes if resource requests cannot be satisfied

---

## References

- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [Cloud SQL Best Practices](https://cloud.google.com/sql/docs/postgres/best-practices)
- [Memorystore Best Practices](https://cloud.google.com/memorystore/docs/redis/redis-best-practices)
- [External Secrets Operator](https://external-secrets.io/latest/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)

---

**Document Version**: 1.0  
**Last Updated**: 2024 (Phase 3 Implementation)  
**Maintainer**: Cotai DevOps Team
