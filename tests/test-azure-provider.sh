#!/bin/bash
# Test: Azure ClusterAPI Provider (CAPZ) validation

set -euo pipefail

CAPI_CLUSTER_NAME="${CAPI_CLUSTER_NAME:-capi-mgmt}"
MGMT_KUBECONFIG="${HOME}/.kube/${CAPI_CLUSTER_NAME}.kubeconfig"

echo "Testing Azure ClusterAPI Provider..."

if [ ! -f "$MGMT_KUBECONFIG" ]; then
    echo "❌ FAIL: Management kubeconfig not found"
    exit 1
fi

# Test CAPZ namespace exists
if ! kubectl --kubeconfig="$MGMT_KUBECONFIG" get namespace capz-system >/dev/null 2>&1; then
    echo "❌ FAIL: CAPZ namespace not found"
    exit 1
fi
echo "✅ PASS: CAPZ namespace exists"

# Test CAPZ controller pods running
CAPZ_PODS=$(kubectl --kubeconfig="$MGMT_KUBECONFIG" get pods -n capz-system \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$CAPZ_PODS" -lt 1 ]; then
    echo "❌ FAIL: CAPZ controller not running"
    exit 1
fi
echo "✅ PASS: CAPZ controller running ($CAPZ_PODS pods)"

# Test Azure cluster identity secret exists
if ! kubectl --kubeconfig="$MGMT_KUBECONFIG" get secret azure-cluster-identity -n default >/dev/null 2>&1; then
    echo "❌ FAIL: Azure cluster identity secret not found"
    exit 1
fi
echo "✅ PASS: Azure cluster identity secret exists"

# Test ASO CRDs installed
if kubectl --kubeconfig="$MGMT_KUBECONFIG" get crd azureasomanagedclusters.infrastructure.cluster.x-k8s.io >/dev/null 2>&1; then
    echo "✅ PASS: Azure ASO CRDs installed"
fi

echo "✅ All Azure provider tests passed"
