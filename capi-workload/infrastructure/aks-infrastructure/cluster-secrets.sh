#!/bin/bash
# Setup Azure credentials for ClusterAPI

set -e

echo "Setting up Azure credentials for ClusterAPI..."

# Validate required variables
if [ -z "$CLUSTER_NAME" ] || [ -z "$KUBERNETES_VERSION" ] || [ -z "$WORKER_MACHINE_COUNT" ] || [ -z "$AZURE_NODE_MACHINE_TYPE" ] || [ -z "$AZURE_LOCATION" ] || [ -z "$AZURE_RESOURCE_GROUP_NAME" ]; then
    echo "ERROR: Missing required Azure credentials from environment variables"
    exit 1
fi

# Create Azure cluster secrets
echo "Creating Azure cluster secrets..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
 name: azure-cluster-secrets
 namespace: default
stringData:
 CLUSTER_NAME: "$CLUSTER_NAME"
 KUBERNETES_VERSION: "$KUBERNETES_VERSION"
 WORKER_MACHINE_COUNT: "$WORKER_MACHINE_COUNT"
 AZURE_NODE_MACHINE_TYPE: "$AZURE_NODE_MACHINE_TYPE"
 AZURE_LOCATION: "$AZURE_LOCATION"
 AZURE_RESOURCE_GROUP_NAME: "$AZURE_RESOURCE_GROUP_NAME"
EOF

echo "Azure credentials setup completed successfully!"
