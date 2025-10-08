#!/bin/bash
# Test Script: test-service-principal.sh

# Derive Service Principal name from Terraform output if available, otherwise fall back.
if command -v terraform >/dev/null 2>&1 && [ -f "terraform/terraform.tfstate" ]; then
    TF_SP_NAME=$(terraform -chdir=terraform output -raw service_principal_name 2>/dev/null || true)
fi

# Fallback: parse terraform.tfvars (simple grep) if not obtained above
if [ -z "$TF_SP_NAME" ] && [ -f "terraform/terraform.tfvars" ]; then
    TF_SP_NAME=$(grep -E '^service_principal_name\s*=' terraform/terraform.tfvars | head -n1 | awk -F'=' '{gsub(/"| /, "", $2); print $2}')
fi

# Final fallback: environment variable or default
SP_NAME="${TF_SP_NAME:-${SERVICE_PRINCIPAL_NAME:-aks-workload-cluster-sp}}"
echo "Using Service Principal name: $SP_NAME"

echo "Testing Service Principal and RBAC..."

# Test if service principal exists
SP_ID=$(az ad sp list --display-name $SP_NAME --query "[0].appId" -o tsv)
if [ -n "$SP_ID" ]; then
    echo "PASS: Service principal exists (ID: $SP_ID)"
else
    echo "FAIL: Service principal not found"
    exit 1
fi

# Test role assignment
az role assignment list --assignee $SP_ID --scope "/subscriptions/$(az account show --query id -o tsv)" \
    --query "[?roleDefinitionName=='Contributor']" -o tsv >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "PASS: Service principal has Contributor role"
else
    echo "FAIL: Service principal missing required permissions"
    exit 1
fi

echo "Service principal tests completed successfully"
