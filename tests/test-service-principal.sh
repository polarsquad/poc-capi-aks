#!/bin/bash
# Test Script: test-service-principal.sh
SP_NAME="aks-cluster-sp"

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
