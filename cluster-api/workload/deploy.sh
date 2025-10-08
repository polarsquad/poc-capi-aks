#!/bin/bash
# Generate and apply ClusterAPI workload cluster manifests

set -e

echo "Generating ClusterAPI workload cluster manifests..."

# Load Azure credentials
if [ -f "../../azure-credentials.env" ]; then
    source ../../azure-credentials.env
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
echo "This may take 10-15 minutes..."

# Monitor cluster creation
kubectl get cluster ${CLUSTER_NAME} -w &
WATCH_PID=$!
# Ensure the background watch process is terminated when the script exits
trap '[ -n "$WATCH_PID" ] && kill -0 $WATCH_PID 2>/dev/null && kill $WATCH_PID 2>/dev/null || true' EXIT

# Wait for cluster to be provisioned
kubectl wait --for='jsonpath={.status.conditions[?(@.type=="Available")].status}=True' cluster/${CLUSTER_NAME} --timeout=900s

# Kill the watch process
if kill -0 $WATCH_PID 2>/dev/null; then
    kill $WATCH_PID 2>/dev/null || true
fi

echo "Cluster provisioning completed!"

# Get kubeconfig
echo "Generating kubeconfig for workload cluster..."
clusterctl get kubeconfig ${CLUSTER_NAME} > ../../${CLUSTER_NAME}.kubeconfig

echo "Workload cluster is ready!"
echo "Use the following command to access the cluster:"
echo "export KUBECONFIG=\$(pwd)/${CLUSTER_NAME}.kubeconfig"
