#!/bin/bash
# Test Script: test-git-connection.sh
WORKLOAD_CLUSTER_NAME="${CLUSTER_NAME}"
REPO_NAME="flux-system"

echo "Testing Git Repository Connection..."

# Test GitRepository resource exists
kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get gitrepository $REPO_NAME -n flux-system 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: GitRepository resource exists"
else
    echo "FAIL: GitRepository resource not found"
    exit 1
fi

# Test repository sync status
SYNC_STATUS=$(kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get gitrepository $REPO_NAME -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$SYNC_STATUS" = "True" ]; then
    echo "PASS: Git repository synced successfully"
else
    echo "FAIL: Git repository sync failed (Status: $SYNC_STATUS)"
    exit 1
fi

echo "Git connection tests completed successfully"
