#!/bin/bash
# Management Cluster Bootstrap Script

set -e

echo "Setting up ClusterAPI Management Cluster..."

# Variables
CLUSTER_NAME="capi-management"
CAPI_VERSION="v1.6.1"
CAPZ_VERSION="v1.13.2"

# Check prerequisites
echo "Checking prerequisites..."
for cmd in kind kubectl clusterctl; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: $cmd is not installed"
        exit 1
    fi
done

# Create kind cluster for management
echo "Creating kind management cluster..."
cat <<EOF | kind create cluster --name ${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
EOF

# Set context
kubectl config use-context kind-${CLUSTER_NAME}

# Initialize ClusterAPI
echo "Initializing ClusterAPI..."
clusterctl init --infrastructure azure

# Wait for ClusterAPI to be ready
echo "Waiting for ClusterAPI components to be ready..."
kubectl wait --for=condition=Available --timeout=300s -n capi-system deployment/capi-controller-manager
kubectl wait --for=condition=Available --timeout=300s -n capz-system deployment/capz-controller-manager

echo "ClusterAPI management cluster setup completed successfully!"
echo "Cluster context: kind-${CLUSTER_NAME}"
