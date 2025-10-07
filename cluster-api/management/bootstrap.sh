#!/bin/bash
# Management Cluster Bootstrap Script

set -e

echo "Setting up ClusterAPI Management Cluster..."

# Check prerequisites
echo "Checking prerequisites..."
for cmd in kind kubectl clusterctl; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: $cmd is not installed"
        exit 1
    fi
done

# Create kind cluster for management
echo "Creating kind management cluster with increased resources..."
cat <<EOF | kind create cluster --name ${CAPI_CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        system-reserved: memory=8Gi
        eviction-hard: memory.available<500Mi
        eviction-soft: memory.available<1Gi
        eviction-soft-grace-period: memory.available=1m30s
EOF

# Set context
kubectl config use-context kind-${CAPI_CLUSTER_NAME}

# Initialize ClusterAPI
echo "Initializing ClusterAPI..."
echo "Note: You may see 'unrecognized format' warnings - these are harmless OpenAPI validation messages"
clusterctl init --infrastructure azure 2>&1 | grep -v "unrecognized format"

# Wait for ClusterAPI to be ready
echo "Waiting for ClusterAPI components to be ready..."
kubectl wait --for=condition=Available --timeout=300s -n capi-system deployment/capi-controller-manager 2>&1 | grep -v "unrecognized format"
kubectl wait --for=condition=Available --timeout=300s -n capz-system deployment/capz-controller-manager 2>&1 | grep -v "unrecognized format"

echo "ClusterAPI management cluster setup completed successfully!"
echo "Cluster context: kind-${CAPI_CLUSTER_NAME}"
