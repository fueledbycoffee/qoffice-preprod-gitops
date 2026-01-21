#!/bin/bash
# P0 Authentication Blockers - Quick Fix Script
# DO NOT RUN AUTOMATICALLY - Review each section and execute manually

set -e

echo "=========================================="
echo "P0 AUTHENTICATION BLOCKERS - FIX SCRIPT"
echo "=========================================="
echo ""
echo "This script contains commands to fix 3 critical authentication blockers."
echo "Review each section and execute commands manually."
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}BLOCKER 1: KEYCLOAK HTTP FORM ACTIONS${NC}"
echo "Problem: Login forms use HTTP instead of HTTPS"
echo ""
echo "Step 1: Check current Keycloak configuration"
echo "kubectl -n qoffice-preprod get deployment keycloak -o jsonpath='{.spec.template.spec.containers[0].env}' | jq"
echo ""
echo "Step 2: Update Keycloak environment variables"
echo "Run this command to edit deployment:"
echo "kubectl -n qoffice-preprod edit deployment keycloak"
echo ""
echo "Add these environment variables:"
cat << 'EOF'
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
EOF
echo ""
echo "Step 3: Restart Keycloak"
echo "kubectl -n qoffice-preprod rollout restart deployment keycloak"
echo "kubectl -n qoffice-preprod rollout status deployment keycloak"
echo ""
echo "Step 4: Verify fix"
echo "curl -s https://keycloak.preprod.qoffice.cloud/realms/qoffice-preprod/.well-known/openid-configuration | jq -r '.issuer'"
echo "Expected: https://keycloak.preprod.qoffice.cloud/realms/qoffice-preprod"
echo ""
echo "Press Enter to continue to Blocker 2..."
read

echo ""
echo -e "${RED}BLOCKER 2: QACCOUNT MISSING CONFIGURATION${NC}"
echo "Problem: qAccount loads blank page with config error"
echo ""
echo "Step 1: Check current qAccount configuration"
echo "kubectl -n qoffice-preprod get deployment qaccount -o yaml | grep -A20 'env:'"
echo ""
echo "Step 2: Add environment variables"
echo "Run this command to edit deployment:"
echo "kubectl -n qoffice-preprod edit deployment qaccount"
echo ""
echo "Add these environment variables:"
cat << 'EOF'
  - name: VITE_KEYCLOAK_URL
    value: "https://keycloak.preprod.qoffice.cloud"
  - name: VITE_KEYCLOAK_REALM
    value: "qoffice-preprod"
  - name: VITE_KEYCLOAK_CLIENT_ID
    value: "qaccount"
  - name: VITE_API_URL
    value: "https://api.preprod.qoffice.cloud"
EOF
echo ""
echo "Step 3: Restart qAccount"
echo "kubectl -n qoffice-preprod rollout restart deployment qaccount"
echo "kubectl -n qoffice-preprod rollout status deployment qaccount"
echo ""
echo "Step 4: Verify fix"
echo "kubectl -n qoffice-preprod logs -l app=qaccount --tail=20"
echo "Then open https://qaccount.preprod.qoffice.cloud in browser"
echo "Should show UI (not blank page)"
echo ""
echo "Press Enter to continue to Blocker 3..."
read

echo ""
echo -e "${RED}BLOCKER 3: QDRIVE LOCALHOST REFERENCES${NC}"
echo "Problem: QDrive tries to connect to localhost"
echo ""
echo "Step 1: Check current QDrive configuration"
echo "kubectl -n qoffice-preprod get deployment qdrive -o yaml | grep -A20 'env:'"
echo ""
echo "Step 2: Add/fix environment variables"
echo "Run this command to edit deployment:"
echo "kubectl -n qoffice-preprod edit deployment qdrive"
echo ""
echo "Add these environment variables:"
cat << 'EOF'
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
EOF
echo ""
echo "Step 3: Restart QDrive"
echo "kubectl -n qoffice-preprod rollout restart deployment qdrive"
echo "kubectl -n qoffice-preprod rollout status deployment qdrive"
echo ""
echo "Step 4: Verify fix"
echo "kubectl -n qoffice-preprod logs -l app=qdrive --tail=20"
echo "Then open https://qdrive.preprod.qoffice.cloud in browser"
echo "Should load file browser (not localhost error)"
echo ""
echo "Press Enter to continue to verification..."
read

echo ""
echo -e "${GREEN}VERIFICATION CHECKLIST${NC}"
echo ""
echo "Run these commands to verify all fixes:"
echo ""
echo "1. Gateway Health Check:"
echo "curl https://api.preprod.qoffice.cloud/health"
echo ""
echo "2. Keycloak OIDC Configuration:"
echo "curl -s https://keycloak.preprod.qoffice.cloud/realms/qoffice-preprod/.well-known/openid-configuration | jq -r '.issuer'"
echo ""
echo "3. All Deployments Status:"
echo "kubectl -n qoffice-preprod get deployments"
echo ""
echo "4. Pod Status:"
echo "kubectl -n qoffice-preprod get pods"
echo ""
echo "5. Check for errors in all pods:"
echo "kubectl -n qoffice-preprod logs -l app=keycloak --tail=20"
echo "kubectl -n qoffice-preprod logs -l app=qaccount --tail=20"
echo "kubectl -n qoffice-preprod logs -l app=qdrive --tail=20"
echo ""
echo -e "${YELLOW}MANUAL BROWSER TEST REQUIRED:${NC}"
echo ""
echo "Open https://shell.preprod.qoffice.cloud in incognito window"
echo "1. Click 'Login' button"
echo "2. Enter credentials: alice@tenant1.local / password123"
echo "3. Click 'Sign In'"
echo "4. VERIFY: NO security warning appears"
echo "5. VERIFY: Redirects back to Shell dashboard"
echo "6. VERIFY: User info displayed"
echo ""
echo "If all verifications pass, authentication is fixed!"
echo ""
echo -e "${GREEN}=========================================="
echo "FIX SCRIPT COMPLETE"
echo "==========================================${NC}"
