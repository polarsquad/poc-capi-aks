#!/bin/bash
# Test: Disaster recovery validation (DESTRUCTIVE)

set -euo pipefail

CAPI_CLUSTER_NAME="${CAPI_CLUSTER_NAME:-capi-mgmt}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-workload-cluster}"
MGMT_KUBECONFIG="${HOME}/.kube/${CAPI_CLUSTER_NAME}.kubeconfig"

echo "⚠️  WARNING: Disaster Recovery Test (DESTRUCTIVE)"
echo "This test will delete and recreate the workload cluster!"
echo ""
read -p "Type 'yes' to proceed: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Test cancelled"
    exit 0
fi

echo "Testing Disaster Recovery..."

if [ ! -f "$MGMT_KUBECONFIG" ]; then
    echo "❌ FAIL: Management kubeconfig not found"
    exit 1
fi

# Backup cluster configuration
echo "Backing up cluster configuration..."
kubectl --kubeconfig="$MGMT_KUBECONFIG" get cluster "$CLUSTER_NAME" -o yaml > /tmp/cluster-backup.yaml 2>/dev/null || true

# Delete cluster
echo "Deleting cluster..."
if kubectl --kubeconfig="$MGMT_KUBECONFIG" delete cluster "$CLUSTER_NAME" --wait=false 2>/dev/null; then
    echo "✅ Cluster deletion initiated"
else
    echo "❌ FAIL: Could not delete cluster"
    exit 1
fi

# Wait for cluster to be deleted
echo "Waiting for cluster deletion (max 10 minutes)..."
for i in {1..60}; do
    if ! kubectl --kubeconfig="$MGMT_KUBECONFIG" get cluster "$CLUSTER_NAME" >/dev/null 2>&1; then
        echo "✅ Cluster deleted"
        break
    fi
    sleep 10
    if [ $i -eq 60 ]; then
        echo "⚠️  WARN: Cluster deletion timeout"
    fi
done

# Recreate cluster using Flux reconciliation
echo "Recreating cluster via Flux reconciliation..."
if command -v flux >/dev/null 2>&1; then
    flux --kubeconfig="$MGMT_KUBECONFIG" reconcile kustomization aks-infrastructure -n default 2>/dev/null || true
fi

# Wait for cluster to be recreated
echo "Waiting for cluster recreation (max 20 minutes)..."
if kubectl --kubeconfig="$MGMT_KUBECONFIG" wait --for=condition=Ready cluster/"$CLUSTER_NAME" --timeout=1200s 2>/dev/null; then
    echo "✅ Cluster recreated successfully"
else
    echo "⚠️  WARN: Cluster recreation timeout or failed"
fi

# Verify cluster is functional
if kubectl --kubeconfig="$MGMT_KUBECONFIG" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
    echo "✅ PASS: Cluster is Ready after recovery"
else
    echo "❌ FAIL: Cluster not Ready after recovery"
    exit 1
fi

echo "✅ Disaster recovery test completed"
echo "⚠️  Note: Full application recovery may take additional time for Flux to reconcile"
