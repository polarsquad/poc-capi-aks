#!/bin/bash
# Test Script: test-disaster-recovery.sh
set -euo pipefail

WORKLOAD_CLUSTER_NAME="$CLUSTER_NAME"

# Derive Resource Group (reuse logic from other tests)
if command -v terraform >/dev/null 2>&1 && [ -f "terraform/terraform.tfstate" ]; then
    TF_RG_NAME=$(terraform -chdir=terraform output -raw resource_group_name 2>/dev/null || true)
fi
if [ -z "${TF_RG_NAME:-}" ] && [ -f "terraform/terraform.tfvars" ]; then
    TF_RG_NAME=$(grep -E '^resource_group_name\s*=' terraform/terraform.tfvars | head -n1 | awk -F'=' '{gsub(/"| /, "", $2); print $2}')
fi
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-${TF_RG_NAME}}

echo "Using RESOURCE_GROUP_NAME=$RESOURCE_GROUP_NAME"

echo "Testing disaster recovery scenario..."
echo "⚠️  WARNING: This will delete and recreate the cluster!"

# Confirmation prompt for safety
read -p "Are you sure you want to proceed with disaster recovery test? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Disaster recovery test cancelled"
    exit 0
fi

echo "Starting disaster recovery test..."

# Backup current cluster info
echo "Backing up cluster information..."
RG_ID_BEFORE=$(az group show --name "$RESOURCE_GROUP_NAME" --query id -o tsv 2>/dev/null || true)
if [ -n "$RG_ID_BEFORE" ]; then
    echo "Recorded existing Resource Group ID: $RG_ID_BEFORE"
else
    echo "WARN: Resource Group $RESOURCE_GROUP_NAME not found before test (will continue)."
fi
if kubectl get cluster $WORKLOAD_CLUSTER_NAME >/dev/null 2>&1; then
    kubectl get cluster $WORKLOAD_CLUSTER_NAME -o yaml > cluster-backup.yaml
else
    echo "WARN: Cluster $WORKLOAD_CLUSTER_NAME not found, skipping backup."
fi
kubectl get azureASOmanagedcluster $WORKLOAD_CLUSTER_NAME -o yaml > azuremanagedcluster-backup.yaml
kubectl delete cluster $WORKLOAD_CLUSTER_NAME --wait=true

# Delete cluster (in test environment only)
echo "Deleting cluster resources (Cluster only, RG should persist)..."
kubectl delete cluster $WORKLOAD_CLUSTER_NAME --wait=false

# Wait for deletion to start
echo "Waiting for cluster deletion to complete..."
sleep 30

# Monitor deletion
while kubectl get cluster $WORKLOAD_CLUSTER_NAME 2>/dev/null; do
    echo "Cluster still exists, waiting..."
    sleep 30
done

echo "Cluster deleted successfully"

# Wait additional time for Azure resources to clean up
echo "Waiting briefly for Cluster API finalizers to reconcile (not deleting RG)..."
sleep 120

# Recreate cluster from manifests
echo "Recreating cluster from manifests (ensuring RG reuse)..."
if [ ! -f cluster-api/workload/cluster-generated.yaml ]; then
    echo "Regenerating manifest via envsubst..."
    envsubst < cluster-api/workload/cluster.yaml > cluster-api/workload/cluster-generated.yaml
fi
kubectl apply -f cluster-api/workload/cluster-generated.yaml

# Verify RG still exists (reuse)
RG_ID_AFTER=$(az group show --name "$RESOURCE_GROUP_NAME" --query id -o tsv 2>/dev/null || true)
if [ -z "$RG_ID_AFTER" ]; then
    echo "FAIL: Resource Group $RESOURCE_GROUP_NAME was removed unexpectedly during disaster recovery"
    exit 1
fi
# If the resource group ID has changed, it means the original resource group was deleted and a new one was created,
    echo "FAIL: Resource Group was recreated (ID changed); expected reuse of the original resource group."
if [ -n "$RG_ID_BEFORE" ] && [ "$RG_ID_BEFORE" != "$RG_ID_AFTER" ]; then
    echo "FAIL: Resource Group was recreated (ID changed) expected reuse"
    exit 1
fi
echo "PASS: Resource Group reused successfully (Old ID: $RG_ID_BEFORE, New ID: $RG_ID_AFTER)"

# Wait for provisioning
echo "Waiting for cluster provisioning (this may take 15-20 minutes)..."
kubectl wait --for=condition=Ready cluster/$WORKLOAD_CLUSTER_NAME --timeout=1200s
KUBECTL_EXIT_CODE=$?
CLUSTER_WAIT_RC=${CLUSTER_WAIT_RC:-$KUBECTL_EXIT_CODE}

if [ ${CLUSTER_WAIT_RC:-$KUBECTL_EXIT_CODE} -eq 0 ]; then
    echo "✅ Cluster reprovisioned successfully"
else
    echo "❌ Cluster provisioning failed"
    exit 1
fi

# Get new kubeconfig
echo "Getting kubeconfig for restored cluster..."
clusterctl get kubeconfig $WORKLOAD_CLUSTER_NAME > ${WORKLOAD_CLUSTER_NAME}-restored.kubeconfig

# Verify cluster and applications are restored
echo "Verifying cluster functionality..."
./tests/test-aks-provisioning.sh || { echo "❌ test-aks-provisioning.sh failed"; exit 1; }
./tests/test-flux-installation.sh || { echo "❌ test-flux-installation.sh failed"; exit 1; }
./tests/test-sample-app.sh || { echo "❌ test-sample-app.sh failed"; exit 1; }

# Ownership / ASO resource validation
echo "Validating ASO ownership references..."
MANAGED_CLUSTER_NS=default
OWNER_RG_REF=$(kubectl get managedcluster.containerservice.azure.com "$WORKLOAD_CLUSTER_NAME" -n $MANAGED_CLUSTER_NS -o jsonpath='{.spec.owner.name}' 2>/dev/null || true)
if [ "$OWNER_RG_REF" != "$RESOURCE_GROUP_NAME" ]; then
    echo "FAIL: ManagedCluster owner name ($OWNER_RG_REF) does not match RESOURCE_GROUP_NAME ($RESOURCE_GROUP_NAME)"
    DR_FAIL=1
else
    echo "PASS: ManagedCluster owner matches expected resource group"
fi

for pool in pool0 pool1; do
    OWNER_REF=$(kubectl get managedclustersagentpool.containerservice.azure.com ${WORKLOAD_CLUSTER_NAME}-$pool -n $MANAGED_CLUSTER_NS -o jsonpath='{.spec.owner.name}' 2>/dev/null || true)
    if [ "$OWNER_REF" != "$RESOURCE_GROUP_NAME" ]; then
        echo "FAIL: AgentPool $pool owner ($OWNER_REF) != $RESOURCE_GROUP_NAME"
        DR_FAIL=1
    else
        echo "PASS: AgentPool $pool owner matches resource group"
    fi
done

if [ -z "${DR_FAIL:-}" ]; then
    echo "🎉 Disaster recovery successful!"
    echo "Cluster and applications restored successfully"
else
    echo "💥 Disaster recovery validation failed"
    exit 1
fi

# Cleanup backup files
for file in cluster-backup.yaml azuremanagedcluster-backup.yaml azuremanagedcontrolplane-backup.yaml; do
    if [ ! -f "$file" ]; then
        echo "WARN: Backup file $file not found during cleanup"
    fi
    rm -f "$file"
done

echo "Disaster recovery test completed successfully"
