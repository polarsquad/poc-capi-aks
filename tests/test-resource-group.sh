#!/bin/bash
# Test: Azure Resource Group validation

set -euo pipefail

echo "Testing Azure Resource Group..."

# Get RG name from Terraform output
if [ -f "terraform/terraform.tfstate" ]; then
    RG_NAME=$(terraform -chdir=terraform output -raw azure_resource_group_name 2>/dev/null || echo "")
fi

# Fallback to environment variable
RG_NAME="${RG_NAME:-${AZURE_RESOURCE_GROUP_NAME:-aks-workload-cluster-rg}}"

# Test resource group exists
if ! az group show --name "$RG_NAME" >/dev/null 2>&1; then
    echo "❌ FAIL: Resource group '$RG_NAME' not found"
    exit 1
fi
echo "✅ PASS: Resource group '$RG_NAME' exists"

# Test location
LOCATION=$(az group show --name "$RG_NAME" --query location -o tsv)
echo "✅ PASS: Resource group location: $LOCATION"

echo "✅ All resource group tests passed"
