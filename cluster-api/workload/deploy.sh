#!/bin/bash
# Generate and apply ClusterAPI workload cluster manifests

set -e

echo "Generating ClusterAPI workload cluster manifests..."

# Load Azure credentials
if [ -f "../management/azure-credentials.env" ]; then
    source ../management/azure-credentials.env
else
    echo "ERROR: Azure credentials not found. Please run setup-azure-credentials.sh first."
    exit 1
fi

# Get Azure AD admin group ID (optional, can be set manually)
AZURE_ADMIN_GROUP_ID=${AZURE_ADMIN_GROUP_ID:-""}

# Generate manifests with environment variable substitution
envsubst < cluster.yaml > cluster-generated.yaml

echo "Applying ClusterAPI manifests..."
kubectl apply -f cluster-generated.yaml

echo "Waiting for cluster to be ready..."
echo "This may take 15-20 minutes..."

# Monitor cluster creation
kubectl get cluster aks-workload-cluster -w &
WATCH_PID=$!

# Wait for cluster to be provisioned
kubectl wait --for=condition=Ready cluster/aks-workload-cluster --timeout=1200s

# Kill the watch process
kill $WATCH_PID 2>/dev/null || true

echo "Cluster provisioning completed!"

# Get kubeconfig
echo "Generating kubeconfig for workload cluster..."
clusterctl get kubeconfig aks-workload-cluster > aks-workload-cluster.kubeconfig

echo "Workload cluster is ready!"
echo "Use the following command to access the cluster:"
echo "export KUBECONFIG=\$(pwd)/aks-workload-cluster.kubeconfig"
