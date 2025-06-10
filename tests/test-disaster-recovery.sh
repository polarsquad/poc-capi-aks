#!/bin/bash
# Test Script: test-disaster-recovery.sh
WORKLOAD_CLUSTER_NAME="${CLUSTER_NAME}"

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
kubectl get cluster $WORKLOAD_CLUSTER_NAME -o yaml > cluster-backup.yaml
kubectl get azuremanagedcluster $WORKLOAD_CLUSTER_NAME -o yaml > azuremanagedcluster-backup.yaml
kubectl get azuremanagedcontrolplane $WORKLOAD_CLUSTER_NAME -o yaml > azuremanagedcontrolplane-backup.yaml

# Delete cluster (in test environment only)
echo "Deleting cluster resources..."
kubectl delete cluster $WORKLOAD_CLUSTER_NAME --wait=false

# Wait for deletion to start
echo "Waiting for cluster deletion to complete..."
sleep 60

# Monitor deletion
while kubectl get cluster $WORKLOAD_CLUSTER_NAME 2>/dev/null; do
    echo "Cluster still exists, waiting..."
    sleep 30
done

echo "Cluster deleted successfully"

# Wait additional time for Azure resources to clean up
echo "Waiting for Azure resources to clean up..."
sleep 300

# Recreate cluster from manifests
echo "Recreating cluster from manifests..."
kubectl apply -f ../cluster-api/workload/cluster-generated.yaml

# Wait for provisioning
echo "Waiting for cluster provisioning (this may take 15-20 minutes)..."
kubectl wait --for=condition=Ready cluster/$WORKLOAD_CLUSTER_NAME --timeout=1200s

if [ $? -eq 0 ]; then
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
./test-aks-provisioning.sh && \
./test-flux-installation.sh && \
./test-sample-app.sh

if [ $? -eq 0 ]; then
    echo "🎉 Disaster recovery successful!"
    echo "Cluster and applications restored successfully"
else
    echo "💥 Disaster recovery validation failed"
    exit 1
fi

# Cleanup backup files
rm -f cluster-backup.yaml azuremanagedcluster-backup.yaml azuremanagedcontrolplane-backup.yaml

echo "Disaster recovery test completed successfully"
