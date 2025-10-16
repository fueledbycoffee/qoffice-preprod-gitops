# Preprod Infrastructure Migration Notes

## Status (2025-10-15 18:55 UTC)
- Postgres, Redis, Keycloak Helm references replaced by Kustomize manifests using official images (`postgres:16`, `redis:7.2`, `quay.io/keycloak/keycloak:26.0`).
- ArgoCD applications updated to point at local manifests with `ignoreDifferences` for secrets to avoid password churn.
- Secrets rotated locally to strong passwords. GitOps repo now stores base64 `data` values instead of `stringData`.
- Postgres statefulset/PVC wiped and recreated; pod now running on fresh volume.
- Bootstrap SQL still needs to be executed inside the pod to create application databases/users.
- Gateway/platform/web pods still crash until new secrets/DBs are in place.

## Credentials (store securely outside repo)
- `postgres-secret` (infra namespace):
  - `POSTGRES_PASSWORD`: `qJVMaAoH+FN0GdLCt+mEtQ5Equrr8EpM`
  - `KEYCLOAK_PASSWORD`: `TLq5X^83bIb@#suZ&fVRcNGu=3^PzBiC`
  - `PLATFORM_PASSWORD`: `Na@pRiU)^Y&he5t#xsx0G6(CsEmQZ3wZ`
  - `REDIS_PASSWORD`: `rQ_!dZFA9a#(1WE9J68QR!H3FZXTP()Q`

## What was done today
1. Deleted legacy Bitnami statefulsets/secrets.
2. Created new Kustomize manifests and secrets for Postgres/Redis/Keycloak.
3. Applied manifests manually via `kubectl apply -k`.
4. Rotated secrets with strong passwords; updated GitOps repo accordingly.
5. Deleted Postgres statefulset and PVC, patched finalizer, re-applied manifest.
6. Verified pod running, ready, and reading new env values.
7. Documented commands and passwords here for Ops handoff.

## Commands (2025-10-15 afternoon)
```
scp -r qoffice-preprod-gitops ubuntu@62.210.94.91:~/
kubectl delete statefulset postgres -n infra
kubectl delete pvc data-postgres-0 -n infra
kubectl patch pvc data-postgres-0 -n infra --type merge --patch '{"metadata":{"finalizers":[]}}'
kubectl apply -f root/infra/postgres/secret.yaml
kubectl apply -f root/infra/postgres/configmap.yaml
kubectl apply -f root/infra/postgres/statefulset.yaml
kubectl get pods -n infra
```

## Next Immediate Steps (P0)
1. Exec into Postgres pod and run bootstrap SQL:
   ```bash
   kubectl cp /tmp/postgres-bootstrap.sql infra/postgres-0:/tmp/postgres-bootstrap.sql
   kubectl exec -n infra postgres-0 -- env PGPASSWORD='change-me' psql -h localhost -U root -d postgres -f /tmp/postgres-bootstrap.sql
   ```
2. Update platform namespace secrets:
   ```bash
   kubectl create secret generic db-secret -n platform \
     --from-literal=DATABASE_URL=postgresql://postgres:qJVMaAoH+FN0GdLCt+mEtQ5Equrr8EpM@postgres.infra.svc.cluster.local:5432/postgres?sslmode=disable --dry-run=client -o yaml | kubectl apply -f -
   kubectl create secret generic redis-conn -n platform \
     --from-literal=url=redis://:rQ_!dZFA9a#(1WE9J68QR!H3FZXTP()Q@redis.infra.svc.cluster.local:6379 --dry-run=client -o yaml | kubectl apply -f -
   ```
3. Rotate any app-specific secrets (gateway, keycloak env) to match new DB passwords.
4. Restart platform and web deployments after secrets updated.

## Outstanding (P1/P2)
- Verify gateway logs after reconnecting to DB/Redis.
- Re-enable ArgoCD auto-sync on infra apps once credentials are stable.
- Configure remaining infra services (MinIO, MeiliSearch, etc.) with new secrets.
- Execute bootstrap for Keycloak DB schema once service starts.
- Prepare final runbook once pods stable.

_Last updated: 2025-10-15 18:55 UTC_