# External Secrets Operator Configuration

## 🎯 Overview

External Secrets Operator (ESO) synchronizes secrets from external secret management systems (GCP Secret Manager, AWS Secrets Manager, HashiCorp Vault) into Kubernetes Secrets. This guide covers ESO setup for Cotai MVP.

---

## 📋 Architecture

```
GCP Secret Manager                    Kubernetes Cluster
├── cotai-jwt-secret         ────────> Secret: auth-jwt-secret
├── cotai-db-password        ────────> Secret: auth-db-credentials
├── cotai-redis-password     ────────> Secret: auth-redis-credentials
└── cotai-api-keys           ────────> Secret: api-keys

External Secrets Operator (ESO)
├── SecretStore (per namespace) - Connection to GCP Secret Manager
└── ExternalSecret (per service) - Defines sync rules
```

---

## 🚀 Step 1: Install External Secrets Operator

### Using Helm

```bash
# Add Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install in dedicated namespace
helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true

# Verify installation
kubectl get pods -n external-secrets-system
kubectl get crds | grep external-secrets
```

### Expected CRDs

```bash
$ kubectl get crds | grep external-secrets
externalsecrets.external-secrets.io
secretstores.external-secrets.io
clustersecretstores.external-secrets.io
```

---

## 🔐 Step 2: Configure Secret Stores

### Development Environment (Kubernetes Secrets Backend)

For local development, use Kubernetes secrets as the backend (no external system needed).

**File**: `kubernetes/external-secrets/secretstore-dev.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: dev-secret-store
  namespace: dev
spec:
  provider:
    kubernetes:
      # Use local Kubernetes secrets
      remoteNamespace: deps
      server:
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: external-secrets-sa
```

Create service account:

```bash
kubectl create serviceaccount external-secrets-sa -n dev

kubectl create clusterrolebinding external-secrets-reader \
  --clusterrole=cluster-admin \
  --serviceaccount=dev:external-secrets-sa
```

### Staging/Production (GCP Secret Manager)

**File**: `kubernetes/external-secrets/secretstore-prod.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: gcp-secret-store
  namespace: production
spec:
  provider:
    gcpsm:
      projectID: "cotai-production"
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: cotai-gke-prod
          serviceAccountRef:
            name: external-secrets-sa
```

Setup Workload Identity:

```bash
# Create GCP service account
gcloud iam service-accounts create external-secrets-sa \
  --project=cotai-production

# Grant Secret Manager access
gcloud projects add-iam-policy-binding cotai-production \
  --member="serviceAccount:external-secrets-sa@cotai-production.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Create Kubernetes service account
kubectl create serviceaccount external-secrets-sa -n production

# Annotate with GCP SA
kubectl annotate serviceaccount external-secrets-sa \
  -n production \
  iam.gke.io/gcp-service-account=external-secrets-sa@cotai-production.iam.gserviceaccount.com

# Bind Workload Identity
gcloud iam service-accounts add-iam-policy-binding \
  external-secrets-sa@cotai-production.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:cotai-production.svc.id.goog[production/external-secrets-sa]" \
  --project=cotai-production
```

### ClusterSecretStore (Global, Optional)

For organization-wide secret store:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-cluster-secret-store
spec:
  provider:
    gcpsm:
      projectID: "cotai-production"
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: cotai-gke-prod
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets-system
```

---

## 📝 Step 3: Create ExternalSecrets

### Auth Service Database Credentials

**File**: `kubernetes/external-secrets/externalsecret-auth-db.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: auth-db-credentials
  namespace: production
spec:
  refreshInterval: 1h  # Sync every hour
  secretStoreRef:
    name: gcp-secret-store
    kind: SecretStore
  target:
    name: auth-db-credentials
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        password: "{{ .password }}"
        username: "cotai_auth"
        host: "10.20.30.10"
        port: "5432"
        database: "cotai_auth"
        # Connection string template
        connection-string: "postgresql://cotai_auth:{{ .password }}@10.20.30.10:5432/cotai_auth?sslmode=require"
  dataFrom:
    - extract:
        key: cotai-auth-db-password
```

### JWT Secret

**File**: `kubernetes/external-secrets/externalsecret-auth-jwt.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: auth-jwt-secret
  namespace: production
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: gcp-secret-store
    kind: SecretStore
  target:
    name: auth-jwt-secret
    creationPolicy: Owner
  data:
    - secretKey: jwt-secret
      remoteRef:
        key: cotai-jwt-secret
```

### Redis Credentials

**File**: `kubernetes/external-secrets/externalsecret-auth-redis.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: auth-redis-credentials
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-store
    kind: SecretStore
  target:
    name: auth-redis-credentials
    creationPolicy: Owner
    template:
      data:
        password: "{{ .password }}"
        host: "10.20.30.20"
        port: "6379"
  dataFrom:
    - extract:
        key: cotai-redis-password
```

### API Keys (Multiple Keys)

**File**: `kubernetes/external-secrets/externalsecret-api-keys.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: api-keys
  namespace: production
spec:
  refreshInterval: 12h
  secretStoreRef:
    name: gcp-secret-store
    kind: SecretStore
  target:
    name: api-keys
    creationPolicy: Owner
  data:
    - secretKey: twilio-api-key
      remoteRef:
        key: cotai-twilio-api-key
    - secretKey: sendgrid-api-key
      remoteRef:
        key: cotai-sendgrid-api-key
    - secretKey: stripe-api-key
      remoteRef:
        key: cotai-stripe-api-key
```

---

## 🚀 Step 4: Deploy External Secrets

```bash
# Apply SecretStore
kubectl apply -f kubernetes/external-secrets/secretstore-prod.yaml

# Verify SecretStore is ready
kubectl get secretstore -n production
# Should show STATUS: Valid

# Apply ExternalSecrets
kubectl apply -f kubernetes/external-secrets/externalsecret-auth-db.yaml
kubectl apply -f kubernetes/external-secrets/externalsecret-auth-jwt.yaml
kubectl apply -f kubernetes/external-secrets/externalsecret-auth-redis.yaml
kubectl apply -f kubernetes/external-secrets/externalsecret-api-keys.yaml

# Verify ExternalSecrets sync
kubectl get externalsecret -n production
# Should show STATUS: SecretSynced

# Check created Kubernetes secrets
kubectl get secrets -n production
# Should list: auth-db-credentials, auth-jwt-secret, auth-redis-credentials, api-keys
```

---

## 🔍 Step 5: Verification

### Check ExternalSecret Status

```bash
# Detailed status
kubectl describe externalsecret auth-db-credentials -n production

# Expected conditions:
# - Ready: True
# - SecretSynced: True

# Check events
kubectl get events -n production --field-selector involvedObject.name=auth-db-credentials
```

### Verify Secret Content

```bash
# View secret (base64 encoded)
kubectl get secret auth-db-credentials -n production -o yaml

# Decode secret
kubectl get secret auth-db-credentials -n production -o jsonpath='{.data.password}' | base64 -d

# Test connection string
kubectl get secret auth-db-credentials -n production -o jsonpath='{.data.connection-string}' | base64 -d
```

### Test from Pod

```bash
# Create test pod
kubectl run test-pod --image=postgres:15 -n production --rm -it -- bash

# Inside pod, test database connection
export PGPASSWORD=$(cat /run/secrets/auth-db-credentials/password)
psql -h $(cat /run/secrets/auth-db-credentials/host) \
     -U $(cat /run/secrets/auth-db-credentials/username) \
     -d $(cat /run/secrets/auth-db-credentials/database)
```

---

## 🔄 Step 6: Secret Rotation

### Automatic Rotation

ESO automatically syncs secrets based on `refreshInterval`. To force immediate sync:

```bash
# Delete and recreate secret (ESO will re-sync)
kubectl delete secret auth-db-credentials -n production

# Or restart ESO pod
kubectl rollout restart deployment external-secrets -n external-secrets-system
```

### Manual Secret Update in GCP

```bash
# Update secret in GCP Secret Manager
echo -n "new-password-here" | gcloud secrets versions add cotai-auth-db-password \
  --data-file=- \
  --project=cotai-production

# ESO will automatically pick up the new version within refreshInterval
# Or force sync by deleting the Kubernetes secret
```

### Secret Rotation Policy

```yaml
# Add to ExternalSecret for automatic rotation
spec:
  refreshInterval: 1h
  target:
    deletionPolicy: Retain  # Keep secret when ExternalSecret is deleted
    template:
      metadata:
        annotations:
          reloader.stakater.com/match: "true"  # Auto-restart pods on secret change
```

---

## 🛡️ Step 7: Security Best Practices

### 1. Least Privilege IAM

```bash
# Grant minimal permissions (read-only)
gcloud projects add-iam-policy-binding cotai-production \
  --member="serviceAccount:auth-service-sa@cotai-production.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --condition='expression=resource.name.startsWith("projects/cotai-production/secrets/cotai-auth"),title=auth-service-secrets'
```

### 2. Audit Logging

```bash
# Enable Secret Manager audit logs
gcloud logging read "protoPayload.serviceName=secretmanager.googleapis.com" \
  --project=cotai-production \
  --limit=50
```

### 3. Secret Encryption (CMEK)

```bash
# Create KMS key ring
gcloud kms keyrings create cotai-keyring \
  --location=us-central1 \
  --project=cotai-production

# Create crypto key
gcloud kms keys create cotai-secret-key \
  --location=us-central1 \
  --keyring=cotai-keyring \
  --purpose=encryption \
  --project=cotai-production

# Create secret with CMEK
gcloud secrets create cotai-jwt-secret-cmek \
  --replication-policy=automatic \
  --kms-key-name=projects/cotai-production/locations/us-central1/keyRings/cotai-keyring/cryptoKeys/cotai-secret-key \
  --project=cotai-production
```

---

## 📊 Step 8: Monitoring

### Prometheus Metrics

ESO exposes Prometheus metrics on port 8080:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-secrets-metrics
  namespace: external-secrets-system
spec:
  ports:
    - name: metrics
      port: 8080
      targetPort: 8080
  selector:
    app.kubernetes.io/name: external-secrets
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: external-secrets
  namespace: external-secrets-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: external-secrets
  endpoints:
    - port: metrics
      interval: 30s
```

### Key Metrics

- `externalsecret_sync_calls_total` - Total sync attempts
- `externalsecret_sync_calls_error` - Failed syncs
- `externalsecret_status_condition` - ExternalSecret status

### Alerting

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: external-secrets-alerts
  namespace: external-secrets-system
spec:
  groups:
    - name: external-secrets
      interval: 30s
      rules:
        - alert: ExternalSecretSyncFailed
          expr: externalsecret_sync_calls_error > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "ExternalSecret sync failed"
            description: "ExternalSecret {{ $labels.name }} in namespace {{ $labels.namespace }} failed to sync"
```

---

## 🐛 Troubleshooting

### ExternalSecret Not Syncing

```bash
# Check ESO logs
kubectl logs -f deployment/external-secrets -n external-secrets-system

# Check ExternalSecret status
kubectl describe externalsecret <name> -n <namespace>

# Common issues:
# - SecretStore not ready: Check Workload Identity binding
# - Permission denied: Verify IAM roles
# - Secret not found: Ensure secret exists in GCP Secret Manager
```

### Workload Identity Issues

```bash
# Verify service account annotation
kubectl get sa external-secrets-sa -n production -o yaml | grep iam.gke.io

# Test Workload Identity
kubectl run -it --rm debug \
  --image=google/cloud-sdk:slim \
  --serviceaccount=external-secrets-sa \
  --namespace=production \
  -- gcloud secrets list --project=cotai-production
```

### Secret Not Updating in Pods

```bash
# Restart deployment to pick up new secret
kubectl rollout restart deployment auth-service -n production

# Or use Reloader for automatic restarts
helm repo add stakater https://stakater.github.io/stakater-charts
helm install reloader stakater/reloader -n external-secrets-system
```

---

## 📚 Additional Resources

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [GCP Secret Manager Best Practices](https://cloud.google.com/secret-manager/docs/best-practices)
- [Workload Identity Setup](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)

---

**Last Updated**: December 2024  
**Maintainer**: Cotai DevOps Team
