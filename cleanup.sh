#!/bin/bash
# Cleanup script to remove all resources

set -e

echo "🧹 Cleanup Azure AKS with ClusterAPI and FluxCD"
echo "==============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning "This will delete ALL resources created by this project!"
print_warning "This action cannot be undone!"
echo ""

read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo "Starting cleanup..."

# 1. Delete AKS workload cluster
echo "1. Deleting AKS workload cluster..."
if kubectl get cluster ${CLUSTER_NAME} 2>/dev/null; then
    kubectl delete cluster ${CLUSTER_NAME} --wait=true --timeout=600s
    print_success "AKS workload cluster deleted"
else
    print_warning "AKS workload cluster not found"
fi

# 2. Delete ClusterAPI management cluster
echo "2. Deleting ClusterAPI management cluster..."
if kind get clusters | grep -q ${CAPI_CLUSTER_NAME}; then
    kind delete cluster --name ${CAPI_CLUSTER_NAME}
    print_success "Management cluster deleted"
else
    print_warning "Management cluster not found"
fi

# 3. Destroy Azure infrastructure
echo "3. Destroying Azure infrastructure..."
cd terraform
if [ -f "terraform.tfstate" ]; then
    terraform destroy -auto-approve
    print_success "Azure infrastructure destroyed"
else
    print_warning "No Terraform state found"
fi
cd ..

# 4. Clean up local files
echo "4. Cleaning up local files..."
rm -f cluster-api/workload/${CLUSTER_NAME}.kubeconfig
rm -f cluster-api/workload/cluster-generated.yaml
rm -f cluster-api/workload/${CLUSTER_NAME}-restored.kubeconfig
rm -f cluster-api/management/azure-credentials.env
rm -f tests/cluster-backup.yaml
rm -f tests/azuremanagedcluster-backup.yaml
rm -f tests/azuremanagedcontrolplane-backup.yaml
rm -f ${CLUSTER_NAME}.kubeconfig

print_success "Local files cleaned up"

echo ""
print_success "Cleanup completed successfully!"
echo ""
echo "All resources have been removed. You can now:"
echo "1. Delete this project directory if no longer needed"
echo "2. Manually delete the GitHub repository if created"
echo "3. Check your Azure subscription to ensure all resources are removed"
