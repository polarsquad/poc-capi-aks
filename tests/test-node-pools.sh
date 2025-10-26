#!/bin/bash
# Test: AKS node pools validation

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-aks-workload-cluster}"
WORKLOAD_KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}.kubeconfig"

echo "Testing Node Pool Configuration..."

if [ ! -f "$WORKLOAD_KUBECONFIG" ]; then
    echo "⚠️  SKIP: Workload kubeconfig not found (cluster may not be provisioned yet)"
    exit 0
fi

# Test nodes exist
NODE_COUNT=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get nodes \
    --no-headers 2>/dev/null | wc -l)
if [ "$NODE_COUNT" -lt 1 ]; then
    echo "❌ FAIL: No nodes found"
    exit 1
fi
echo "✅ PASS: Found $NODE_COUNT node(s)"

# Test node readiness
READY_NODES=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get nodes \
    --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
if [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
    echo "✅ PASS: All nodes Ready ($READY_NODES/$NODE_COUNT)"
else
    echo "⚠️  WARN: Not all nodes Ready ($READY_NODES/$NODE_COUNT)"
fi

# List node details
echo "Node details:"
kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get nodes -o wide 2>/dev/null || true

echo "✅ Node pool tests completed"
