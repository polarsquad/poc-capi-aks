#!/bin/bash
# Test: ClusterAPI Management Cluster validation

set -euo pipefail

CAPI_CLUSTER_NAME="${CAPI_CLUSTER_NAME:-capi-mgmt}"
MGMT_KUBECONFIG="${HOME}/.kube/${CAPI_CLUSTER_NAME}.kubeconfig"

echo "Testing ClusterAPI Management Cluster..."

# Test kind cluster exists
if ! kind get clusters | grep -q "^${CAPI_CLUSTER_NAME}$"; then
    echo "❌ FAIL: Kind cluster '${CAPI_CLUSTER_NAME}' not found"
    exit 1
fi
echo "✅ PASS: Kind cluster exists"

# Test kubeconfig file exists
if [ ! -f "$MGMT_KUBECONFIG" ]; then
    echo "❌ FAIL: Kubeconfig not found at $MGMT_KUBECONFIG"
    exit 1
fi
echo "✅ PASS: Kubeconfig file exists"

# Test cluster is accessible
if ! kubectl --kubeconfig="$MGMT_KUBECONFIG" cluster-info >/dev/null 2>&1; then
    echo "❌ FAIL: Management cluster not accessible"
    exit 1
fi
echo "✅ PASS: Management cluster accessible"

# Test ClusterAPI CRDs installed
if ! kubectl --kubeconfig="$MGMT_KUBECONFIG" get crd clusters.cluster.x-k8s.io >/dev/null 2>&1; then
    echo "❌ FAIL: ClusterAPI CRDs not installed"
    exit 1
fi
echo "✅ PASS: ClusterAPI CRDs installed"

# Test CAPI controllers running
CAPI_PODS=$(kubectl --kubeconfig="$MGMT_KUBECONFIG" get pods -n capi-system \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$CAPI_PODS" -lt 1 ]; then
    echo "❌ FAIL: CAPI controller not running"
    exit 1
fi
echo "✅ PASS: CAPI controllers running ($CAPI_PODS pods)"

# Test CAPZ controllers running
CAPZ_PODS=$(kubectl --kubeconfig="$MGMT_KUBECONFIG" get pods -n capz-system \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$CAPZ_PODS" -lt 1 ]; then
    echo "❌ FAIL: CAPZ controller not running"
    exit 1
fi
echo "✅ PASS: CAPZ controllers running ($CAPZ_PODS pods)"

echo "✅ All management cluster tests passed"
