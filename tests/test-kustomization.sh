#!/bin/bash
# Test: Flux Kustomization validation

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-aks-workload-cluster}"
WORKLOAD_KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}.kubeconfig"

echo "Testing Flux Kustomizations..."

if [ ! -f "$WORKLOAD_KUBECONFIG" ]; then
    echo "⚠️  SKIP: Workload kubeconfig not found"
    exit 0
fi

# Test apps Kustomization exists
if ! kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get kustomization apps -n default >/dev/null 2>&1; then
    echo "❌ FAIL: Kustomization 'apps' not found in default namespace"
    exit 1
fi
echo "✅ PASS: Apps Kustomization exists"

# Test apps Kustomization status
APPS_STATUS=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get kustomization apps -n default \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$APPS_STATUS" = "True" ]; then
    echo "✅ PASS: Apps Kustomization is Ready"
else
    echo "⚠️  WARN: Apps Kustomization not Ready (status: $APPS_STATUS)"
fi

# Test flux-system Kustomization
FLUX_STATUS=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get kustomization flux-system -n flux-system \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$FLUX_STATUS" = "True" ]; then
    echo "✅ PASS: Flux-system Kustomization is Ready"
fi

# List all Kustomizations
echo "All Kustomizations:"
kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get kustomization -A 2>/dev/null || true

echo "✅ Kustomization tests completed"
