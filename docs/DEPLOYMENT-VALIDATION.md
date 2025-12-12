# Deployment Validation Checklist

## 🎯 Overview

This checklist ensures that all Cotai MVP services are properly deployed, configured, and operational before considering a deployment successful. Use this for staging and production deployments.

---

## ✅ Pre-Deployment Checklist

### Infrastructure

- [ ] **Cluster Health**: GKE cluster is running with sufficient resources
  ```bash
  kubectl cluster-info
  kubectl get nodes
  kubectl top nodes
  ```

- [ ] **Dependencies Running**: PostgreSQL, Redis, RabbitMQ/Pub/Sub operational
  ```bash
  kubectl get pods -n deps  # Local
  gcloud sql instances describe cotai-postgres-prod  # GCP
  gcloud redis instances describe cotai-redis-prod --region=us-central1
  ```

- [ ] **Secrets Available**: All secrets created in Secret Manager or Kubernetes
  ```bash
  kubectl get secrets -n production
  gcloud secrets list --project=cotai-production
  ```

- [ ] **External Secrets Synced**: ESO successfully syncing secrets
  ```bash
  kubectl get externalsecret -n production
  kubectl describe externalsecret auth-db-credentials -n production
  ```

### Images

- [ ] **Images Built**: All service images built and tagged
  ```bash
  docker images | grep cotai
  ```

- [ ] **Images Pushed**: Images pushed to GCR/Artifact Registry
  ```bash
  gcloud container images list --repository=gcr.io/PROJECT_ID
  ```

- [ ] **Image Vulnerability Scan**: No critical vulnerabilities
  ```bash
  gcloud container images scan gcr.io/PROJECT_ID/cotai-auth-service:v1.0.0
  ```

### Helm Charts

- [ ] **Charts Linted**: All Helm charts pass lint validation
  ```bash
  for service in auth edital procurement bidding notification audit api-gateway; do
    helm lint ${service}-service/charts/${service}-service
  done
  ```

- [ ] **Templates Render**: Helm templates render without errors
  ```bash
  helm template auth-service ./auth-service/charts/auth-service -f values-prod.yaml
  ```

- [ ] **Dependencies Updated**: Helm chart dependencies up-to-date
  ```bash
  helm dependency update ./auth-service/charts/auth-service
  ```

---

## 🚀 Deployment Execution

### Deploy Services

- [ ] **Namespace Created**: Target namespace exists
  ```bash
  kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
  ```

- [ ] **Helm Install/Upgrade**: Services deployed successfully
  ```bash
  helm upgrade --install auth-service ./auth-service/charts/auth-service \
    -f values-prod.yaml \
    --set image.tag="v1.0.0" \
    --namespace production \
    --atomic --wait --timeout 10m
  ```

- [ ] **Deployment Status**: All deployments rolled out successfully
  ```bash
  kubectl rollout status deployment/auth-service -n production
  ```

---

## 🔍 Post-Deployment Validation

### Pod Health

- [ ] **Pods Running**: All pods in Running state
  ```bash
  kubectl get pods -n production
  # Expected: All pods show 1/1 or X/X READY, STATUS=Running
  ```

- [ ] **No Restarts**: Pods not crash-looping
  ```bash
  kubectl get pods -n production -o wide
  # Check RESTARTS column = 0 or low number
  ```

- [ ] **Resource Usage**: Pods within resource limits
  ```bash
  kubectl top pods -n production
  ```

- [ ] **Pod Logs Clean**: No critical errors in logs
  ```bash
  kubectl logs deployment/auth-service -n production --tail=50
  # Check for ERROR, FATAL, panic messages
  ```

### Probes

- [ ] **Liveness Probes Passing**: Pods passing liveness checks
  ```bash
  kubectl describe pod <pod-name> -n production | grep Liveness
  # Should show: Liveness: <probe-config> (Success)
  ```

- [ ] **Readiness Probes Passing**: Pods ready to receive traffic
  ```bash
  kubectl describe pod <pod-name> -n production | grep Readiness
  # Should show: Readiness: <probe-config> (Success)
  ```

### Service Connectivity

- [ ] **Services Created**: Kubernetes Services exist and have endpoints
  ```bash
  kubectl get svc -n production
  kubectl get endpoints -n production
  # Endpoints should have pod IPs listed
  ```

- [ ] **Internal DNS**: Services resolvable via DNS
  ```bash
  kubectl run test-dns --image=busybox:1.28 --rm -it --restart=Never -- nslookup auth-service.production.svc.cluster.local
  ```

- [ ] **Port-Forward Test**: Can access service via port-forward
  ```bash
  kubectl port-forward svc/auth-service 50051:50051 -n production &
  grpcurl -plaintext localhost:50051 list
  killall kubectl
  ```

### Database Connectivity

- [ ] **Database Reachable**: Services can connect to PostgreSQL
  ```bash
  kubectl exec -it deployment/auth-service -n production -- sh
  # Inside pod:
  nc -zv postgresql.deps.svc.cluster.local 5432
  # or for Cloud SQL:
  nc -zv 10.20.30.10 5432
  ```

- [ ] **Database Tables Exist**: Schema migrations applied
  ```bash
  kubectl exec -it deployment/auth-service -n production -- sh
  # Run migration check or query:
  psql $DATABASE_URL -c "\dt"
  ```

- [ ] **Database Credentials Work**: Can authenticate successfully
  ```bash
  # Check secret is mounted
  kubectl exec deployment/auth-service -n production -- cat /run/secrets/db-credentials/password
  ```

### Cache Connectivity

- [ ] **Redis Reachable**: Services can connect to Redis
  ```bash
  kubectl exec -it deployment/auth-service -n production -- sh
  redis-cli -h redis-master.deps.svc.cluster.local -a $REDIS_PASSWORD ping
  # or for Memorystore:
  redis-cli -h 10.20.30.20 -a $REDIS_PASSWORD ping
  ```

- [ ] **Redis Commands Work**: Can set/get keys
  ```bash
  kubectl exec deployment/auth-service -n production -- \
    redis-cli -h $REDIS_HOST -a $REDIS_PASSWORD SET test-key "test-value"
  kubectl exec deployment/auth-service -n production -- \
    redis-cli -h $REDIS_HOST -a $REDIS_PASSWORD GET test-key
  ```

### Inter-Service Communication

- [ ] **gRPC Calls Succeed**: Services can call each other via gRPC
  ```bash
  # From api-gateway, call auth-service
  kubectl exec -it deployment/api-gateway -n production -- \
    grpcurl -plaintext auth-service:50051 grpc.health.v1.Health/Check
  ```

- [ ] **Service Discovery Works**: Services resolve each other's DNS
  ```bash
  kubectl exec deployment/api-gateway -n production -- \
    nslookup auth-service.production.svc.cluster.local
  ```

---

## 📊 Observability Validation

### Metrics

- [ ] **Prometheus Scraping**: Metrics endpoints being scraped
  ```bash
  # Port-forward Prometheus
  kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n deps &
  # Open http://localhost:9090
  # Query: up{namespace="production"}
  # Should show all services as up=1
  ```

- [ ] **Service Metrics Available**: Business metrics are being recorded
  ```bash
  # In Prometheus, query:
  # http_requests_total{namespace="production"}
  # grpc_server_handled_total{namespace="production"}
  ```

- [ ] **HPA Metrics**: Horizontal Pod Autoscaler has metrics
  ```bash
  kubectl get hpa -n production
  # Should show current CPU/memory usage
  ```

### Logging

- [ ] **Logs Flowing**: Logs are being collected
  ```bash
  kubectl logs deployment/auth-service -n production --tail=10
  # For GCP:
  gcloud logging read "resource.type=k8s_container" --limit=10
  ```

- [ ] **Log Format Correct**: Logs in JSON format (prod) with correlation IDs
  ```bash
  kubectl logs deployment/auth-service -n production --tail=1 | jq .
  # Should parse as valid JSON with fields: timestamp, level, message, trace_id
  ```

- [ ] **No Error Floods**: Error rate within acceptable limits
  ```bash
  kubectl logs deployment/auth-service -n production --tail=100 | grep -c ERROR
  # Should be < 5%
  ```

### Tracing

- [ ] **Traces Visible**: Distributed traces appearing in Jaeger/Cloud Trace
  ```bash
  # Port-forward Jaeger
  kubectl port-forward svc/jaeger-query 16686:16686 -n deps &
  # Open http://localhost:16686
  # Select service "auth-service" and search for traces
  ```

- [ ] **Trace Context Propagated**: Spans show parent-child relationships
  ```bash
  # In Jaeger, check that traces have multiple spans across services
  ```

- [ ] **Sampling Working**: Traces are being sampled appropriately
  ```bash
  # Check sampling rate in service config
  kubectl get configmap auth-service -n production -o yaml | grep OTEL_SAMPLING_RATE
  ```

---

## 🔐 Security Validation

### Network Policies

- [ ] **Network Policies Applied**: Policies exist and are enforced
  ```bash
  kubectl get networkpolicy -n production
  kubectl describe networkpolicy auth-service -n production
  ```

- [ ] **Egress Restricted**: Pods can only access allowed destinations
  ```bash
  # Test blocked egress (should fail)
  kubectl exec deployment/auth-service -n production -- curl -m 5 https://google.com
  # Test allowed egress (should succeed)
  kubectl exec deployment/auth-service -n production -- nc -zv postgresql 5432
  ```

### Pod Security

- [ ] **Pod Security Standards**: Pods meet restricted profile
  ```bash
  kubectl get pod <pod-name> -n production -o yaml | grep -A 10 securityContext
  # Should show: runAsNonRoot: true, readOnlyRootFilesystem: true, capabilities dropped
  ```

- [ ] **No Privileged Containers**: No containers running as privileged
  ```bash
  kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].securityContext.privileged}{"\n"}{end}'
  # Should show false or blank for all
  ```

### Secrets

- [ ] **Secrets Not in Env**: Secrets mounted as volumes, not env vars (best practice)
  ```bash
  kubectl get pod <pod-name> -n production -o yaml | grep -A 5 volumeMounts
  ```

- [ ] **Secret Rotation Working**: Secrets can be rotated without downtime
  ```bash
  # Update secret in Secret Manager, wait for refreshInterval, verify pod still works
  ```

---

## 🚦 Integration Testing

### Health Endpoints

- [ ] **Health Check Returns OK**: Service health endpoints respond
  ```bash
  kubectl exec deployment/auth-service -n production -- \
    curl -s http://localhost:8090/health
  # Should return {"status":"UP"} or equivalent
  ```

- [ ] **Readiness Check Returns OK**: Service ready endpoints respond
  ```bash
  kubectl exec deployment/auth-service -n production -- \
    grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check
  ```

### API Testing

- [ ] **gRPC API Responds**: Can call gRPC methods successfully
  ```bash
  kubectl port-forward svc/auth-service 50051:50051 -n production &
  grpcurl -d '{"username":"test","password":"test123"}' \
    -plaintext localhost:50051 auth.v1.AuthService/Login
  killall kubectl
  ```

- [ ] **REST API Responds** (if applicable): API Gateway returns valid responses
  ```bash
  kubectl port-forward svc/api-gateway 8080:8080 -n production &
  curl http://localhost:8080/api/v1/health
  killall kubectl
  ```

### End-to-End Workflows

- [ ] **User Registration Flow**: Can create new user
- [ ] **Authentication Flow**: Can login and receive JWT
- [ ] **Authorization Flow**: JWT validation works
- [ ] **Database Persistence**: Data persists correctly
- [ ] **Cache Operations**: Cache hit/miss working

---

## 📈 Performance Validation

### Resource Utilization

- [ ] **CPU Usage Reasonable**: Pods using <70% of requested CPU
  ```bash
  kubectl top pods -n production
  ```

- [ ] **Memory Usage Reasonable**: Pods using <80% of requested memory
  ```bash
  kubectl top pods -n production
  ```

- [ ] **No OOMKills**: No out-of-memory kills
  ```bash
  kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}' | grep OOMKilled
  # Should return nothing
  ```

### Latency

- [ ] **API Latency Acceptable**: P95 latency <500ms, P99 <1s
  ```bash
  # Check in Prometheus:
  # histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
  # histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
  ```

- [ ] **Database Query Performance**: Slow queries identified and optimized
  ```bash
  # Check Cloud SQL query insights or pg_stat_statements
  ```

---

## 🔄 High Availability Validation

### Replica Count

- [ ] **Multiple Replicas Running**: Production has ≥2 replicas per service
  ```bash
  kubectl get deployment -n production
  # READY column should show 2/2, 3/3, etc.
  ```

- [ ] **PodDisruptionBudget Configured**: PDBs prevent too many pods being down
  ```bash
  kubectl get pdb -n production
  kubectl describe pdb auth-service -n production
  ```

### Autoscaling

- [ ] **HPA Configured**: HorizontalPodAutoscaler exists
  ```bash
  kubectl get hpa -n production
  ```

- [ ] **HPA Scaling Works**: HPA scales pods based on metrics
  ```bash
  # Generate load and watch:
  kubectl get hpa -n production -w
  ```

### Failover

- [ ] **Pod Restart Tolerance**: Deleting a pod doesn't cause downtime
  ```bash
  # Start continuous requests in background
  # Delete one pod
  kubectl delete pod <pod-name> -n production
  # Verify no 5xx errors in requests
  ```

- [ ] **Node Drain Tolerance**: Draining a node doesn't cause downtime
  ```bash
  # Only test in staging!
  kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
  kubectl get pods -n production -o wide
  # Pods should reschedule to other nodes
  ```

---

## 🎯 Sign-Off Criteria

### Critical (Must Pass)

- [x] All pods in Running state with 0 restarts
- [x] All probes (liveness, readiness) passing
- [x] Database connectivity working
- [x] External Secrets syncing correctly
- [x] Health endpoints returning 200 OK
- [x] No critical errors in logs
- [x] gRPC inter-service calls succeeding

### Important (Should Pass)

- [ ] Metrics flowing to Prometheus
- [ ] Traces visible in Jaeger/Cloud Trace
- [ ] HPA configured and responding to load
- [ ] PodDisruptionBudget preventing disruptions
- [ ] Network policies enforced
- [ ] Resource usage within limits

### Nice-to-Have (Can Be Addressed Post-Deployment)

- [ ] Grafana dashboards configured
- [ ] Alerting rules set up
- [ ] Cost optimization features enabled (Spot VMs, CUD)
- [ ] Load testing completed

---

## 📝 Deployment Sign-Off

**Environment**: _________________ (dev/staging/production)  
**Date**: _________________  
**Version**: _________________  
**Deployed By**: _________________  

**Sign-Off**:

- [ ] Infrastructure Team: _________________
- [ ] Development Team: _________________
- [ ] QA Team: _________________
- [ ] Security Team: _________________ (for production)

**Notes**:
________________________________________________________________
________________________________________________________________
________________________________________________________________

---

## 🆘 Rollback Procedure

If validation fails, follow rollback procedure:

```bash
# Helm rollback to previous revision
helm rollback auth-service <revision-number> -n production

# Or redeploy previous version
helm upgrade auth-service ./auth-service/charts/auth-service \
  --set image.tag="v0.9.0" \
  -f values-prod.yaml \
  -n production \
  --atomic --wait

# Verify rollback
kubectl rollout status deployment/auth-service -n production
kubectl get pods -n production -l app.kubernetes.io/name=auth-service
```

---

**Last Updated**: December 2024  
**Maintainer**: Cotai DevOps Team
