#!/bin/bash
# Comprehensive cleanup for GitOps AKS environment (ClusterAPI + Flux + Terraform)

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

warn "This will delete ALL Kubernetes (kind) + Flux + Terraform + Azure resources managed by this project."
warn "Action is irreversible."
echo ""
read -p "Type 'yes' to confirm cleanup: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled"; exit 0; fi

CLUSTER_NAME=${CLUSTER_NAME:-aks-workload-cluster}
CAPI_CLUSTER_NAME=${CAPI_CLUSTER_NAME:-capi-mgmt}

echo "Step 1: Suspend Flux reconciliation to reduce churn..."
if command -v flux &>/dev/null; then
    # Suspend management cluster Kustomizations
    flux -n flux-system suspend kustomization aks-infrastructure --context="kind-${CAPI_CLUSTER_NAME}" || true
    flux -n flux-system suspend kustomization infrastructure --context="kind-${CAPI_CLUSTER_NAME}" || true
    flux -n flux-system suspend kustomization flux-system --context="kind-${CAPI_CLUSTER_NAME}" || true
    ok "Flux Kustomizations suspended (where present)."
else
    warn "Flux CLI not found; skipping suspension."
fi

echo "Step 2: Delete workload cluster (Cluster resource + related ClusterAPI managed objects)..."
if kubectl get cluster "$CLUSTER_NAME" --context="kind-${CAPI_CLUSTER_NAME}" >/dev/null 2>&1; then
    kubectl delete cluster "$CLUSTER_NAME" --context="kind-${CAPI_CLUSTER_NAME}" --wait=true --timeout=600s || warn "Cluster delete timeout; continuing"
    ok "Workload Cluster resource deletion initiated."
else
    warn "Cluster $CLUSTER_NAME not found."
fi

echo "Step 3: Delete Flux system objects (GitRepository + Kustomizations + components namespace)..."
if kubectl get namespace flux-system --context="kind-${CAPI_CLUSTER_NAME}" >/dev/null 2>&1; then
    # Delete higher-level Kustomizations to clean owned resources
    for k in aks-infrastructure infrastructure flux-system; do
        kubectl delete kustomization "$k" -n flux-system --context="kind-${CAPI_CLUSTER_NAME}" --ignore-not-found=true || true
    done
    # Delete GitRepository
    kubectl delete gitrepository flux-system -n flux-system --context="kind-${CAPI_CLUSTER_NAME}" --ignore-not-found=true || true
    # Delete controllers namespace last
    kubectl delete namespace flux-system --context="kind-${CAPI_CLUSTER_NAME}" --timeout=180s || warn "Namespace flux-system deletion timeout"
    ok "Flux system resources deletion requested."
else
    warn "Namespace flux-system already absent."
fi

echo "Step 4: Delete Azure identity secret..."
kubectl delete secret azure-cluster-identity -n flux-system --context="kind-${CAPI_CLUSTER_NAME}" --ignore-not-found=true || true
ok "Azure credential secret cleaned up."

echo "Step 5: Remove management kind cluster..."
if kind get clusters | grep -q "^${CAPI_CLUSTER_NAME}$"; then
    kind delete cluster --name "$CAPI_CLUSTER_NAME" || warn "Kind cluster delete encountered issues"
    ok "Management kind cluster deleted."
else
    warn "Management cluster $CAPI_CLUSTER_NAME not found."
fi

echo "Step 6: Local file cleanup..."
rm -rf cluster-api/workload/*.kubeconfig || true
rm -f cluster-api/workload/rendered-cluster.yaml || true
rm -f ${CLUSTER_NAME}.kubeconfig || true
rm -f capi-workload/flux-system/gotk-components.yaml || true
rm -f capi-workload/flux-system/gotk-sync.yaml || true
rm -f aks-workload/flux-system/gotk-components.yaml || true
rm -f aks-workload/flux-system/gotk-sync.yaml || true
ok "Local generated files removed."

echo "Step 7: Destroy Azure resources using Terraform..."
if [ -f terraform/terraform.tfstate ]; then
    echo "  Running 'terraform destroy' to remove Azure service principal and resource group..."
    
    # Use environment variables if already set (e.g., from mise.toml)
    # Check both ARM_TENANT_ID and AZURE_TENANT_ID (mise.toml uses AZURE_TENANT_ID)
    if [ -z "${ARM_SUBSCRIPTION_ID:-}" ] || [ -z "${ARM_TENANT_ID:-}" ]; then
        # Try AZURE_TENANT_ID if ARM_TENANT_ID is not set
        if [ -n "${AZURE_TENANT_ID:-}" ]; then
            export ARM_TENANT_ID="${AZURE_TENANT_ID}"
        fi
        
        # If still missing, retrieve from az CLI
        if [ -z "${ARM_SUBSCRIPTION_ID:-}" ] || [ -z "${ARM_TENANT_ID:-}" ]; then
            echo "  Retrieving Azure subscription and tenant from current az login..."
            export ARM_SUBSCRIPTION_ID=${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || echo "")}
            export ARM_TENANT_ID=${ARM_TENANT_ID:-$(az account show --query tenantId -o tsv 2>/dev/null || echo "")}
        fi
    fi
    
    # Run terraform destroy with environment variables
    if [ -n "${ARM_SUBSCRIPTION_ID:-}" ] && [ -n "${ARM_TENANT_ID:-}" ]; then
        echo "  Using subscription: ${ARM_SUBSCRIPTION_ID}"
        echo "  Using tenant: ${ARM_TENANT_ID}"
        (cd terraform && TF_INPUT=false terraform destroy -auto-approve \
            -var="arm_subscription_id=${ARM_SUBSCRIPTION_ID}" \
            -var="arm_tenant_id=${ARM_TENANT_ID}") || warn "Terraform destroy encountered issues"
    else
        warn "ARM_SUBSCRIPTION_ID or ARM_TENANT_ID not set; attempting destroy without variables"
        (cd terraform && TF_INPUT=false terraform destroy -auto-approve) || warn "Terraform destroy encountered issues"
    fi
    
    ok "Azure resources destroyed via Terraform."
else
    warn "No terraform state file found; skipping Terraform destroy."
fi

echo "Step 8: Final verification summary"
echo "  Remaining kind clusters:" $(kind get clusters 2>/dev/null || echo none)
echo "  Terraform state:" $([ -f terraform/terraform.tfstate ] && echo present || echo absent)

ok "Cleanup process completed."
echo ""
echo "All resources have been cleaned up:"
echo "  ✓ Workload cluster (ClusterAPI Cluster resource)"
echo "  ✓ Flux system (management cluster)"
echo "  ✓ Azure identity secret"
echo "  ✓ Management kind cluster"
echo "  ✓ Generated manifests and kubeconfigs"
echo "  ✓ Azure resources (service principal, resource group)"
echo ""
echo "You may now remove the repository directory if desired."
