# qOffice Preprod Rollback Plan

## 1. Overview

This plan provides detailed procedures to revert the infrastructure migration from Bitnami Helm charts to Kustomize manifests if critical issues arise during or after bootstrap.

## 2. Rollback Triggers

Initiate rollback when any of the following occur:

- Infrastructure pods fail to reach a stable state within 30 minutes
- Data corruption occurs in Postgres, Redis, or MinIO
- Services remain unable to connect to infrastructure after bootstrap
- Critical security vulnerabilities are discovered in the new images
- ArgoCD applications remain in `Degraded` or `Progressing` states due to sync failures
- Production-blocking bugs surface that cannot be mitigated quickly

## 3. Pre-Rollback Checklist

- [ ] Document the incident prompting rollback (include timestamps and symptoms)
- [ ] Capture logs from all failing pods
- [ ] Export current ArgoCD application states (`argocd app get <app> -o yaml`)
- [ ] Backup current secrets and credentials if they differ from committed values
- [ ] Notify stakeholders and on-call engineers that rollback is starting
- [ ] Estimate expected downtime (target 60 minutes)

## 4. Rollback Procedure

### Step 1: Pause ArgoCD Auto-Sync

```bash
argocd app set ops-vault --sync-policy none
argocd app set ops-external-secrets --sync-policy none
argocd app set infra-postgres --sync-policy none
argocd app set infra-redis --sync-policy none
argocd app set infra-keycloak --sync-policy none
argocd app set infra-minio --sync-policy none
argocd app set infra-meilisearch --sync-policy none
argocd app set platform-secrets --sync-policy none
argocd app list | egrep 'ops-|infra-|platform-secrets'
```

### Step 2: Scale Down Dependent Services

```bash
kubectl scale deployment --all --replicas=0 -n platform
kubectl scale deployment --all --replicas=0 -n web
kubectl get pods -n platform -n web
```

### Step 3: Backup Current State (If Accessible)

```bash
kubectl exec -n infra postgres-0 -- pg_dumpall -U postgres > /tmp/postgres-backup-$(date +%Y%m%d-%H%M%S).sql
kubectl exec -n infra redis-0 -- redis-cli -a <password> --rdb /tmp/dump.rdb
kubectl cp infra/redis-0:/tmp/dump.rdb /tmp/redis-backup-$(date +%Y%m%d-%H%M%S).rdb
kubectl exec -n data minio-0 -- tar czf /tmp/buckets.tar.gz /data
kubectl cp data/minio-0:/tmp/buckets.tar.gz /tmp/minio-backup-$(date +%Y%m%d-%H%M%S).tar.gz
```

### Step 4: Delete New Infrastructure

```bash
kubectl delete namespace infra
kubectl delete namespace auth
kubectl delete namespace data
kubectl delete namespace search
kubectl delete namespace platform
```

If a namespace is stuck in `Terminating`, clear finalizers:

```bash
kubectl get namespace infra -o json | jq '.spec.finalizers=[]' | kubectl replace --raw /api/v1/namespaces/infra/finalize -f -
```

### Step 5: Revert ArgoCD Applications to Bitnami Helm

```bash
cd qoffice-preprod-gitops
git log --oneline root/apps/infra/
git checkout <previous-commit> root/apps/infra/minio-app.yaml
git checkout <previous-commit> root/apps/infra/meili-app.yaml
git checkout <previous-commit> root/apps/infra/postgres-app.yaml
git checkout <previous-commit> root/apps/infra/redis-app.yaml
git checkout <previous-commit> root/apps/infra/keycloak-app.yaml
git add root/apps/infra/
git commit -m "Rollback: restore Bitnami-based infrastructure"
git push origin main
```

### Step 6: Recreate Namespaces

```bash
kubectl create namespace infra
kubectl create namespace auth
kubectl create namespace data
kubectl create namespace search
kubectl create namespace platform
kubectl create namespace web
```

### Step 7: Restore Bitnami Secrets

```bash
kubectl create secret generic minio-secrets \
  --from-literal=root-user=<username> \
  --from-literal=root-password=<password> \
  -n data

kubectl create secret generic meili-secrets \
  --from-literal=masterKey=<master-key> \
  -n search

kubectl create secret generic postgres-secret \
  --from-literal=postgres-password=<password> \
  -n infra

kubectl create secret generic redis-secret \
  --from-literal=redis-password=<password> \
  -n infra

kubectl create secret generic keycloak-admin \
  --from-literal=admin-password=<password> \
  -n auth
```

### Step 8: Re-enable ArgoCD Auto-Sync

```bash
argocd app set infra-postgres --sync-policy automated
argocd app set infra-redis --sync-policy automated
argocd app set infra-keycloak --sync-policy automated
argocd app set infra-minio --sync-policy automated
argocd app set infra-meilisearch --sync-policy automated

argocd app sync infra-postgres
argocd app sync infra-redis
argocd app sync infra-keycloak
argocd app sync infra-minio
argocd app sync infra-meilisearch
```

### Step 9: Verify Infrastructure

```bash
watch kubectl get pods -n infra -n auth -n data -n search
```

Wait for all pods to reach a healthy state.

### Step 10: Restore Data from Backup

```bash
kubectl cp /tmp/postgres-backup-*.sql infra/postgres-0:/tmp/backup.sql
kubectl exec -n infra postgres-0 -- psql -U postgres < /tmp/backup.sql

kubectl cp /tmp/redis-backup-*.rdb infra/redis-0:/data/dump.rdb
kubectl delete pod -n infra redis-0

kubectl cp /tmp/minio-backup-*.tar.gz data/minio-0:/tmp/buckets.tar.gz
kubectl exec -n data minio-0 -- tar xzf /tmp/buckets.tar.gz -C /
```

### Step 11: Recreate Platform Secrets (Old Format)

```bash
kubectl create secret generic gateway-secrets \
  --from-literal=OIDC_CLIENT_SECRET=<secret> \
  --from-literal=JWT_SECRET=<secret> \
  -n platform

kubectl create secret generic redis-conn \
  --from-literal=url=redis://:password@redis.infra.svc.cluster.local:6379/0 \
  -n platform

kubectl create secret generic db-secret \
  --from-literal=DATABASE_URL=postgresql://postgres:password@postgres.infra.svc.cluster.local:5432/platform?sslmode=disable \
  -n platform
```

### Step 12: Scale Up Applications

```bash
kubectl scale deployment gateway --replicas=1 -n platform
kubectl scale deployment provisioner --replicas=1 -n platform
# repeat for other services as needed

kubectl scale deployment shell --replicas=1 -n web
kubectl scale deployment qdrive --replicas=1 -n web
```

### Step 13: Verify Rollback Success

```bash
kubectl get pods --all-namespaces
argocd app list
kubectl port-forward -n platform deployment/gateway 8081:8081
curl http://localhost:8081/health
open https://preprod.qoffice.cloud
```

## 5. Post-Rollback Actions

- Update `docs/infra-migration-notes.md` with rollback details
- Produce an incident report with root cause and resolution plan
- Notify stakeholders that rollback is complete
- Identify remediation tasks required before attempting migration again
- Schedule a post-mortem and update this plan with lessons learned

## 6. Rollback Verification Checklist

- [ ] Infrastructure pods healthy (Bitnami images)
- [ ] All ArgoCD apps synced and healthy
- [ ] Gateway connects to Postgres, Redis, MinIO, Meilisearch
- [ ] Shell app loads and authentication works
- [ ] QDrive file operations function correctly
- [ ] No `CrashLoopBackOff` or `ImagePullBackOff`
- [ ] Data integrity verified (no loss or corruption)
- [ ] Performance metrics acceptable

## 7. Time Estimates

| Phase                    | Duration (min) |
| ------------------------ | -------------- |
| Preparation              | 10             |
| Infrastructure teardown  | 5              |
| Recreate Argo apps       | 10             |
| Infra startup            | 10             |
| Data restore             | 15             |
| Service restart          | 10             |
| Verification             | 10             |
| **Total**                | **60-70**      |

## 8. Rollback Risks

- Potential data loss if backups fail
- ~1 hour downtime for platform
- Drift between Git and cluster after manual changes
- Secret mismatches if rotation occurred after backup
- Bitnami image pull errors may reappear

## 9. Alternatives to Full Rollback

### Partial Rollback

```bash
argocd app set infra-minio --sync-policy none
kubectl delete statefulset -n data minio
git checkout <commit> root/apps/infra/minio-app.yaml
git push
argocd app set infra-minio --sync-policy automated
argocd app sync infra-minio
```

### Forward Fix

Attempt to remediate specific issues without rolling back by patching manifests, rotating secrets, or reapplying bootstrap procedures.

## 10. Contact Information

- Incident Commander: __________________
- Infrastructure Lead: __________________
- On-Call Engineer: __________________
- Escalation Contact: __________________