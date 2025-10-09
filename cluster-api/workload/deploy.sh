#!/bin/bash
# Generate and apply ClusterAPI workload cluster manifests
set -euo pipefail

echo "Deriving authoritative RESOURCE_GROUP_NAME..."

# Always attempt to read Terraform RG (authoritative) if state present
TF_STATE_DIR="../../terraform"
if command -v terraform >/dev/null 2>&1 && [ -f "$TF_STATE_DIR/terraform.tfstate" ]; then
    TF_DERIVED_RG=$(terraform -chdir=$TF_STATE_DIR output -raw resource_group_name 2>/dev/null || true)
fi

# Decide final RG:
# 1. If both set and mismatch -> fail unless ALLOW_RG_MISMATCH=1
# 2. Prefer Terraform value when present
if [ -n "${TF_DERIVED_RG:-}" ]; then
    if [ -n "${RESOURCE_GROUP_NAME:-}" ] && [ "${RESOURCE_GROUP_NAME}" != "${TF_DERIVED_RG}" ]; then
        if [ "${ALLOW_RG_MISMATCH:-0}" != "1" ]; then
            echo "ERROR: RESOURCE_GROUP_NAME='${RESOURCE_GROUP_NAME}' differs from Terraform resource_group_name='${TF_DERIVED_RG}'. Set ALLOW_RG_MISMATCH=1 to override or align values." >&2
            exit 1
        else
            echo "WARN: Using ENV RESOURCE_GROUP_NAME (${RESOURCE_GROUP_NAME}) overriding Terraform value (${TF_DERIVED_RG}) due to ALLOW_RG_MISMATCH=1" >&2
        fi
    else
        export RESOURCE_GROUP_NAME="${TF_DERIVED_RG}"
    fi
fi

if [ -z "${RESOURCE_GROUP_NAME:-}" ]; then
    echo "ERROR: RESOURCE_GROUP_NAME not set and Terraform output unavailable. Run terraform apply or export RESOURCE_GROUP_NAME." >&2
    exit 1
fi

echo "Using authoritative RESOURCE_GROUP_NAME=$RESOURCE_GROUP_NAME"

echo "Loading Azure credentials..."
if [ -f "../../azure-credentials.env" ]; then
    # shellcheck disable=SC1091
    source ../../azure-credentials.env
else
    echo "ERROR: Azure credentials not found. Please run setup-azure-credentials.sh first." >&2
    exit 1
fi

AZURE_ADMIN_GROUP_ID=${AZURE_ADMIN_GROUP_ID:-""}

echo "Rendering manifests (envsubst)..."
envsubst < cluster.yaml > cluster-generated.yaml

# Verify RG substitution
if ! grep -q "name: ${RESOURCE_GROUP_NAME}" cluster-generated.yaml; then
    echo "ERROR: Generated manifest does not reference expected RESOURCE_GROUP_NAME (${RESOURCE_GROUP_NAME})." >&2
    echo "       Examine cluster-generated.yaml for incorrect substitution." >&2
    exit 1
fi

echo "Applying ClusterAPI manifests..."
kubectl apply -f cluster-generated.yaml

echo "Waiting for cluster to be ready (Cluster Available condition)..."
echo "This may take several minutes..."

kubectl get cluster ${CLUSTER_NAME} -w &
WATCH_PID=$!
trap '[ -n "$WATCH_PID" ] && kill -0 $WATCH_PID 2>/dev/null && kill $WATCH_PID 2>/dev/null || true' EXIT

kubectl wait --for='jsonpath={.status.conditions[?(@.type=="Available")].status}=True' cluster/${CLUSTER_NAME} --timeout=900s

if kill -0 $WATCH_PID 2>/dev/null; then
    kill $WATCH_PID 2>/dev/null || true
fi

echo "Cluster provisioning completed!"
echo "Generating kubeconfig for workload cluster..."
clusterctl get kubeconfig ${CLUSTER_NAME} > ../../${CLUSTER_NAME}.kubeconfig

echo "Workload cluster is ready!"
echo "export KUBECONFIG=\$(pwd)/${CLUSTER_NAME}.kubeconfig"
