# qOffice Preprod Bootstrap Procedures

## 1. Overview

This document describes the required bootstrap sequence for the preprod environment after migrating infrastructure components from Bitnami Helm charts to Kustomize manifests. Completing these steps resolves the P0 blockers identified in `docs/infra-migration-notes.md` and brings the platform to an operational state.

## 2. Prerequisites

- K3s cluster reachable at `ubuntu@62.210.94.91`
- `kubectl` configured with access to the cluster
- ArgoCD CLI installed and authenticated (or access to ArgoCD UI)
- `qoffice-preprod-gitops` repository cloned locally
- Generated credentials and secrets stored securely (see `root/apps/platform-secrets/`)

## 3. Infrastructure Bootstrap Sequence

### Step 1: Apply Infrastructure Manifests

```bash
kubectl apply -k root/infra/postgres
kubectl apply -k root/infra/redis
kubectl apply -k root/infra/keycloak
kubectl apply -k root/infra/minio
kubectl apply -k root/infra/meilisearch
```

### Step 2: Wait for Infrastructure Pods

```bash
kubectl get pods -n infra
kubectl get pods -n auth
kubectl get pods -n data
kubectl get pods -n search
```

Ensure every pod reports `Running` and `Ready (1/1)`. Initial startup can take several minutes.

### Step 3: Execute Postgres Bootstrap SQL

The `init.sql` config map should seed roles and databases. Verify:

```bash
kubectl exec -n infra postgres-0 -- psql -U postgres -c "\l"
```

Expected databases: `postgres`, `qoffice`, `keycloak`, `platform`.

If missing, execute manually:

```bash
kubectl exec -n infra postgres-0 -- psql -U postgres <<'EOF'
CREATE ROLE qoffice LOGIN PASSWORD 'qJVMaAoH+FN0GdLCt+mEtQ5Equrr8EpM';
CREATE ROLE keycloak LOGIN PASSWORD 'TLq5X^83bIb@#suZ&fVRcNGu=3^PzBiC';
CREATE ROLE platform LOGIN PASSWORD 'Na@pRiU)^Y&he5t#xsx0G6(CsEmQZ3wZ';
CREATE DATABASE qoffice OWNER qoffice;
CREATE DATABASE keycloak OWNER keycloak;
CREATE DATABASE platform OWNER platform;
EOF
```

### Step 4: Sync Vault & External Secrets Controllers

```bash
argocd app sync ops-vault
argocd app sync ops-external-secrets
kubectl get pods -n vault
kubectl get pods -n external-secrets
```

Wait until all pods in `vault` and `external-secrets` report `Running`/`Ready` before continuing.

### Step 5: Initialize and Unseal Vault

1. Initialise Vault once (store the unseal key and root token safely):
   ```bash
   kubectl exec -n vault statefulset/vault -- vault operator init -key-shares=1 -key-threshold=1
   ```
2. Unseal each Vault pod:
   ```bash
   kubectl exec -n vault pod/vault-0 -- vault operator unseal <UNSEAL_KEY>
   kubectl exec -n vault pod/vault-1 -- vault operator unseal <UNSEAL_KEY>
   kubectl exec -n vault pod/vault-2 -- vault operator unseal <UNSEAL_KEY>
   ```
3. Enable the Kubernetes auth method and map the External Secrets service account (run once):
   ```bash
   vault auth enable kubernetes

   vault write auth/kubernetes/config \
     token_reviewer_jwt="$(kubectl get secret -n external-secrets external-secrets-sa -o jsonpath='{.data.token}' | base64 -d)" \
     kubernetes_host="https://kubernetes.default.svc" \
     kubernetes_ca_cert="$(kubectl get configmap -n kube-system kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')"

   vault policy write external-secrets -<<EOF
   path "kv/data/preprod/*" {
     capabilities = ["read"]
   }
   EOF

   vault write auth/kubernetes/role/external-secrets \
     bound_service_account_names=external-secrets \
     bound_service_account_namespaces=external-secrets \
     policies=external-secrets \
     ttl=24h
   ```

### Step 6: Seed Vault Secrets

Populate Vault KV paths with the credentials used by infrastructure and platform workloads (replace placeholders with actual values):

```bash
vault kv put kv/preprod/infra/minio MINIO_ROOT_USER=<user> MINIO_ROOT_PASSWORD=<password>
vault kv put kv/preprod/infra/meilisearch MEILI_MASTER_KEY=<master-key>
vault kv put kv/preprod/infra/postgres \
  POSTGRES_DB=postgres \
  POSTGRES_USER=postgres \
  POSTGRES_PASSWORD=<postgres-admin-password> \
  QOFFICE_DB=qoffice \
  QOFFICE_USER=qoffice \
  QOFFICE_PASSWORD=<qoffice-password> \
  KEYCLOAK_DB=keycloak \
  KEYCLOAK_USER=keycloak \
  KEYCLOAK_PASSWORD=<keycloak-db-password> \
  PLATFORM_DB=platform \
  PLATFORM_USER=platform \
  PLATFORM_PASSWORD=<platform-db-password> \
  REDIS_PASSWORD=<redis-sidecar-password>
vault kv put kv/preprod/infra/keycloak \
  KEYCLOAK_ADMIN=<admin-user> \
  KEYCLOAK_ADMIN_PASSWORD=<admin-password> \
  KC_DB_USERNAME=keycloak \
  KC_DB_PASSWORD=<keycloak-db-password>
vault kv put kv/preprod/platform/gateway OIDC_CLIENT_SECRET=<secret> JWT_SECRET=<secret>
vault kv put kv/preprod/platform/db DATABASE_URL=<postgres-url>
vault kv put kv/preprod/platform/redis url=<redis-url>
```

Record all inserted values in the secure secrets registry.

### Step 7: Verify ExternalSecret Reconciliation

```bash
kubectl get clustersecretstores.external-secrets.io
kubectl get externalsecrets.external-secrets.io --all-namespaces
kubectl get secrets -n data
kubectl get secrets -n search
kubectl get secrets -n platform
```

Ensure generated Kubernetes Secrets (e.g., `minio-secret`, `meilisearch-secret`, `gateway-secrets`, `db-secret`, `redis-conn`) exist and timestamps reflect recent reconciliation.

### Step 8: Configure Keycloak

1. Wait for Keycloak readiness:

   ```bash
   kubectl wait --for=condition=ready pod -l app=keycloak -n auth --timeout=300s
   ```

2. Access admin console at `https://keycloak.preprod.qoffice.cloud` using credentials from `keycloak-admin` secret.

3. Import realm (`infrastructure/keycloak/realms/qoffice-dev.json`) and clients (see `infrastructure/keycloak/clients/`).

4. Update `gateway-secrets` with the actual OIDC client secret generated in Keycloak if it differs from the placeholder.

### Step 6: Provision MinIO Buckets

Option 1 (console): Sign in at `https://minio.preprod.qoffice.cloud` and create bucket `t-tenant-preprod`.

Option 2 (`mc` CLI):

```bash
mc alias set preprod https://minio.preprod.qoffice.cloud qoffice-minio <password>
mc mb preprod/t-tenant-preprod
```

Credentials come from `root/infra/minio/secret.yaml`.

### Step 7: Provision Meilisearch Indices

```bash
export MEILISEARCH_HOST=https://search.preprod.qoffice.cloud
export MEILISEARCH_MASTER_KEY=<value from meilisearch-secret>
cd infrastructure/meilisearch
./provision-indices.sh
```

Verify indices `files`, `mail_messages`, `people`, `chat_messages`, and `events`.

## 4. Service Bootstrap Sequence

### Step 8: Sync ArgoCD Applications

```bash
argocd app sync infra-postgres
argocd app sync infra-redis
argocd app sync infra-keycloak
argocd app sync infra-minio
argocd app sync infra-meilisearch
argocd app sync platform-secrets
argocd app sync svc-gateway
argocd app sync web-shell
```

Sync remaining services and web apps after core components stabilize.

### Step 9: Gateway Migrations

Check logs:

```bash
kubectl logs -n platform deployment/gateway --tail=100
```

If migrations did not run automatically:

```bash
kubectl exec -n platform deployment/gateway -- /app/gateway migrate
```

### Step 10: Verify Service Health

```bash
kubectl get pods --all-namespaces
kubectl port-forward -n platform deployment/gateway 8081:8081
curl http://localhost:8081/health
kubectl port-forward -n web deployment/shell 80:80
curl http://localhost:80
```

### Operator Handover Notes

- Record the Vault init/unseal material in the secure secrets registry and document the standard unseal cadence (who and when) so restarts can be handled without delay.
- Confirm the Vault `kv/preprod/*` namespace owners; each service team must know where to request or rotate credentials.
- Capture the GitOps sync order in the release checklist: `ops-vault` → `ops-external-secrets` → infrastructure apps (`infra-*`) → `platform-secrets` → dependent services/web apps.
- After seeding Vault, validate that ExternalSecret resources reconcile cleanly (`kubectl describe externalsecret -n <ns> <name>`) and capture any remediation steps if drift occurs.

## 5. Verification Checklist

- [ ] Infrastructure pods `Running` and `Ready`
- [ ] Postgres roles/databases created (`qoffice`, `keycloak`, `platform`)
- [ ] Platform secrets applied (`gateway-secrets`, `redis-conn`, `db-secret`)
- [ ] Keycloak realm imported and clients provisioned
- [ ] MinIO bucket `t-tenant-preprod` exists
- [ ] Meilisearch indices provisioned
- [ ] Gateway service healthy and migrations complete
- [ ] Shell application accessible
- [ ] No `CrashLoopBackOff` pods cluster-wide

## 6. Troubleshooting

### Postgres Connectivity

```bash
kubectl exec -n platform deployment/gateway -- sh -c 'apk add postgresql-client && psql $DB_URL -c "SELECT 1"'
```

### Redis Connectivity

```bash
kubectl exec -n platform deployment/gateway -- sh -c 'apk add redis && redis-cli -u $REDIS_URL PING'
```

### MinIO Health

```bash
kubectl exec -n platform deployment/gateway -- wget -O- http://minio.data.svc.cluster.local:9000/minio/health/live
```

### Meilisearch Health

```bash
kubectl exec -n platform deployment/gateway -- wget -O- http://meilisearch.search.svc.cluster.local:7700/health
```

## 7. Rollback Procedures

- Pause ArgoCD auto-sync for infra apps:

  ```bash
  argocd app set infra-postgres --sync-policy none
  # repeat for redis, keycloak, minio, meilisearch, platform-secrets
  ```

- Delete failing namespaces (`infra`, `auth`, `data`, `search`, `platform`) if rollback is required.
- Restore previous manifests (Bitnami Helm) via Git history.
- Reapply original secrets (`minio-secrets`, `meili-secrets`, etc.).
- Resync applications and re-run bootstrap.

For comprehensive rollback steps, refer to `docs/ROLLBACK_PLAN.md`.

## 8. References

- `docs/infra-migration-notes.md`
- `root/infra/postgres/configmap.yaml`
- `root/apps/platform-secrets/`
- `infrastructure/keycloak/import.sh`
- `infrastructure/meilisearch/provision-indices.sh`