#!/bin/bash
# Setup Azure credentials for ClusterAPI

set -e

echo "Setting up Azure credentials for ClusterAPI..."

# Check if Terraform outputs are available
if [ ! -f "../terraform/terraform.tfstate" ]; then
    echo "ERROR: Terraform state not found. Please run terraform apply first."
    exit 1
fi

# Extract values from Terraform outputs
AZURE_SUBSCRIPTION_ID=$(cd ../terraform && terraform output -raw subscription_id)
AZURE_TENANT_ID=$(cd ../terraform && terraform output -raw tenant_id)
AZURE_CLIENT_ID=$(cd ../terraform && terraform output -raw service_principal_client_id)
AZURE_CLIENT_SECRET=$(cd ../terraform && terraform output -raw service_principal_client_secret)

# Validate required variables
if [ -z "$AZURE_SUBSCRIPTION_ID" ] || [ -z "$AZURE_TENANT_ID" ] || [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ]; then
    echo "ERROR: Missing required Azure credentials from Terraform outputs"
    exit 1
fi

# Create Azure identity secret
echo "Creating Azure identity secret..."
kubectl create secret generic azure-cluster-identity-secret \
    --from-literal=clientSecret=${AZURE_CLIENT_SECRET} \
    --namespace=default

# Create Azure cluster identity
echo "Creating Azure cluster identity..."
cat <<EOF | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: AzureClusterIdentity
metadata:
  name: cluster-identity
  namespace: default
spec:
  type: ServicePrincipal
  tenantID: ${AZURE_TENANT_ID}
  clientID: ${AZURE_CLIENT_ID}
  clientSecret:
    name: azure-cluster-identity-secret
    namespace: default
  allowedNamespaces:
    list:
    - default
EOF

echo "Azure credentials setup completed successfully!"

# Save environment variables for later use
cat <<EOF > azure-credentials.env
export AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
export AZURE_TENANT_ID=${AZURE_TENANT_ID}
export AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
export AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
export AZURE_CLUSTER_IDENTITY_SECRET_NAME="azure-cluster-identity-secret"
export AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE="default"
EOF

echo "Azure credentials saved to azure-credentials.env"
