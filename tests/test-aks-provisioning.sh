#!/bin/bash
# Test Script: test-aks-provisioning.sh
WORKLOAD_CLUSTER_NAME="${CLUSTER_NAME}"

# Derive Resource Group name from Terraform output if available
if command -v terraform >/dev/null 2>&1 && [ -f "terraform/terraform.tfstate" ]; then
    TF_RG_NAME=$(terraform -chdir=terraform output -raw resource_group_name 2>/dev/null || true)
fi

# Fallback: parse terraform.tfvars if not obtained above
if [ -z "$TF_RG_NAME" ] && [ -f "terraform/terraform.tfvars" ]; then
    TF_RG_NAME=$(grep -E '^resource_group_name\s*=' terraform/terraform.tfvars | head -n1 | awk -F'=' '{gsub(/"| /, "", $2); print $2}')
fi

# Final fallback: environment variable or naming convention
RG_NAME="${TF_RG_NAME:-${RESOURCE_GROUP_NAME}}"

echo "Using Resource Group name: $RG_NAME"

echo "Testing AKS Cluster Provisioning..."

# Test cluster provisioning status
CLUSTER_PHASE=$(kubectl get cluster $WORKLOAD_CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$CLUSTER_PHASE" = "Provisioned" ]; then
    echo "PASS: Cluster provisioned successfully"
else
    echo "INFO: Cluster phase: $CLUSTER_PHASE (waiting for Provisioned)"
    # Wait for cluster to be provisioned (timeout after 20 minutes)
    kubectl wait --for=condition=Ready cluster/$WORKLOAD_CLUSTER_NAME --timeout=1200s
    if [ $? -eq 0 ]; then
        echo "PASS: Cluster provisioned successfully"
    else
        echo "FAIL: Cluster not provisioned within timeout"
        exit 1
    fi
fi

# Test Azure AKS resource exists
az aks show --resource-group $RG_NAME --name $WORKLOAD_CLUSTER_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: AKS cluster exists in Azure"
else
    echo "FAIL: AKS cluster not found in Azure"
    exit 1
fi

# Get kubeconfig for the workload cluster
echo "Getting kubeconfig for workload cluster..."
clusterctl get kubeconfig $WORKLOAD_CLUSTER_NAME > ${WORKLOAD_CLUSTER_NAME}.kubeconfig

# Test cluster connectivity
kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get nodes 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Can connect to AKS cluster"
else
    echo "FAIL: Cannot connect to AKS cluster"
    exit 1
fi

echo "AKS provisioning tests completed successfully"
