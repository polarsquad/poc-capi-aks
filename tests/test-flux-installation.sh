#!/bin/bash
# Test: Flux installation on both clusters

set -euo pipefail

CAPI_CLUSTER_NAME="${CAPI_CLUSTER_NAME:-capi-mgmt}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-workload-cluster}"
MGMT_KUBECONFIG="${HOME}/.kube/${CAPI_CLUSTER_NAME}.kubeconfig"
WORKLOAD_KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}.kubeconfig"

echo "Testing Flux Installation..."

# Test Flux on management cluster
echo "Checking Flux on management cluster..."
if [ ! -f "$MGMT_KUBECONFIG" ]; then
    echo "❌ FAIL: Management kubeconfig not found"
    exit 1
fi

if ! kubectl --kubeconfig="$MGMT_KUBECONFIG" get namespace flux-system >/dev/null 2>&1; then
    echo "❌ FAIL: Flux namespace not found on management cluster"
    exit 1
fi
echo "✅ PASS: Flux namespace exists on management cluster"

MGMT_FLUX_PODS=$(kubectl --kubeconfig="$MGMT_KUBECONFIG" get pods -n flux-system \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$MGMT_FLUX_PODS" -lt 4 ]; then
    echo "❌ FAIL: Insufficient Flux controllers on management cluster ($MGMT_FLUX_PODS pods)"
    exit 1
fi
echo "✅ PASS: Flux controllers running on management cluster ($MGMT_FLUX_PODS pods)"

# Test Flux on workload cluster
echo "Checking Flux on workload cluster..."
if [ ! -f "$WORKLOAD_KUBECONFIG" ]; then
    echo "⚠️  SKIP: Workload kubeconfig not found (cluster may not be provisioned yet)"
    exit 0
fi

if ! kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get namespace flux-system >/dev/null 2>&1; then
    echo "❌ FAIL: Flux namespace not found on workload cluster"
    exit 1
fi
echo "✅ PASS: Flux namespace exists on workload cluster"

WORKLOAD_FLUX_PODS=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get pods -n flux-system \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$WORKLOAD_FLUX_PODS" -lt 4 ]; then
    echo "❌ FAIL: Insufficient Flux controllers on workload cluster ($WORKLOAD_FLUX_PODS pods)"
    exit 1
fi
echo "✅ PASS: Flux controllers running on workload cluster ($WORKLOAD_FLUX_PODS pods)"

echo "✅ All Flux installation tests passed"
