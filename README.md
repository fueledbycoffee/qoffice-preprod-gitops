# qOffice Preprod GitOps

This repo is managed by Argo CD. Root app points to root/kustomization.yaml which aggregates infra and app Applications.

- Infra: Bitnami charts (PostgreSQL, Redis, MinIO, Meilisearch, Keycloak)
- Services: gateway
- Web: shell

Argo CD root Application should reference:
  repo: https://github.com/fueledbycoffee/qoffice-preprod-gitops.git
  path: root
