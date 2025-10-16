# qOffice Preprod Validation Checklist

**Date**: ____________________  
**Validator**: ____________________  
**Environment**: preprod.qoffice.cloud  
**Cluster**: ubuntu@62.210.94.91

## 1. Secret Management Foundation

### 1.1 Vault (ops-vault)
- [ ] ArgoCD application Healthy and Synced
- [ ] Pods Running/Ready (`kubectl get pods -n vault`)
- [ ] TLS certificate `vault-tls` issued and valid
- [ ] Vault status Sealed/Unsealed checked (`vault status`)
- [ ] Audit log enabled (optional but recommended)

### 1.2 External Secrets Operator (ops-external-secrets)
- [ ] ArgoCD application Healthy and Synced
- [ ] Pods Running/Ready (`kubectl get pods -n external-secrets`)
- [ ] Service account token reviewer configured (no errors in logs)
- [ ] `ClusterSecretStore` `vault` Ready
- [ ] `ExternalSecret` resources Synced (see Section 2)

## 2. Infrastructure Layer (5 Applications)

### 1.1 Postgres (infra-postgres)
- [ ] Pod Running and Ready (1/1)
- [ ] StatefulSet healthy (`kubectl get statefulset -n infra postgres`)
- [ ] PVC bound (`kubectl get pvc -n infra`)
- [ ] Databases exist (`kubectl exec -n infra postgres-0 -- psql -U postgres -c "\l"`)
  - [ ] postgres
  - [ ] qoffice
  - [ ] keycloak
  - [ ] platform
- [ ] Roles exist (`kubectl exec -n infra postgres-0 -- psql -U postgres -c "\du"`)
  - [ ] postgres (superuser)
  - [ ] qoffice
  - [ ] keycloak
  - [ ] platform
- [ ] Gateway connectivity (`kubectl exec -n platform deployment/gateway -- sh -c 'apk add postgresql-client && psql $DB_URL -c "SELECT 1"'`)

### 1.2 Redis (infra-redis)
- [ ] Pod Running and Ready (1/1)
- [ ] StatefulSet healthy
- [ ] PVC bound
- [ ] Redis PING (`kubectl exec -n infra redis-0 -- redis-cli -a <password> PING`)
- [ ] Gateway connectivity (`kubectl exec -n platform deployment/gateway -- sh -c 'apk add redis && redis-cli -u $REDIS_URL PING'`)

### 1.3 Keycloak (infra-keycloak)
- [ ] Pod Running and Ready
- [ ] Deployment healthy
- [ ] Ingress configured (`kubectl get ingress -n auth keycloak`)
- [ ] Admin console accessible at https://keycloak.preprod.qoffice.cloud
- [ ] Realm `qoffice-preprod` exists
- [ ] Clients created:
  - [ ] qoffice-gateway (confidential)
  - [ ] qoffice-provisioner (confidential)
  - [ ] qoffice-shell (public)
- [ ] Test users present with `tenant_id` attribute

### 1.4 MinIO (infra-minio)
- [ ] Pod Running and Ready
- [ ] StatefulSet healthy
- [ ] PVC bound
- [ ] Console accessible at https://minio.preprod.qoffice.cloud
- [ ] Bucket `t-tenant-preprod` exists
- [ ] Health check (`kubectl exec -n data minio-0 -- wget -O- http://localhost:9000/minio/health/live`)
- [ ] Gateway connectivity (`kubectl exec -n platform deployment/gateway -- wget -O- http://minio.data.svc.cluster.local:9000/minio/health/live`)

### 1.5 Meilisearch (infra-meilisearch)
- [ ] Pod Running and Ready
- [ ] StatefulSet healthy
- [ ] PVC bound
- [ ] API accessible at https://search.preprod.qoffice.cloud
- [ ] Health endpoint OK (`curl https://search.preprod.qoffice.cloud/health`)
- [ ] Indices exist:
  - [ ] files
  - [ ] mail_messages
  - [ ] people
  - [ ] chat_messages
  - [ ] events
- [ ] Gateway connectivity (`kubectl exec -n platform deployment/gateway -- wget -O- http://meilisearch.search.svc.cluster.local:7700/health`)

## 2. Platform Secrets (1 Application)

### 2.1 Platform Secrets (platform-secrets)
- [ ] ArgoCD application Healthy and Synced
- [ ] Secrets exist (`kubectl get secrets -n platform`)
  - [ ] gateway-secrets
  - [ ] redis-conn
  - [ ] db-secret
- [ ] Secret data matches infrastructure credentials

## 3. Platform Services (11 Applications)

### 3.1 Gateway
- [ ] Pod Running and Ready
- [ ] Deployment healthy
- [ ] Ingress configured (`kubectl get ingress -n platform gateway-ingress`)
- [ ] Health endpoint (`curl https://api.preprod.qoffice.cloud/health`)
- [ ] Logs show successful DB, Redis, MinIO, Meilisearch connections
- [ ] Migrations executed (check logs)

### 3.2 Provisioner
- [ ] Pod Running (Ready if applicable)
- [ ] Deployment healthy
- [ ] Logs show successful startup

### 3.3 Remaining Services (admin-api, billing, indexer, notifications, qai, qcalendar-qcontacts, qmail, qmeet, wopi-bridge)
For each:
- [ ] Pod Running (Ready when applicable)
- [ ] Deployment exists
- [ ] No `ImagePullBackOff`
- [ ] Logs free of critical errors

## 4. Web Applications (14 Applications)

### 4.1 Shell
- [ ] Pod Running and Ready
- [ ] Deployment healthy
- [ ] Ingress configured
- [ ] Accessible at https://preprod.qoffice.cloud
- [ ] Login page loads
- [ ] Keycloak authentication flow completes
- [ ] Dashboard renders without errors

### 4.2 QDrive
- [ ] Pod Running and Ready
- [ ] Deployment healthy
- [ ] Ingress configured
- [ ] Accessible at https://drive.preprod.qoffice.cloud
- [ ] Login works
- [ ] File operations succeed (upload, folder create, search)

### 4.3 Remaining Web Apps (qmail, qai, qchat, qaccount, qmeet, qdocs, qsheets, qslides, billing, revenue-console, qadmin, admin)
For each:
- [ ] Pod Running
- [ ] Deployment exists
- [ ] Ingress configured (if applicable)
- [ ] Basic UI loads or returns expected "not yet implemented" status

## 5. ArgoCD Health

- [ ] All 30 applications visible in ArgoCD UI
- [ ] Infrastructure apps Healthy + Synced
- [ ] Platform-secrets Healthy + Synced
- [ ] Core services (gateway) Healthy + Synced
- [ ] Shell Healthy + Synced
- [ ] No unintended `OutOfSync` or `Degraded` states
- [ ] `ignoreDifferences` configured for secrets verified

## 6. End-to-End Smoke Tests

### 6.1 Authentication
- [ ] Navigate to Shell login
- [ ] Redirect to Keycloak
- [ ] Login with test user
- [ ] JWT token includes `tenant_id`, `user_id`, `email`

### 6.2 File Upload Flow
- [ ] Login to Shell
- [ ] Open QDrive
- [ ] Upload file
- [ ] Verify file appears in MinIO
- [ ] Search file (Meilisearch)
- [ ] Download and delete file

### 6.3 Optional User Signup (if QAccount live)
- [ ] Register new user at https://account.preprod.qoffice.cloud
- [ ] Verify email flow (if configured)
- [ ] Login with new user
- [ ] Access QDrive

## 7. Performance & Stability

- [ ] `kubectl top pods --all-namespaces` shows CPU/Memory < 80%
- [ ] PVC usage < 80% (`kubectl get pvc --all-namespaces`)
- [ ] No pod restarts in last hour (`kubectl get pods --all-namespaces`)
- [ ] Nodes healthy (`kubectl top nodes`)

## 8. Security

- [ ] Secrets stored as base64 `data` fields (no `stringData`)
- [ ] Ingress resources use TLS
- [ ] No unintended `LoadBalancer` services
- [ ] Namespaces enforce isolation
- [ ] Pods not running as root (unless required)

## 9. Monitoring & Logging

- [ ] Application logs accessible (`kubectl logs -n <namespace> <pod>`)
- [ ] No critical errors in logs
- [ ] Events clean (`kubectl get events --all-namespaces --field-selector type=Warning`)
- [ ] Audit `argocd app history <app>` shows successful syncs

## 10. Documentation

- [ ] `docs/BOOTSTRAP_PROCEDURES.md` reflects executed steps
- [ ] `docs/ROLLBACK_PLAN.md` reviewed and ready
- [ ] `docs/infra-migration-notes.md` updated with current status
- [ ] `docs/deployment/PREPROD_DEPLOYMENT_GUIDE.md` matches environment state

## Summary

| Metric           | Count |
| ---------------- | ----- |
| Checks total     | _____ |
| Checks passed    | _____ |
| Checks failed    | _____ |
| Checks skipped   | _____ |
| Pass rate (%)    | _____ |

### Critical Issues
1. ____________________________________
2. ____________________________________
3. ____________________________________

### Recommendations
1. ____________________________________
2. ____________________________________
3. ____________________________________

### Sign-off
- [ ] Infrastructure validated
- [ ] Core services operational
- [ ] End-to-end smoke tests passed
- [ ] Platform ready for broader testing
- [ ] Platform ready for production cutover

**Validator Signature**: ____________________  
**Date**: ____________________