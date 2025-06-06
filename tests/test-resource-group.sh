#!/bin/bash
# Test Script: test-resource-group.sh
RG_NAME="${CLUSTER_NAME}-rg"
LOCATION="eastus"

echo "Testing Azure Resource Group..."

# Test if resource group exists
az group show --name $RG_NAME --query "name" -o tsv 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Resource group $RG_NAME exists"
else
    echo "FAIL: Resource group $RG_NAME does not exist"
    exit 1
fi

# Test location
ACTUAL_LOCATION=$(az group show --name $RG_NAME --query "location" -o tsv)
if [ "$ACTUAL_LOCATION" = "$LOCATION" ]; then
    echo "PASS: Resource group in correct location"
else
    echo "FAIL: Resource group in wrong location"
    exit 1
fi

echo "Resource group tests completed successfully"
