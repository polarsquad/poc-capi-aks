#!/bin/bash
# Complete end-to-end setup script for Azure AKS via ClusterAPI + Flux GitOps + Terraform Controller
#
# Flow:
#  1. Terraform creates Azure infra (RG, SP, etc.) locally.
#  2. ClusterAPI management cluster bootstraps (includes Flux + Terraform Controller).
#  3. Azure credentials secret injected for CAPZ / Terraform.
#  4. Terraform Controller runs in cluster producing outputs secret.
#  5. Workload AKS cluster manifests applied (consuming Terraform outputs via scripts today).
#  6. Tests run.

set -euo pipefail

echo "🚀 Azure AKS GitOps Setup (ClusterAPI + Flux + Terraform Controller)"
echo "===================================================================="

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

if [ -z "${CAPI_CLUSTER_NAME:-}" ]; then
    print_warning "CAPI_CLUSTER_NAME not set; using default: capi-mgmt"
    export CAPI_CLUSTER_NAME=capi-mgmt
fi

export BOOTSTRAP_MODE=${BOOTSTRAP_MODE:-auto}
print_success "Environment variables configured (BOOTSTRAP_MODE=${BOOTSTRAP_MODE})"

# Step 1: Azure Infrastructure
print_step "1" "Setting up Azure infrastructure with Terraform (local apply before GitOps)"

cd terraform

if [ ! -f "terraform.tfvars" ]; then
    print_warning "terraform.tfvars not found, creating from example"
    cp terraform.tfvars.example terraform.tfvars
    print_warning "Please edit terraform/terraform.tfvars with your values and run this script again"
    exit 1
fi

terraform init -input=false
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

# Step 2: ClusterAPI Management Cluster (includes Flux + Terraform Controller bootstrap)
print_step "2" "Bootstrapping ClusterAPI management cluster (includes Flux + Terraform Controller)"

chmod +x cluster-api/management/bootstrap.sh
./cluster-api/management/bootstrap.sh

print_success "ClusterAPI management cluster ready (Flux controllers installing)"

# Step 3: Azure Credentials
print_step "3" "Setting up Azure credentials (Secrets for CAPZ + Terraform Controller)"

chmod +x cluster-api/management/setup-azure-credentials.sh
./cluster-api/management/setup-azure-credentials.sh

print_success "Azure credentials configured"

print_step "4" "Waiting for Terraform Controller readiness and outputs"

TF_NS=flux-system
TF_NAME=aks-infra
MAX_DEPLOY_WAIT=60
DEPLOY_SLEEP=5

echo "Checking terraform-controller deployment availability..."
DEPLOY_ATTEMPTS=0
until kubectl -n $TF_NS get deployment terraform-controller &>/dev/null; do
    DEPLOY_ATTEMPTS=$((DEPLOY_ATTEMPTS+1))
    if [ $DEPLOY_ATTEMPTS -ge $MAX_DEPLOY_WAIT ]; then
        print_warning "terraform-controller deployment not detected; continuing (will rely on local Terraform outputs)"
        break
    fi
    sleep $DEPLOY_SLEEP
done

if kubectl -n $TF_NS get deployment terraform-controller &>/dev/null; then
    kubectl -n $TF_NS wait --for=condition=Available --timeout=300s deployment/terraform-controller || print_warning "terraform-controller not Available within timeout"
fi

echo "Waiting for Terraform CR '$TF_NAME' to exist..."
CR_ATTEMPTS=0
while [ $CR_ATTEMPTS -lt 30 ]; do
    if kubectl get terraform $TF_NAME -n $TF_NS &>/dev/null; then
        break
    fi
    CR_ATTEMPTS=$((CR_ATTEMPTS+1))
    sleep 5
done
if ! kubectl get terraform $TF_NAME -n $TF_NS &>/dev/null; then
    print_warning "Terraform CR $TF_NAME not found; proceeding without in-cluster Terraform apply"
else
    echo "Waiting for Terraform CR Ready condition..."
    READY_ATTEMPTS=0
    until [ $READY_ATTEMPTS -ge 30 ]; do
        READY_STATUS=$(kubectl get terraform $TF_NAME -n $TF_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        if [ "$READY_STATUS" = "True" ]; then
            print_success "Terraform CR Ready"
            break
        fi
        READY_ATTEMPTS=$((READY_ATTEMPTS+1))
        sleep 10
    done
    if [ "$READY_STATUS" != "True" ]; then
        print_warning "Terraform CR not Ready in allotted time; workload cluster will still be attempted"
    fi
fi

echo "Checking for terraform-outputs secret..."
OUTPUT_ATTEMPTS=0
while [ $OUTPUT_ATTEMPTS -lt 40 ]; do
    if kubectl get secret terraform-outputs -n $TF_NS &>/dev/null; then
        print_success "terraform-outputs secret present"
        break
    fi
    OUTPUT_ATTEMPTS=$((OUTPUT_ATTEMPTS+1))
    sleep 5
done
if ! kubectl get secret terraform-outputs -n $TF_NS &>/dev/null; then
    print_warning "terraform-outputs secret not found; using local Terraform state for workload provisioning"
else
    RG_NAME=$(kubectl get secret terraform-outputs -n $TF_NS -o jsonpath='{.data.resource_group_name}' 2>/dev/null | base64 -d || echo "")
    if [ -n "$RG_NAME" ]; then
        echo "Terraform output resource_group_name: $RG_NAME"
    else
        print_warning "resource_group_name key missing in terraform-outputs secret"
    fi
fi

# Step 5: AKS Workload Cluster (after Terraform readiness checks)
print_step "5" "Creating AKS workload cluster"

cd cluster-api/workload
chmod +x deploy.sh
./deploy.sh
cd ../..

print_success "AKS workload cluster created"

# FluxCD bootstrap now occurs during management cluster bootstrap (Step 2)

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
echo "Your Azure AKS cluster with ClusterAPI, Flux GitOps, and Terraform Controller is ready!"
echo ""
echo "Next steps:"
echo "1. Clone your GitOps repository: git clone https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
echo "2. Add application manifests under flux-config/apps/ (or new directories)"
echo "3. Commit and push changes - Flux will automatically reconcile"
echo "4. Inspect Terraform CR: kubectl -n flux-system get terraform"
echo "5. View Terraform outputs: kubectl -n flux-system get secret terraform-outputs -o yaml"
echo ""
echo "Useful commands:"
echo "- Access workload cluster: export KUBECONFIG=cluster-api/workload/aks-workload-cluster.kubeconfig"
echo "- Check Flux status: flux get all"
echo "- Check Terraform Controller: kubectl -n flux-system get pods | grep terraform-controller"
echo "- View infrastructure Kustomization status: flux -n flux-system get kustomizations infrastructure"
echo "- Run tests: ./tests/test-e2e-system.sh"
echo ""
echo "Documentation: ./README.md and ./docs/GETTING_STARTED.md"
