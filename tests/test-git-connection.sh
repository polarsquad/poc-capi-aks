#!/bin/bash
# Test: Git repository connection validation

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-aks-workload-cluster}"
WORKLOAD_KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}.kubeconfig"

echo "Testing Git Repository Connection..."

if [ ! -f "$WORKLOAD_KUBECONFIG" ]; then
    echo "⚠️  SKIP: Workload kubeconfig not found"
    exit 0
fi

# Test GitRepository resource exists
if ! kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get gitrepository flux-system -n flux-system >/dev/null 2>&1; then
    echo "❌ FAIL: GitRepository 'flux-system' not found"
    exit 1
fi
echo "✅ PASS: GitRepository resource exists"

# Test Git sync status
SYNC_STATUS=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get gitrepository flux-system -n flux-system \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$SYNC_STATUS" = "True" ]; then
    echo "✅ PASS: Git repository synced successfully"
else
    echo "⚠️  WARN: Git repository not Ready (status: $SYNC_STATUS)"
fi

# Show repository URL
REPO_URL=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get gitrepository flux-system -n flux-system \
    -o jsonpath='{.spec.url}' 2>/dev/null || echo "")
if [ -n "$REPO_URL" ]; then
    echo "✅ PASS: Repository URL: $REPO_URL"
fi

echo "✅ Git connection tests completed"
