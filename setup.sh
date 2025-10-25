#!/bin/bash
# GitOps Setup Script: Terraform + kind ClusterAPI Management + Flux + Workload Cluster
#
# Target Flow:
#  1. Use Terraform CLI to create Azure service principal and resource group.
#  2. Create kind ClusterAPI management cluster.
#  3. Install Flux (manifests under capi-workload/flux-system) and reconcile management GitOps tree.
#  4. Create azure-cluster-identity secret from Terraform outputs.
#  5. Ensure aks-infrastructure (Kustomization in ./capi-workload/infrastructure/aks-infrastructure) reconciles.
#  6. Wait until workload cluster (Cluster resource) becomes Ready.
#  7. Install Flux on workload cluster (manifests under aks-workload/flux-system) and bootstrap its GitOps source.
#  8. Wait for apps Kustomization in workload cluster (aks-workload/apps) to become Ready.

set -euo pipefail

echo "🚀 GitOps AKS Setup (Terraform + ClusterAPI + Flux)"
echo "===================================================="

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

REQUIRED_COMMANDS=("az" "kubectl" "helm" "kind" "clusterctl" "flux" "git" "docker" "terraform")

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
if [ -z "${GITHUB_TOKEN:-}" ]; then
    print_warning "GITHUB_TOKEN not set (only needed for private repo or bootstrap generation); proceeding"
fi

if [ -z "${GITHUB_OWNER:-}" ]; then
    print_warning "GITHUB_OWNER not set, using default: your-github-username"
    export GITHUB_OWNER="your-github-username"
fi

if [ -z "${GITHUB_REPO:-}" ]; then
    print_warning "GITHUB_REPO not set, using default: poc-capi-aks"
    export GITHUB_REPO="poc-capi-aks"
fi

if [ -z "${CAPI_CLUSTER_NAME:-}" ]; then
    print_warning "CAPI_CLUSTER_NAME not set; using default: capi-mgmt"
    export CAPI_CLUSTER_NAME=capi-mgmt
fi

print_success "Environment variables configured"

#############################################
# Step 1: Run Terraform to create Azure resources
#############################################
print_step "1" "Create Azure service principal and resource group using Terraform"

# Get current Azure subscription and tenant from az CLI
echo "[setup] Retrieving Azure subscription and tenant from current az login..."
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export ARM_TENANT_ID=$(az account show --query tenantId -o tsv)

print_success "Using Azure subscription: ${ARM_SUBSCRIPTION_ID}"
print_success "Using Azure tenant: ${ARM_TENANT_ID}"

cd terraform
terraform init

# Run terraform apply with environment variables from current az login
echo "[setup] Running terraform apply with current environment variables..."
terraform apply -auto-approve \
    -var="arm_subscription_id=${ARM_SUBSCRIPTION_ID}" \
    -var="arm_tenant_id=${ARM_TENANT_ID}"

# Capture Terraform outputs
export ARM_SUBSCRIPTION_ID=$(terraform output -raw arm_subscription_id)
export AZURE_TENANT_ID=$(terraform output -raw arm_tenant_id)
export AZURE_CLIENT_ID=$(terraform output -raw service_principal_client_id)
export AZURE_CLIENT_SECRET=$(terraform output -raw service_principal_client_secret)
export AZURE_LOCATION=$(terraform output -raw azure_resource_group_location 2>/dev/null || echo "swedencentral")
export AZURE_RESOURCE_GROUP_NAME=$(terraform output -raw azure_resource_group_name 2>/dev/null || echo "aks-workload-cluster-rg")
export AZURE_SERVICE_PRINCIPAL_NAME=$(terraform output -raw azure_service_principal_name)

cd ..

print_success "Azure resources created via Terraform"
echo "  - Subscription: ${ARM_SUBSCRIPTION_ID}"
echo "  - Tenant: ${AZURE_TENANT_ID}"
echo "  - Service Principal: ${AZURE_SERVICE_PRINCIPAL_NAME}"
echo "  - Resource Group: ${AZURE_RESOURCE_GROUP_NAME} (${AZURE_LOCATION})"


# Step 2: ClusterAPI Management Cluster (includes Flux + Terraform Controller bootstrap)
print_step "2" "Create kind management cluster and initialize ClusterAPI"

echo "[setup] Creating kind cluster '${CAPI_CLUSTER_NAME}' (if absent)..."
if ! kind get clusters | grep -q "^${CAPI_CLUSTER_NAME}$"; then
cat <<EOF | kind create cluster --name "${CAPI_CLUSTER_NAME}" --config=-
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
else
    echo "[setup] Reusing existing kind cluster '${CAPI_CLUSTER_NAME}'."
fi

kubectl config use-context "kind-${CAPI_CLUSTER_NAME}" >/dev/null

echo "[setup] Initializing ClusterAPI (core + azure provider)..."
clusterctl init --infrastructure azure 2>&1 | grep -v "unrecognized format" || true

echo "[setup] Waiting for ClusterAPI controllers..."
kubectl wait --for=condition=Available --timeout=300s -n capi-system deployment/capi-controller-manager 2>&1 | grep -v "unrecognized format"
kubectl wait --for=condition=Available --timeout=300s -n capz-system deployment/capz-controller-manager 2>&1 | grep -v "unrecognized format"

print_success "ClusterAPI management cluster ready"

print_step "3" "Install Flux controllers on management cluster (manifests path capi-workload/flux-system)"

FLUX_COMPONENTS_DIR="capi-workload/flux-system"
GOTK_COMPONENTS_FILE="${FLUX_COMPONENTS_DIR}/gotk-components.yaml"
GOTK_SYNC_FILE="${FLUX_COMPONENTS_DIR}/gotk-sync.yaml"
mkdir -p "$FLUX_COMPONENTS_DIR"
if [ ! -f "$GOTK_COMPONENTS_FILE" ] || [ ! -f "$GOTK_SYNC_FILE" ]; then
    echo "[setup] Generating Flux manifests via 'flux install --export'..."
    flux install --export > "$GOTK_COMPONENTS_FILE"
    cat > "$GOTK_SYNC_FILE" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
    name: flux-system
    namespace: flux-system
spec:
    interval: 1m0s
        url: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}
    ref:
        branch: ${GITHUB_BRANCH:-main}
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
    name: flux-system
    namespace: flux-system
spec:
    interval: 10m0s
    path: ./capi-workload
    prune: true
    sourceRef:
        kind: GitRepository
        name: flux-system
    wait: true
EOF
fi

echo "[setup] Applying Flux system manifests..."
kubectl apply -f "$GOTK_COMPONENTS_FILE"
kubectl apply -f "$GOTK_SYNC_FILE"

echo "[setup] Waiting for Flux controllers to become Available..."
kubectl -n flux-system wait --for=condition=Available --timeout=240s deployment/source-controller || true
kubectl -n flux-system wait --for=condition=Available --timeout=240s deployment/kustomize-controller || true
kubectl -n flux-system wait --for=condition=Available --timeout=240s deployment/helm-controller || true
kubectl -n flux-system wait --for=condition=Available --timeout=240s deployment/notification-controller || true

print_step "3a" "Wait for GitRepository flux-system Ready before creating secrets"
for i in {1..30}; do
    GIT_READY=$(kubectl get gitrepository -n flux-system flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [ "$GIT_READY" = "True" ]; then
        print_success "GitRepository flux-system Ready"
        break
    fi
    sleep 6
    if [ $i -eq 30 ]; then
        print_warning "GitRepository flux-system not Ready within timeout; proceeding anyway"
    fi
done

# Step 4: Azure Credentials from Terraform outputs
print_step "4" "Create Azure identity secret from Terraform outputs"

echo "[setup] Creating azure-cluster-identity secret from Terraform outputs..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
    name: azure-cluster-identity
    namespace: flux-system
stringData:
    subscriptionID: "${ARM_SUBSCRIPTION_ID}"
    tenantID: "${AZURE_TENANT_ID}"
    clientID: "${AZURE_CLIENT_ID}"
    clientSecret: "${AZURE_CLIENT_SECRET}"
    location: "${AZURE_LOCATION}"
    resourceGroupName: "${AZURE_RESOURCE_GROUP_NAME}"
    servicePrincipalName: "${AZURE_SERVICE_PRINCIPAL_NAME}"
EOF

print_success "Azure identity secrets configured from Terraform outputs"

print_step "5" "Wait for aks-infrastructure Kustomization reconciliation"
echo "[setup] Waiting for Kustomization 'aks-infrastructure' to become Ready..."
for i in {1..40}; do
    KUST_READY=$(kubectl get kustomization aks-infrastructure -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$KUST_READY" = "True" ]; then
        print_success "aks-infrastructure Kustomization Ready"
        break
    fi
    if (( i % 5 == 0 )); then
        echo "[wait] aks-infrastructure Ready condition still pending (attempt $i)"
    fi
    sleep 6
    if [ $i -eq 40 ]; then
        print_warning "aks-infrastructure Kustomization not Ready within timeout; continuing"
    fi
done

print_step "6" "Wait for Cluster resource readiness (workload cluster creation)"
export CLUSTER_NAME=${CLUSTER_NAME:-aks-workload-cluster}
kubectl wait --for=condition=Ready --timeout=600s cluster/${CLUSTER_NAME} 2>/dev/null || print_warning "Cluster Ready condition timeout"

print_step "7" "Install Flux on workload cluster (aks-workload/flux-system)"
echo "[setup] Fetching workload cluster kubeconfig..."
WORKLOAD_KUBECONFIG="cluster-api/workload/${CLUSTER_NAME}.kubeconfig"
if [ ! -f "$WORKLOAD_KUBECONFIG" ]; then
    clusterctl get kubeconfig ${CLUSTER_NAME} > "$WORKLOAD_KUBECONFIG" 2>/dev/null || print_warning "Unable to retrieve kubeconfig via clusterctl; ensure ClusterAPI has finished reconciling."
fi

if [ -f "$WORKLOAD_KUBECONFIG" ]; then
    export KUBECONFIG="$WORKLOAD_KUBECONFIG"
    print_success "Switched KUBECONFIG to workload cluster"
else
    print_warning "Workload kubeconfig file missing, attempting to continue using management context"
fi

WL_FLUX_DIR="aks-workload/flux-system"
WL_GOTK_COMPONENTS="$WL_FLUX_DIR/gotk-components.yaml"
WL_GOTK_SYNC="$WL_FLUX_DIR/gotk-sync.yaml"
mkdir -p "$WL_FLUX_DIR"
if [ ! -f "$WL_GOTK_COMPONENTS" ] || [ ! -f "$WL_GOTK_SYNC" ]; then
    echo "[setup] Generating workload cluster Flux manifests..."
    flux install --export > "$WL_GOTK_COMPONENTS"
    cat > "$WL_GOTK_SYNC" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m0s
  url: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}
  ref:
    branch: ${GITHUB_BRANCH:-main}
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./aks-workload
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: true
EOF
fi

echo "[setup] Applying workload Flux system manifests..."
kubectl apply -f "$WL_GOTK_COMPONENTS" || print_error "Failed applying workload gotk-components"
kubectl apply -f "$WL_GOTK_SYNC" || print_error "Failed applying workload gotk-sync"

echo "[setup] Waiting for workload Flux controllers to become Available..."
kubectl -n flux-system wait --for=condition=Available --timeout=240s deployment/source-controller || print_warning "source-controller not Available in workload cluster"
kubectl -n flux-system wait --for=condition=Available --timeout=240s deployment/kustomize-controller || print_warning "kustomize-controller not Available in workload cluster"
kubectl -n flux-system wait --for=condition=Available --timeout=240s deployment/helm-controller || print_warning "helm-controller not Available in workload cluster"
kubectl -n flux-system wait --for=condition=Available --timeout=240s deployment/notification-controller || print_warning "notification-controller not Available in workload cluster"

echo "[setup] Waiting for workload GitRepository flux-system Ready..."
for i in {1..30}; do
    WG_STATUS=$(kubectl get gitrepository -n flux-system flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [ "$WG_STATUS" = "True" ]; then
        print_success "Workload GitRepository Ready"
        break
    fi
    sleep 6
    if [ $i -eq 30 ]; then
        print_warning "Workload GitRepository not Ready within timeout"
    fi
done

#############################################
# Step 8: Wait for apps reconciliation in workload cluster
#############################################
print_step "8" "Wait for apps Kustomization in workload cluster"
for i in {1..40}; do
    W_APP_STATUS=$(flux -n flux-system get kustomizations apps 2>/dev/null | awk 'NR==2{print $2}')
    if [ "$W_APP_STATUS" = "Ready" ]; then
        print_success "Workload apps Kustomization Ready"
        break
    fi
    if [ $i -eq 40 ]; then
        print_warning "Workload apps Kustomization not Ready within timeout"
        break
    fi
    if (( i % 5 == 0 )); then
        echo "[wait] apps Kustomization Ready condition still pending (attempt $i)"
    fi
    sleep 10
done

# Switch back to management cluster kubeconfig for tests referencing controllers there (optional)
export KUBECONFIG="${HOME}/.kube/config"
kubectl config use-context "kind-${CAPI_CLUSTER_NAME}" >/dev/null 2>&1 || true

echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "Your GitOps-driven AKS cluster (ClusterAPI + Flux) is ready!"
echo ""
echo "Next steps:"
echo "1. Clone your GitOps repository: git clone https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
echo "2. Review management GitOps tree: ./capi-workload (flux-system, infrastructure/aks-infrastructure)"
echo "3. Review workload GitOps tree: ./aks-workload (flux-system, apps)"
echo "4. Add/modify application manifests under aks-workload/apps/sample-apps"
echo "5. Commit and push changes - both Flux instances will reconcile"
echo "6. View workload cluster Kustomization status: flux -n flux-system get kustomizations"
echo "7. Switch to workload cluster: export KUBECONFIG=cluster-api/workload/aks-workload-cluster.kubeconfig"
echo "8. Inspect workload apps: flux get all"
echo ""
echo "Useful commands:"
echo "- Access workload cluster: export KUBECONFIG=cluster-api/workload/aks-workload-cluster.kubeconfig"
echo "- Check Flux status: flux get all"
echo "- View aks-infrastructure Kustomization: flux -n flux-system get kustomizations aks-infrastructure"
echo "- View Cluster resource: kubectl get cluster ${CLUSTER_NAME}"
echo "- Destroy infrastructure: cd terraform && terraform destroy"
echo ""
echo "Documentation: ./README.md and ./docs/GETTING_STARTED.md"
