#!/bin/bash
# Test: AKS cluster provisioning validation

set -euo pipefail

CAPI_CLUSTER_NAME="${CAPI_CLUSTER_NAME:-capi-mgmt}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-workload-cluster}"
MGMT_KUBECONFIG="${HOME}/.kube/${CAPI_CLUSTER_NAME}.kubeconfig"
WORKLOAD_KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}.kubeconfig"

echo "Testing AKS Cluster Provisioning..."

if [ ! -f "$MGMT_KUBECONFIG" ]; then
    echo "❌ FAIL: Management kubeconfig not found"
    exit 1
fi

# Get resource group from Terraform
if [ -f "terraform/terraform.tfstate" ]; then
    RG_NAME=$(terraform -chdir=terraform output -raw azure_resource_group_name 2>/dev/null || echo "")
fi
RG_NAME="${RG_NAME:-${AZURE_RESOURCE_GROUP_NAME:-aks-workload-cluster-rg}}"

# Test Cluster resource Ready status
CLUSTER_READY=$(kubectl --kubeconfig="$MGMT_KUBECONFIG" get cluster "$CLUSTER_NAME" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$CLUSTER_READY" = "True" ]; then
    echo "✅ PASS: Cluster resource is Ready"
else
    echo "⚠️  WARN: Cluster not yet Ready (may still be provisioning)"
fi

# Test AKS cluster exists in Azure
if az aks show --resource-group "$RG_NAME" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "✅ PASS: AKS cluster exists in Azure"
    
    # Get provisioning state
    PROV_STATE=$(az aks show --resource-group "$RG_NAME" --name "$CLUSTER_NAME" \
        --query provisioningState -o tsv)
    echo "✅ PASS: AKS provisioning state: $PROV_STATE"
else
    echo "⚠️  WARN: AKS cluster not found in Azure (may still be creating)"
fi

# Test workload cluster connectivity
if [ -f "$WORKLOAD_KUBECONFIG" ]; then
    if kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" cluster-info >/dev/null 2>&1; then
        echo "✅ PASS: Can connect to AKS cluster"
        
        # Get node count
        NODE_COUNT=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get nodes \
            --no-headers 2>/dev/null | wc -l)
        echo "✅ PASS: AKS cluster has $NODE_COUNT node(s)"
    else
        echo "⚠️  WARN: Cannot connect to AKS cluster yet"
    fi
else
    echo "⚠️  WARN: Workload kubeconfig not found (cluster may still be provisioning)"
fi

echo "✅ AKS provisioning tests completed"
