#!/bin/bash
# Comprehensive cleanup for GitOps AKS environment (ClusterAPI + Flux + Terraform Controller)

set -euo pipefail

echo "🧹 Cleanup GitOps AKS Environment"
echo "================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
ok() { echo -e "${GREEN}✅ $1${NC}"; }
err() { echo -e "${RED}❌ $1${NC}"; }

warn "This will delete ALL Kubernetes (kind) + Flux + Terraform Controller + Azure resources managed by this project."
warn "Action is irreversible."
echo ""
read -p "Type 'yes' to confirm cleanup: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled"; exit 0; fi

CLUSTER_NAME=${CLUSTER_NAME:-aks-workload-cluster}
CAPI_CLUSTER_NAME=${CAPI_CLUSTER_NAME:-capi-mgmt}
TF_NS=flux-system
TF_NAME=aks-infra

echo "Step 1: Suspend Flux reconciliation to reduce churn..."
if command -v flux &>/dev/null; then
    flux -n flux-system suspend kustomization apps || true
    flux -n flux-system suspend kustomization workload-cluster || true
    flux -n flux-system suspend kustomization infrastructure || true
    ok "Flux Kustomizations suspended (where present)."
else
    warn "Flux CLI not found; skipping suspension."
fi

echo "Step 2: Delete workload cluster (Cluster resource + related ASO managed objects)..."
if kubectl get cluster "$CLUSTER_NAME" >/dev/null 2>&1; then
    kubectl delete cluster "$CLUSTER_NAME" --wait=true --timeout=600s || warn "Cluster delete timeout; continuing"
    ok "Workload Cluster resource deletion initiated."
else
    warn "Cluster $CLUSTER_NAME not found."
fi

echo "Step 3: Delete Terraform Controller custom resource (to prevent further applies)..."
if kubectl get terraform "$TF_NAME" -n "$TF_NS" >/dev/null 2>&1; then
    kubectl delete terraform "$TF_NAME" -n "$TF_NS" --timeout=300s || warn "Terraform CR deletion timeout"
    ok "Terraform CR deleted."
else
    warn "Terraform CR $TF_NAME not found."
fi

echo "Step 4: Delete Terraform Controller HelmRelease (and underlying deployment)..."
if kubectl get helmrelease -n "$TF_NS" terraform-controller >/dev/null 2>&1; then
    kubectl delete helmrelease -n "$TF_NS" terraform-controller --timeout=300s || warn "HelmRelease deletion timeout"
    ok "Terraform Controller HelmRelease deletion requested."
else
    warn "HelmRelease terraform-controller not present."
fi

echo "Step 5: Delete Flux system objects (GitRepository + Kustomizations + components namespace)..."
if kubectl get namespace flux-system >/dev/null 2>&1; then
    # Delete higher-level Kustomizations to clean owned resources
    for k in apps workload-cluster infrastructure flux-system; do
        kubectl delete kustomization "$k" -n flux-system --ignore-not-found=true || true
    done
    # Delete GitRepository
    kubectl delete gitrepository flux-system -n flux-system --ignore-not-found=true || true
    # Delete controllers namespace last
    kubectl delete namespace flux-system --timeout=180s || warn "Namespace flux-system deletion timeout"
    ok "Flux system resources deletion requested."
else
    warn "Namespace flux-system already absent."
fi

echo "Step 6: Delete Azure identity secrets (cluster identity + workload cluster secrets)..."
kubectl delete secret azure-cluster-identity -n default --ignore-not-found=true || true
kubectl delete secret azure-cluster-identity-secret -n default --ignore-not-found=true || true
kubectl delete secret azure-cluster-secrets -n default --ignore-not-found=true || true
ok "Credential and workload secrets cleaned up."

echo "Step 7: Remove management kind cluster..."
if kind get clusters | grep -q "^${CAPI_CLUSTER_NAME}$"; then
    kind delete cluster --name "$CAPI_CLUSTER_NAME" || warn "Kind cluster delete encountered issues"
    ok "Management kind cluster deleted."
else
    warn "Management cluster $CAPI_CLUSTER_NAME not found."
fi

echo "Step 8: Local file cleanup..."
rm -f cluster-api/workload/${CLUSTER_NAME}.kubeconfig || true
rm -f cluster-api/workload/rendered-cluster.yaml || true
rm -f ${CLUSTER_NAME}.kubeconfig || true
rm -f cluster-api/management/azure-credentials.env || true
rm -f flux-config/clusters/flux-system/gotk-components.yaml 2>/dev/null || true
rm -f flux-config/clusters/flux-system/gotk-sync.yaml 2>/dev/null || true
ok "Local generated files removed."

echo "Step 9: (Optional) Terraform local state destroy if still present..."
if [ -f terraform/terraform.tfstate ]; then
    (cd terraform && terraform destroy -auto-approve || warn "Terraform destroy encountered issues")
    ok "Terraform state destroyed."
else
    warn "No terraform state file found."
fi

echo "Step 10: Final verification summary"
echo "  Remaining kind clusters:" $(kind get clusters 2>/dev/null || echo none)
echo "  Remaining flux-system namespace:" $(kubectl get ns flux-system 2>/dev/null || echo absent)
echo "  Remaining cluster resource:" $(kubectl get cluster ${CLUSTER_NAME} 2>/dev/null || echo absent)

ok "Cleanup process completed."
echo "You may now remove the repository directory or delete remote Git repository if desired."
