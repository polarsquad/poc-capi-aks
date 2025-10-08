#!/bin/bash
# Generate and apply ClusterAPI workload cluster manifests

set -euo pipefail

# Derive RESOURCE_GROUP_NAME if absent (prefers Terraform outputs)
if [ -z "${RESOURCE_GROUP_NAME:-}" ]; then
    if command -v terraform >/dev/null 2>&1 && [ -f "../../terraform/terraform.tfstate" ]; then
        DERIVED_RG=$(terraform -chdir=../../terraform output -raw resource_group_name 2>/dev/null || true)
        if [ -n "$DERIVED_RG" ]; then
            export RESOURCE_GROUP_NAME="$DERIVED_RG"
        fi
    fi
fi

if [ -z "${RESOURCE_GROUP_NAME:-}" ]; then
    echo "ERROR: RESOURCE_GROUP_NAME not set and not derivable (run terraform apply or export manually)." >&2
    exit 1
fi

echo "Using RESOURCE_GROUP_NAME=$RESOURCE_GROUP_NAME"

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

# Guard against legacy pattern lingering
if grep -q '\${CLUSTER_NAME}-rg' cluster-generated.yaml; then
    echo "ERROR: Deprecated pattern \\${CLUSTER_NAME}-rg detected in generated manifest." >&2
    exit 1
fi

echo "Applying ClusterAPI manifests..."
kubectl apply -f cluster-generated.yaml

echo "Waiting for cluster to be ready (Cluster Available condition)..."
echo "This may take several minutes..."

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
