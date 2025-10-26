#!/bin/bash
# Test: Cluster manifest validation

set -euo pipefail

CAPI_CLUSTER_NAME="${CAPI_CLUSTER_NAME:-capi-mgmt}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-workload-cluster}"
MGMT_KUBECONFIG="${HOME}/.kube/${CAPI_CLUSTER_NAME}.kubeconfig"

echo "Testing ClusterAPI manifests..."

if [ ! -f "$MGMT_KUBECONFIG" ]; then
    echo "❌ FAIL: Management kubeconfig not found"
    exit 1
fi

# Test Cluster resource exists
if ! kubectl --kubeconfig="$MGMT_KUBECONFIG" get cluster "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "❌ FAIL: Cluster resource '$CLUSTER_NAME' not found"
    exit 1
fi
echo "✅ PASS: Cluster resource exists"

# Test Cluster status
CLUSTER_READY=$(kubectl --kubeconfig="$MGMT_KUBECONFIG" get cluster "$CLUSTER_NAME" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$CLUSTER_READY" = "True" ]; then
    echo "✅ PASS: Cluster is Ready"
else
    echo "⚠️  WARN: Cluster not yet Ready (status: $CLUSTER_READY)"
fi

# Test AzureASOManagedCluster exists
AZURE_CLUSTER=$(kubectl --kubeconfig="$MGMT_KUBECONFIG" get azureasomanagedcluster \
    -o name 2>/dev/null | head -n 1)
if [ -n "$AZURE_CLUSTER" ]; then
    echo "✅ PASS: AzureASOManagedCluster resource exists"
else
    echo "❌ FAIL: AzureASOManagedCluster resource not found"
    exit 1
fi

# Test MachinePools exist
MACHINE_POOLS=$(kubectl --kubeconfig="$MGMT_KUBECONFIG" get machinepool \
    --no-headers 2>/dev/null | wc -l)
if [ "$MACHINE_POOLS" -gt 0 ]; then
    echo "✅ PASS: MachinePools exist ($MACHINE_POOLS pools)"
else
    echo "⚠️  WARN: No MachinePools found"
fi

echo "✅ All cluster manifest tests passed"
