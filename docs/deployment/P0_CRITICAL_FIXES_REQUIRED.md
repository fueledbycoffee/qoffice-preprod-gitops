# P0 CRITICAL FIXES REQUIRED - IMMEDIATE ACTION

**Date**: 2025-10-17
**Priority**: P0 - PRODUCTION BLOCKER
**Status**: NO-GO - Authentication Broken
**Estimated Fix Time**: 75 minutes

---

## EXECUTIVE SUMMARY

Authentication is completely broken in preprod. Three critical blockers prevent any user from logging in:

1. **Keycloak HTTP Forms**: Login forms use HTTP, triggering browser security warnings
2. **qAccount Missing Config**: App loads blank due to missing configuration
3. **QDrive Localhost Errors**: App cannot load due to hardcoded localhost URLs

**GO/NO-GO**: **NO-GO** until all three fixed.

---

## BLOCKER 1: Keycloak HTTP Form Actions (P0)

### Problem
When users try to log in, browser displays: "Les informations que vous êtes sur le point de soumettre ne sont pas sécurisées"

Form action URL is HTTP:
```
http://keycloak.preprod.qoffice.cloud/realms/qoffice-preprod/login-actions/authenticate
```

Should be HTTPS:
```
https://keycloak.preprod.qoffice.cloud/realms/qoffice-preprod/login-actions/authenticate
```

### Root Cause
Keycloak is not configured to use HTTPS for frontend URLs. The OIDC discovery document shows HTTPS, but actual HTML form actions use HTTP.

### Fix Instructions

**Option 1: Update Keycloak Environment Variables (RECOMMENDED)**

Edit Keycloak deployment:
```bash
kubectl -n qoffice-preprod edit deployment keycloak
```

Add/update environment variables:
```yaml
env:
  - name: KC_HOSTNAME_URL
    value: "https://keycloak.preprod.qoffice.cloud"
  - name: KC_HOSTNAME_STRICT
    value: "true"
  - name: KC_HOSTNAME_STRICT_HTTPS
    value: "true"
  - name: KC_PROXY
    value: "edge"
  - name: KC_PROXY_HEADERS
    value: "xforwarded"
```

Restart Keycloak:
```bash
kubectl -n qoffice-preprod rollout restart deployment keycloak
kubectl -n qoffice-preprod rollout status deployment keycloak
```

**Option 2: Update Ingress Headers (if Option 1 doesn't work)**

Ensure Keycloak ingress passes X-Forwarded-Proto header:
```bash
kubectl -n qoffice-preprod edit ingress keycloak
```

Add annotation:
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Forwarded-Proto https;
      proxy_set_header X-Forwarded-Port 443;
```

### Verification Commands

```bash
# Check Keycloak environment
kubectl -n qoffice-preprod get deployment keycloak -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KC_HOSTNAME_URL")].value}'
# Expected: https://keycloak.preprod.qoffice.cloud

# Check ingress annotations
kubectl -n qoffice-preprod get ingress keycloak -o yaml | grep -A5 annotations

# Test OIDC config
curl -s https://keycloak.preprod.qoffice.cloud/realms/qoffice-preprod/.well-known/openid-configuration | jq -r '.issuer'
# Expected: https://keycloak.preprod.qoffice.cloud/realms/qoffice-preprod

# CRITICAL: Test actual login form (use browser inspector)
# Navigate to https://shell.preprod.qoffice.cloud
# Click login, inspect form element:
# <form action="https://keycloak.preprod.qoffice.cloud/..."> <!-- Should be HTTPS -->
```

### Success Criteria
- [ ] Login form action uses HTTPS (not HTTP)
- [ ] No browser security warnings when clicking "Sign In"
- [ ] Login completes successfully
- [ ] User redirected back to Shell dashboard

---

## BLOCKER 2: qAccount Missing Configuration (P0)

### Problem
qAccount app loads but shows blank page. Console error:
```
Error: The configuration object is missing the required 'url' property.
```

### Root Cause
qAccount app is not receiving required configuration for Keycloak and API URLs.

### Fix Instructions

**Check Current Deployment:**
```bash
kubectl -n qoffice-preprod get deployment qaccount -o yaml | grep -A20 "env:"
```

**Option 1: Add Environment Variables**

Edit qAccount deployment:
```bash
kubectl -n qoffice-preprod edit deployment qaccount
```

Add environment variables:
```yaml
env:
  - name: VITE_KEYCLOAK_URL
    value: "https://keycloak.preprod.qoffice.cloud"
  - name: VITE_KEYCLOAK_REALM
    value: "qoffice-preprod"
  - name: VITE_KEYCLOAK_CLIENT_ID
    value: "qaccount"
  - name: VITE_API_URL
    value: "https://api.preprod.qoffice.cloud"
```

Restart deployment:
```bash
kubectl -n qoffice-preprod rollout restart deployment qaccount
kubectl -n qoffice-preprod rollout status deployment qaccount
```

**Option 2: Rebuild with Config (if env vars don't work)**

If app expects config at build time:
```bash
cd /media/sean/SHARED/qOffice/qoffice-preprod-gitops/apps/qaccount

# Build with correct environment
VITE_KEYCLOAK_URL=https://keycloak.preprod.qoffice.cloud \
VITE_KEYCLOAK_REALM=qoffice-preprod \
VITE_KEYCLOAK_CLIENT_ID=qaccount \
VITE_API_URL=https://api.preprod.qoffice.cloud \
pnpm run build

# Rebuild and push image
docker build -t ghcr.io/qoffice/qaccount:preprod-fix .
docker push ghcr.io/qoffice/qaccount:preprod-fix

# Update deployment
kubectl -n qoffice-preprod set image deployment/qaccount qaccount=ghcr.io/qoffice/qaccount:preprod-fix
```

### Verification Commands

```bash
# Check environment variables
kubectl -n qoffice-preprod get deployment qaccount -o jsonpath='{.spec.template.spec.containers[0].env}'

# Check pod logs for errors
kubectl -n qoffice-preprod logs -l app=qaccount --tail=50

# Test in browser
# Navigate to https://qaccount.preprod.qoffice.cloud
# Should see registration/account management UI (not blank page)
# Open console - should see NO configuration errors
```

### Success Criteria
- [ ] qAccount loads with visible UI
- [ ] No console errors about missing configuration
- [ ] Registration form accessible
- [ ] Page not blank

---

## BLOCKER 3: QDrive Localhost References (P0)

### Problem
QDrive shows error: "Ce site est inaccessible - localhost n'autorise pas la connexion"
Error code: ERR_CONNECTION_REFUSED

### Root Cause
QDrive has hardcoded localhost URLs instead of preprod.qoffice.cloud URLs.

### Fix Instructions

**Check Current Configuration:**
```bash
kubectl -n qoffice-preprod get deployment qdrive -o yaml | grep -A20 "env:"
```

**Option 1: Add/Fix Environment Variables**

Edit QDrive deployment:
```bash
kubectl -n qoffice-preprod edit deployment qdrive
```

Ensure these environment variables are set:
```yaml
env:
  - name: VITE_API_URL
    value: "https://api.preprod.qoffice.cloud"
  - name: VITE_KEYCLOAK_URL
    value: "https://keycloak.preprod.qoffice.cloud"
  - name: VITE_KEYCLOAK_REALM
    value: "qoffice-preprod"
  - name: VITE_KEYCLOAK_CLIENT_ID
    value: "qdrive"
  - name: VITE_WOPI_URL
    value: "https://wopi.preprod.qoffice.cloud"
```

Restart deployment:
```bash
kubectl -n qoffice-preprod rollout restart deployment qdrive
kubectl -n qoffice-preprod rollout status deployment qdrive
```

**Option 2: Rebuild with Correct URLs**

If localhost is hardcoded in source:
```bash
# Search for localhost references
cd /media/sean/SHARED/qOffice/qoffice-preprod-gitops/apps/qdrive
grep -r "localhost" src/

# Replace with preprod URLs and rebuild
VITE_API_URL=https://api.preprod.qoffice.cloud \
VITE_KEYCLOAK_URL=https://keycloak.preprod.qoffice.cloud \
VITE_KEYCLOAK_REALM=qoffice-preprod \
VITE_KEYCLOAK_CLIENT_ID=qdrive \
pnpm run build

# Rebuild and push image
docker build -t ghcr.io/qoffice/qdrive:preprod-fix .
docker push ghcr.io/qoffice/qdrive:preprod-fix

# Update deployment
kubectl -n qoffice-preprod set image deployment/qdrive qdrive=ghcr.io/qoffice/qdrive:preprod-fix
```

### Verification Commands

```bash
# Check environment variables
kubectl -n qoffice-preprod get deployment qdrive -o jsonpath='{.spec.template.spec.containers[0].env}'

# Check pod logs
kubectl -n qoffice-preprod logs -l app=qdrive --tail=50

# Test in browser
# Navigate to https://qdrive.preprod.qoffice.cloud
# Should load file browser UI (not localhost error)
```

### Success Criteria
- [ ] QDrive loads without localhost errors
- [ ] Login flow works
- [ ] File browser displays
- [ ] No localhost references in network tab

---

## VERIFICATION CHECKLIST

After applying all three fixes, run complete validation:

### Quick Smoke Test
```bash
# 1. Test Gateway
curl https://api.preprod.qoffice.cloud/health
# Expected: {"service":"gateway","status":"ok","version":"1.0.0"}

# 2. Test Keycloak OIDC
curl -s https://keycloak.preprod.qoffice.cloud/realms/qoffice-preprod/.well-known/openid-configuration | jq -r '.issuer'
# Expected: https://keycloak.preprod.qoffice.cloud/realms/qoffice-preprod (HTTPS)

# 3. Check all deployments
kubectl -n qoffice-preprod get deployments
# All should show READY
```

### Full Authentication Test
1. Open https://shell.preprod.qoffice.cloud in incognito window
2. Click "Login" button
3. Should redirect to Keycloak (HTTPS URL)
4. Enter credentials: alice@tenant1.local / password123
5. Click "Sign In"
6. **CRITICAL**: Should NOT show security warning
7. Should redirect back to Shell
8. Should display dashboard with user info

### App-Specific Tests
```bash
# qAccount
# Navigate to https://qaccount.preprod.qoffice.cloud
# Should show registration/account UI (not blank)
# Open console - no config errors

# QDrive
# Navigate to https://qdrive.preprod.qoffice.cloud
# Should show file browser (not localhost error)
# Login should work
```

---

## TIMELINE

| Task | Estimated Time | Owner |
|------|----------------|-------|
| Fix Keycloak HTTPS | 15 minutes | DevOps |
| Fix qAccount Config | 15 minutes | Service Builder |
| Fix QDrive Localhost | 15 minutes | Service Builder |
| Verification Testing | 30 minutes | QA Specialist |
| **TOTAL** | **75 minutes** | |

---

## CONTACTS

**DevOps Team**: Keycloak configuration fix
**Service Builder Team**: qAccount and QDrive fixes
**QA Specialist**: Validation after fixes

---

## NEXT STEPS

1. DevOps: Fix Keycloak HTTPS configuration (Blocker 1)
2. Service Builder: Fix qAccount config (Blocker 2)
3. Service Builder: Fix QDrive localhost (Blocker 3)
4. QA: Re-run P0 validation suite
5. QA: Generate GO/NO-GO decision

**Only proceed to production after all blockers resolved and validation passes.**

---

**Report Generated**: 2025-10-17
**Related Document**: `/media/sean/SHARED/qOffice/qoffice-preprod-gitops/docs/testing/P0_VALIDATION_TEST_RESULTS.md`
