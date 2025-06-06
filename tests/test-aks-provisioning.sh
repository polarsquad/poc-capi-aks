#!/bin/bash
# Test Script: test-aks-provisioning.sh
WORKLOAD_CLUSTER_NAME="${CLUSTER_NAME}"
RG_NAME="${CLUSTER_NAME}-rg"

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
