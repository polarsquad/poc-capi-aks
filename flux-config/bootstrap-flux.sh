#!/bin/bash
# FluxCD Bootstrap Script

set -e

CLUSTER_NAME="aks-workload-cluster"
GITHUB_OWNER=${GITHUB_OWNER:-"your-github-username"}
GITHUB_REPO=${GITHUB_REPO:-"poc-capi-aks"}
GITHUB_BRANCH=${GITHUB_BRANCH:-"main"}
KUBECONFIG=$(pwd)/${CLUSTER_NAME:-"aks-workload-cluster"}.kubeconfig

echo "Setting up FluxCD on AKS cluster..."

# Check prerequisites
if [ ! -f "${CLUSTER_NAME}.kubeconfig" ]; then
    echo "ERROR: Kubeconfig for ${CLUSTER_NAME} not found"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: GITHUB_TOKEN environment variable is required"
    exit 1
fi

# Check if flux CLI is installed
if ! command -v flux &> /dev/null; then
    echo "ERROR: flux CLI is not installed"
    echo "Install it from: https://fluxcd.io/flux/installation/"
    exit 1
fi

# Set kubeconfig
export KUBECONFIG=${CLUSTER_NAME}.kubeconfig

# Pre-flight check
echo "Running pre-flight check..."
flux check --pre

# Bootstrap Flux
echo "Bootstrapping FluxCD..."
flux bootstrap github \
  --owner=${GITHUB_OWNER} \
  --repository=${GITHUB_REPO} \
  --branch=${GITHUB_BRANCH} \
  --path=/flux-config/clusters \
  --personal \
  --private=true

echo "FluxCD bootstrap completed successfully!"
echo ""
echo "Next steps:"
echo "1. Clone the GitOps repository: git clone https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
echo "2. Add your application manifests to the repository"
echo "3. Flux will automatically sync the changes"
