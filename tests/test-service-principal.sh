#!/bin/bash
# Test: Azure Service Principal validation

set -euo pipefail

CAPI_CLUSTER_NAME="${CAPI_CLUSTER_NAME:-capi-mgmt}"
MGMT_KUBECONFIG="${HOME}/.kube/${CAPI_CLUSTER_NAME}.kubeconfig"

echo "Testing Azure Service Principal..."

# Get SP name from Terraform output
if [ -f "terraform/terraform.tfstate" ]; then
    SP_NAME=$(terraform -chdir=terraform output -raw azure_service_principal_name 2>/dev/null || echo "")
fi

# Fallback to environment variable
SP_NAME="${SP_NAME:-${AZURE_SERVICE_PRINCIPAL_NAME:-aks-workload-cluster-sp}}"

# Test SP exists in Azure AD
SP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null)
if [ -z "$SP_ID" ]; then
    echo "❌ FAIL: Service principal '$SP_NAME' not found in Azure AD"
    exit 1
fi
echo "✅ PASS: Service principal exists (App ID: $SP_ID)"

# Test Contributor role assignment
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
ROLE_COUNT=$(az role assignment list --assignee "$SP_ID" --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --query "[?roleDefinitionName=='Contributor'] | length(@)" -o tsv)

if [ "$ROLE_COUNT" -gt 0 ]; then
    echo "✅ PASS: Service principal has Contributor role"
else
    echo "❌ FAIL: Service principal missing Contributor role"
    exit 1
fi

# Test secret exists in management cluster
if [ -f "$MGMT_KUBECONFIG" ]; then
    if kubectl --kubeconfig="$MGMT_KUBECONFIG" get secret azure-cluster-identity -n default >/dev/null 2>&1; then
        echo "✅ PASS: Azure cluster identity secret exists in management cluster"
    else
        echo "❌ FAIL: Azure cluster identity secret not found"
        exit 1
    fi
fi

echo "✅ All service principal tests passed"
