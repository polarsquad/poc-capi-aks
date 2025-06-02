#!/bin/bash
# Complete setup script for Azure AKS with ClusterAPI and FluxCD

set -e

echo "🚀 Azure AKS with ClusterAPI and FluxCD Setup"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_step() {
    echo -e "${BLUE}Step $1: $2${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
    fi
}

# Step 0: Prerequisites check
print_step "0" "Checking prerequisites"

REQUIRED_COMMANDS=("az" "kubectl" "helm" "kind" "clusterctl" "flux" "terraform" "git" "docker")

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    check_command $cmd
done

print_success "All required commands are available"

# Check Azure login
if ! az account show &> /dev/null; then
    print_error "Please login to Azure first: az login"
fi

print_success "Azure CLI is logged in"

# Check environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    print_error "GITHUB_TOKEN environment variable is required"
fi

if [ -z "$GITHUB_OWNER" ]; then
    print_warning "GITHUB_OWNER not set, using default: your-github-username"
    export GITHUB_OWNER="your-github-username"
fi

if [ -z "$GITHUB_REPO" ]; then
    print_warning "GITHUB_REPO not set, using default: poc-capi-aks"
    export GITHUB_REPO="poc-capi-aks"
fi

print_success "Environment variables configured"

# Step 1: Azure Infrastructure
print_step "1" "Setting up Azure infrastructure with Terraform"

cd terraform

if [ ! -f "terraform.tfvars" ]; then
    print_warning "terraform.tfvars not found, creating from example"
    cp terraform.tfvars.example terraform.tfvars
    print_warning "Please edit terraform/terraform.tfvars with your values and run this script again"
    exit 1
fi

terraform init
terraform plan
read -p "Apply Terraform configuration? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    terraform apply -auto-approve
    print_success "Azure infrastructure created"
else
    print_error "Terraform apply cancelled"
fi

cd ..

# Step 2: ClusterAPI Management Cluster
print_step "2" "Setting up ClusterAPI management cluster"

chmod +x cluster-api/management/bootstrap.sh
./cluster-api/management/bootstrap.sh

print_success "ClusterAPI management cluster ready"

# Step 3: Azure Credentials
print_step "3" "Setting up Azure credentials for ClusterAPI"

chmod +x cluster-api/management/setup-azure-credentials.sh
./cluster-api/management/setup-azure-credentials.sh

print_success "Azure credentials configured"

# Step 4: AKS Workload Cluster
print_step "4" "Creating AKS workload cluster"

cd cluster-api/workload
chmod +x deploy.sh
./deploy.sh
cd ../..

print_success "AKS workload cluster created"

# Step 5: FluxCD Setup
print_step "5" "Setting up FluxCD"

chmod +x flux-config/bootstrap-flux.sh
./flux-config/bootstrap-flux.sh

print_success "FluxCD configured"

# Step 6: Run Tests
print_step "6" "Running comprehensive tests"

chmod +x tests/*.sh
./tests/test-e2e-system.sh

if [ $? -eq 0 ]; then
    print_success "All tests passed!"
else
    print_warning "Some tests failed, check the output above"
fi

# Final summary
echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "Your Azure AKS cluster with ClusterAPI and FluxCD is ready!"
echo ""
echo "Next steps:"
echo "1. Clone your GitOps repository: git clone https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
echo "2. Add your applications to the apps/ directory"
echo "3. Commit and push changes - Flux will automatically deploy them"
echo ""
echo "Useful commands:"
echo "- Access workload cluster: export KUBECONFIG=cluster-api/workload/aks-workload-cluster.kubeconfig"
echo "- Check Flux status: flux get all"
echo "- Run tests: ./tests/test-e2e-system.sh"
echo ""
echo "Documentation: ./docs/README.md"
