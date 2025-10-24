#!/bin/bash
# GitOps Setup Script: kind ClusterAPI Management + Flux + Terraform Controller + Workload Cluster
#
# Target Flow (updated):
#  1. Create kind ClusterAPI management cluster.
#  2. Install Flux (manifests under capi-workload/flux-system) and reconcile management GitOps tree.
#  3. Infrastructure: Terraform Controller installed by Kustomization 'terraform'.
#  4. Terraform Controller applies capi-workload/infrastructure/terraform-controller -> wait for Terraform CR Ready & terraform-outputs secret.
#  5. Ensure aks-infrastructure (currently Kustomization name 'apps' pointing to ./capi-workload/infrastructure/aks-infrastructure) reconciles.
#  6. Wait until workload cluster (Cluster resource) becomes Ready (Kustomization name 'workload-cluster' expected via repo manifests).
#  7. Install Flux on workload cluster (manifests under aks-workload/flux-system) and bootstrap its GitOps source.
#  8. Wait for apps Kustomization in workload cluster (aks-workload/apps) to become Ready.

set -euo pipefail

echo "🚀 GitOps AKS Setup (ClusterAPI + Flux + Terraform Controller)"
echo "============================================================="

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

REQUIRED_COMMANDS=("az" "kubectl" "helm" "kind" "clusterctl" "flux" "git" "docker")

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
    print_warning "GITHUB_TOKEN not set (only needed for private repo or bootstrap generation); proceeding"
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

print_success "Environment variables configured"

# Load Azure credentials env file if present
if [ -f azure-credentials.env ]; then
    # shellcheck disable=SC1091
    source azure-credentials.env
    export ARM_SUBSCRIPTION_ID=${ARM_SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID:-}}
    if [ -z "${ARM_SUBSCRIPTION_ID:-}" ] && [ -n "${AZURE_SUBSCRIPTION_ID:-}" ]; then
        ARM_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
    fi
    print_success "Loaded azure-credentials.env"
fi


# Step 2: ClusterAPI Management Cluster (includes Flux + Terraform Controller bootstrap)
print_step "1" "Create kind management cluster and initialize ClusterAPI"

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

print_step "2" "Install Flux controllers on management cluster (manifests path capi-workload/flux-system)"

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

print_step "2a" "Wait for GitRepository flux-system Ready before watching infrastructure Kustomizations"
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

# Step 3: Azure Credentials
print_step "3" "Create Azure identity secrets (for CAPZ + Terraform Controller)"

# Validate required Azure env vars
REQUIRED_AZ_VARS=(AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET ARM_SUBSCRIPTION_ID AZURE_LOCATION AZURE_RESOURCE_GROUP_NAME AZURE_SERVICE_PRINCIPAL_NAME)
MISSING=()
for v in "${REQUIRED_AZ_VARS[@]}"; do
    if [ -z "${!v:-}" ]; then MISSING+=("$v"); fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
    print_error "Missing required Azure environment variables: ${MISSING[*]}"
fi

echo "[setup] Creating/Updating azure-cluster-identity secret..."
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

print_success "Azure identity secrets configured"

print_step "4" "Wait for Terraform Controller Kustomization ('terraform') and Terraform CR readiness"
echo "[setup] Waiting for Kustomization 'terraform' to become Ready..."
for i in {1..40}; do
    # Use kubectl to get Ready condition directly; suppress errors until resource exists
    T_READY=$(kubectl -n flux-system get kustomization terraform -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ "$T_READY" = "True" ]; then
        print_success "terraform Kustomization Ready"
        break
    fi
    # Optional status output every few attempts
    if (( i % 5 == 0 )); then
        echo "[wait] terraform Ready condition still pending (attempt $i)"
    fi
    sleep 6
    if [ $i -eq 40 ]; then
        print_warning "terraform Kustomization not Ready within timeout; proceeding"
    fi
done

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

# Step 5: Ensure aks-infrastructure (Kustomization name 'apps' in management repo) reconciles
print_step "5" "Wait for aks-infrastructure Kustomization (name 'apps') reconciliation"
echo "[setup] Waiting for Kustomization 'apps' (aks-infrastructure) to become Ready..."
for i in {1..40}; do
    AI_STATUS=$(flux -n flux-system get kustomizations apps 2>/dev/null | awk 'NR==2{print $2}')
    if [ "$AI_STATUS" = "Ready" ]; then
        print_success "aks-infrastructure (apps) Kustomization Ready"
        break
    fi
    sleep 6
    if [ $i -eq 40 ]; then
        print_warning "aks-infrastructure Kustomization not Ready within timeout; continuing"
    fi
done

# Step 6: Generate workload cluster secret (after infra readiness)
print_step "6" "Generate workload cluster secret (cluster-secrets.sh) after Terraform outputs"

cd cluster-api/workload
chmod +x cluster-secrets.sh
export CLUSTER_NAME=${CLUSTER_NAME:-aks-workload-cluster}
export KUBERNETES_VERSION=${KUBERNETES_VERSION:-v1.33.2}
export WORKER_MACHINE_COUNT=${WORKER_MACHINE_COUNT:-2}
export AZURE_NODE_MACHINE_TYPE=${AZURE_NODE_MACHINE_TYPE:-Standard_DS3_v2}
export AZURE_LOCATION=$(kubectl get secret terraform-outputs -n $TF_NS -o jsonpath='{.data.location}' 2>/dev/null | base64 -d || echo swedencentral)
export AZURE_RESOURCE_GROUP_NAME=$(kubectl get secret terraform-outputs -n $TF_NS -o jsonpath='{.data.resource_group_name}' 2>/dev/null | base64 -d || echo aks-workload-cluster-rg)
./cluster-secrets.sh
cd ../..

print_success "Workload cluster secret generated for Flux reconciliation"

print_step "7" "Wait for workload-cluster Kustomization to apply cluster.yaml (management cluster)"
for i in {1..40}; do
    STATUS=$(flux -n flux-system get kustomizations workload-cluster 2>/dev/null | awk 'NR==2{print $2}')
    if [ "$STATUS" = "Ready" ]; then
        print_success "workload-cluster Kustomization Ready"
        break
    fi
    sleep 10
    if [ $i -eq 40 ]; then
        print_warning "workload-cluster Kustomization not Ready within timeout"
    fi
done

print_step "8" "Wait for Cluster resource readiness (workload cluster creation)"
kubectl wait --for=condition=Ready --timeout=600s cluster/${CLUSTER_NAME} 2>/dev/null || print_warning "Cluster Ready condition timeout"

#############################################
# Step 7: Install Flux on workload cluster
#############################################
print_step "9" "Install Flux on workload cluster (aks-workload/flux-system)"
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
  path: ./aks-workload/apps
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
print_step "10" "Wait for apps Kustomization in workload cluster"
for i in {1..40}; do
    W_APP_STATUS=$(flux -n flux-system get kustomizations apps 2>/dev/null | awk 'NR==2{print $2}')
    if [ "$W_APP_STATUS" = "Ready" ]; then
        print_success "Workload apps Kustomization Ready"
        break
    fi
    sleep 10
    if [ $i -eq 40 ]; then
        print_warning "Workload apps Kustomization not Ready within timeout"
    fi
done

# Switch back to management cluster kubeconfig for tests referencing controllers there (optional)
export KUBECONFIG="${HOME}/.kube/config"
kubectl config use-context "kind-${CAPI_CLUSTER_NAME}" >/dev/null 2>&1 || true

print_step "11" "Run tests (system + terraform + sample app)"

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
echo "Your GitOps-driven AKS cluster (ClusterAPI + Flux + Terraform Controller) is ready!"
echo ""
echo "Next steps:"
echo "1. Clone your GitOps repository: git clone https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
echo "2. Review management GitOps tree: ./capi-workload (flux-system, infrastructure, terraform-controller, aks-infrastructure)"
echo "3. Review workload GitOps tree: ./aks-workload (flux-system, apps)"
echo "4. Add/modify application manifests under aks-workload/apps/sample-apps (or create new directories under aks-workload/apps)"
echo "5. Commit and push changes - both Flux instances will reconcile respectively"
echo "6. Inspect Terraform CR: kubectl -n flux-system get terraform (management context)"
echo "7. View Terraform outputs: kubectl -n flux-system get secret terraform-outputs -o yaml"
echo "8. View workload cluster Kustomization status: flux -n flux-system get kustomizations workload-cluster (management context until Flux installed in workload)"
echo "9. After switching KUBECONFIG to workload cluster: flux get all (to inspect workload apps reconciliation)"
echo ""
echo "Useful commands:"
echo "- Access workload cluster: export KUBECONFIG=cluster-api/workload/aks-workload-cluster.kubeconfig"
echo "- Check Flux status: flux get all"
echo "- Check Terraform Controller: kubectl -n flux-system get pods | grep terraform-controller"
echo "- View terraform Kustomization status: flux -n flux-system get kustomizations terraform"
echo "- View aks-infrastructure Kustomization status: flux -n flux-system get kustomizations apps"
echo "- Run tests: ./tests/test-e2e-system.sh"
echo ""
echo "Documentation: ./README.md and ./docs/GETTING_STARTED.md"
