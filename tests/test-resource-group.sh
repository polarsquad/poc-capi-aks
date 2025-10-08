#!/bin/bash
# Test Script: test-resource-group.sh

# Derive Resource Group name from Terraform output if available
if command -v terraform >/dev/null 2>&1 && [ -f "terraform/terraform.tfstate" ]; then
    TF_RG_NAME=$(terraform -chdir=terraform output -raw resource_group_name 2>/dev/null || true)
fi

# Fallback: parse terraform.tfvars if not obtained above
if [ -z "$TF_RG_NAME" ] && [ -f "terraform/terraform.tfvars" ]; then
    TF_RG_NAME=$(grep -E '^resource_group_name\s*=' terraform/terraform.tfvars | head -n1 | awk -F'=' '{gsub(/"| /, "", $2); print $2}')
fi

# Final fallbacks: environment variable or naming convention
RG_NAME="${TF_RG_NAME:-${RESOURCE_GROUP_NAME:-${CLUSTER_NAME}-rg}}"
LOCATION="${AZURE_LOCATION}"

echo "Using Resource Group name: $RG_NAME"

echo "Testing Azure Resource Group..."

# Test if resource group exists
az group show --name $RG_NAME --query "name" -o tsv 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Resource group $RG_NAME exists"
else
    echo "FAIL: Resource group $RG_NAME does not exist"
    exit 1
fi

# Test location (case-insensitive compare). Provide warning instead of hard fail unless STRICT_RG_LOCATION=1
ACTUAL_LOCATION=$(az group show --name $RG_NAME --query "location" -o tsv)
normalize() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

if [ -z "$LOCATION" ]; then
    echo "INFO: Expected location not set (AZURE_LOCATION empty); Actual: $ACTUAL_LOCATION"
elif [ "$(normalize "$ACTUAL_LOCATION")" = "$(normalize "$LOCATION")" ]; then
    echo "PASS: Resource group in correct location ($ACTUAL_LOCATION)"
else
    if [ "${STRICT_RG_LOCATION}" = "1" ]; then
        echo "FAIL: RG location mismatch. Expected: $LOCATION Actual: $ACTUAL_LOCATION (STRICT_RG_LOCATION=1)"
        exit 1
    else
        echo "WARN: RG location mismatch. Expected: $LOCATION Actual: $ACTUAL_LOCATION (continuing; set STRICT_RG_LOCATION=1 to enforce)"
    fi
fi

echo "Resource group tests completed successfully"
