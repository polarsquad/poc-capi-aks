#!/bin/bash
# Management Cluster Bootstrap Script
#
# Responsibilities:
# 1. Create the local kind-based ClusterAPI management cluster.
# 2. Initialize ClusterAPI (core + Azure provider).
# 3. Install Flux controllers (either via existing generated manifests or flux bootstrap).
# 4. Reconcile Git repository Kustomizations (apps + infrastructure) so Terraform Controller runs.

set -euo pipefail

echo "[management-bootstrap] Starting ClusterAPI management cluster setup..."

: "${CAPI_CLUSTER_NAME:?CAPI_CLUSTER_NAME env var is required}" || true

# Optional overrides for Flux/Git bootstrapping
GITHUB_OWNER=${GITHUB_OWNER:-"${GITHUB_USER:-your-github-username}"}
GITHUB_REPO=${GITHUB_REPO:-"poc-capi-aks"}
GITHUB_BRANCH=${GITHUB_BRANCH:-"main"}
FLUX_PATH=${FLUX_PATH:-"/flux-config/clusters"}
BOOTSTRAP_MODE=${BOOTSTRAP_MODE:-auto} # auto|manifests|github

echo "[management-bootstrap] Using settings:"
echo "  CAPI_CLUSTER_NAME=${CAPI_CLUSTER_NAME}"
echo "  GITHUB_OWNER=${GITHUB_OWNER}"
echo "  GITHUB_REPO=${GITHUB_REPO}"
echo "  GITHUB_BRANCH=${GITHUB_BRANCH}"
echo "  FLUX_PATH=${FLUX_PATH}"
echo "  BOOTSTRAP_MODE=${BOOTSTRAP_MODE}"

echo "[management-bootstrap] Checking prerequisites..."
for cmd in kind kubectl clusterctl flux; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: required command '$cmd' is not installed" >&2
        exit 1
    fi
done

# Create kind cluster if it does not already exist
if ! kind get clusters | grep -q "^${CAPI_CLUSTER_NAME}$"; then
  echo "[management-bootstrap] Creating kind management cluster '${CAPI_CLUSTER_NAME}' with tuned resources..."
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
  echo "[management-bootstrap] Reusing existing kind cluster '${CAPI_CLUSTER_NAME}'."
fi

kubectl config use-context "kind-${CAPI_CLUSTER_NAME}" >/dev/null

echo "[management-bootstrap] Initializing ClusterAPI (core + azure)..."
echo "(Note: harmless 'unrecognized format' warnings may appear)"
clusterctl init --infrastructure azure 2>&1 | grep -v "unrecognized format" || true

echo "[management-bootstrap] Waiting for ClusterAPI controllers to become Available..."
kubectl wait --for=condition=Available --timeout=300s -n capi-system deployment/capi-controller-manager 2>&1 | grep -v "unrecognized format"
kubectl wait --for=condition=Available --timeout=300s -n capz-system deployment/capz-controller-manager 2>&1 | grep -v "unrecognized format"

echo "[management-bootstrap] ClusterAPI ready. Proceeding to Flux installation..."

# Decide installation mode for Flux
# 1. manifests: apply existing flux-system generated manifests if present
# 2. github: run flux bootstrap github (requires GITHUB_TOKEN)
# 3. auto: prefer manifests if present, else bootstrap github

FLUX_SYSTEM_DIR="flux-config/clusters/flux-system"
GOTK_COMPONENTS_FILE="${FLUX_SYSTEM_DIR}/gotk-components.yaml"
GOTK_SYNC_FILE="${FLUX_SYSTEM_DIR}/gotk-sync.yaml"

determine_mode() {
  if [ "$BOOTSTRAP_MODE" = "auto" ]; then
    if [ -f "$GOTK_COMPONENTS_FILE" ] && [ -f "$GOTK_SYNC_FILE" ]; then
      echo manifests
    else
      echo github
    fi
  else
    echo "$BOOTSTRAP_MODE"
  fi
}

MODE=$(determine_mode)
echo "[management-bootstrap] Flux bootstrap mode resolved to: ${MODE}"

if [ "$MODE" = "manifests" ]; then
  echo "[management-bootstrap] Applying existing Flux system manifests..."
  kubectl apply -f "$GOTK_COMPONENTS_FILE"
  kubectl apply -f "$GOTK_SYNC_FILE"
elif [ "$MODE" = "github" ]; then
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "ERROR: GITHUB_TOKEN is required for github bootstrap mode" >&2
    exit 1
  fi
  echo "[management-bootstrap] Running 'flux bootstrap github'..."
  flux bootstrap github \
    --owner="${GITHUB_OWNER}" \
    --repository="${GITHUB_REPO}" \
    --branch="${GITHUB_BRANCH}" \
    --path="${FLUX_PATH}" \
    --personal \
    --private=true
else
  echo "ERROR: Unknown BOOTSTRAP_MODE='${MODE}' (expected auto|manifests|github)" >&2
  exit 1
fi

echo "[management-bootstrap] Verifying Flux controllers are ready..."
kubectl -n flux-system wait --for=condition=Available --timeout=180s deployment/source-controller || true
kubectl -n flux-system wait --for=condition=Available --timeout=180s deployment/kustomize-controller || true
kubectl -n flux-system wait --for=condition=Available --timeout=180s deployment/helm-controller || true
kubectl -n flux-system wait --for=condition=Available --timeout=180s deployment/notification-controller || true

echo "[management-bootstrap] Applying cluster-level Kustomization definitions (apps + infrastructure)..."
kubectl apply -f flux-config/clusters/aks-workload-cluster.yaml

echo "[management-bootstrap] Waiting for 'infrastructure' Kustomization to become Ready (Terraform Controller will install)..."
flux -n flux-system get kustomizations infrastructure || true
ATTEMPTS=0
until flux -n flux-system get kustomizations infrastructure 2>/dev/null | grep -q 'Ready'; do
  ATTEMPTS=$((ATTEMPTS+1))
  if [ $ATTEMPTS -gt 30 ]; then
    echo "WARNING: infrastructure Kustomization not Ready after retries; proceeding anyway" >&2
    break
  fi
  sleep 5
done

echo "[management-bootstrap] Checking Terraform Controller HelmRelease presence..."
kubectl get helmrelease -n flux-system terraform-controller 2>/dev/null || echo "(HelmRelease not yet created or using different name)"

echo "[management-bootstrap] If HelmRelease installed, waiting for terraform-controller deployment..."
kubectl -n flux-system wait --for=condition=Available --timeout=300s deployment/terraform-controller 2>/dev/null || echo "(terraform-controller deployment not detected yet)"

echo "[management-bootstrap] Management cluster bootstrap complete. Summary:" 
echo "  Context: kind-${CAPI_CLUSTER_NAME}" 
echo "  Flux Git source: github.com/${GITHUB_OWNER}/${GITHUB_REPO}@${GITHUB_BRANCH} path ${FLUX_PATH}" 
echo "  Terraform GitOps: flux-config/infrastructure/terraform-controller/terraform.yaml" 
echo "Next steps:" 
echo "  1. Ensure Azure credentials Secret applied (see setup-azure-credentials.sh)." 
echo "  2. Run workload cluster provisioning script once Terraform outputs are ready." 
echo "  3. Inspect Terraform CR: kubectl -n flux-system get terraform" 
echo "  4. View outputs: kubectl -n flux-system get secret terraform-outputs -o yaml" 
echo "Done."
