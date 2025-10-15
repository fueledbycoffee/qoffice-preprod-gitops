# Preprod Infrastructure Migration Notes

## Status (2025-10-15)
- Bitnami Helm sources removed for postgres, redis, keycloak.
- Kustomize bases added at `root/infra/{postgres,redis,keycloak}` using official images (`postgres:16`, `redis:7.2`, `quay.io/keycloak/keycloak:26.0`).
- Secrets generated via kustomize use placeholder credentials (`change-me`). These were applied once during testing; replace with Vault-backed or manually created secrets before pushing to main.
- Applied manifests manually on preprod host (`kubectl apply -k ~/qoffice-preprod-gitops/root/infra/*`).
- Redis pod from new manifest is running. Postgres and Keycloak pods pending readiness while legacy Bitnami statefulsets remain under Argo control.

## Required Follow-up
1. Update placeholder secrets with real values and commit sealed versions or document manual creation.
2. Commit and push GitOps repo changes, then remove or disable the old ArgoCD applications so only the new kustomize apps reconcile.
3. Resync ArgoCD (`infra-postgres`, `infra-redis`, `infra-keycloak`) after push; verify pods reach `Running`.
4. Recreate downstream secrets (e.g. `gateway-secrets`) once databases are healthy.
5. Trigger CI/CD for platform and web apps; monitor namespace rollouts (`kubectl get pods -n platform`, `-n web`).
6. Re-run validation checklist in `DEVOPS_HANDOFF.md` Section 9.

## Commands Run
```
scp -r qoffice-preprod-gitops ubuntu@62.210.94.91:~/
kubectl delete statefulset infra-postgres-postgresql -n infra --ignore-not-found
kubectl delete statefulset infra-redis-master -n infra --ignore-not-found
kubectl delete statefulset infra-redis-replicas -n infra --ignore-not-found
kubectl delete statefulset infra-keycloak -n auth --ignore-not-found
kubectl delete secret pg-secrets -n infra --ignore-not-found
kubectl delete secret redis-secrets -n infra --ignore-not-found
kubectl delete secret keycloak-admin -n auth --ignore-not-found
kubectl apply -k ~/qoffice-preprod-gitops/root/infra/postgres
kubectl apply -k ~/qoffice-preprod-gitops/root/infra/redis
kubectl apply -k ~/qoffice-preprod-gitops/root/infra/keycloak
kubectl get pods -n infra
```

## Next Steps for Full Preprod
- After infra stabilizes, sync remaining infra apps (minio, meilisearch) and verify S3/search credentials.
- Roll platform services sequentially once gateway secrets restored.
- Roll web apps after backend APIs healthy; confirm ingress TLS via cert-manager.
- Capture final cluster state in runbook for future on-call rotations.
