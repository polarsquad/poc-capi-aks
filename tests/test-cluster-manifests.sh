#!/bin/bash
set -euo pipefail
# Test Script: test-cluster-manifests.sh

if [ -z "${CLUSTER_NAME:-}" ]; then
    echo "ERROR: CLUSTER_NAME not set" >&2
    exit 1
fi

WORKLOAD_CLUSTER_NAME="${CLUSTER_NAME}"
echo "Testing ClusterAPI manifests for cluster: ${WORKLOAD_CLUSTER_NAME}" 

# Test cluster manifest syntax
kubectl apply --dry-run=client -f ./cluster-api/workload/cluster.yaml 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Cluster manifest syntax valid"
else
    echo "FAIL: Cluster manifest has syntax errors"
    exit 1
fi

echo "Skipping live apply creation test (manifest generation validation only)"
# Derive authoritative RG from Terraform
if command -v terraform >/dev/null 2>&1 && [ -f "terraform/terraform.tfstate" ]; then
    TF_DERIVED_RG=$(terraform -chdir=terraform output -raw resource_group_name 2>/dev/null || true)
fi

# Render manifest with envsubst (ensure ENV RG aligns or inject Terraform value)
if [ -n "${TF_DERIVED_RG:-}" ]; then
    export RESOURCE_GROUP_NAME="${TF_DERIVED_RG}"
fi

envsubst < ./cluster-api/workload/cluster.yaml > /tmp/cluster-manifests-generated.yaml

# Verify expected RG name appears
if [ -n "${TF_DERIVED_RG:-}" ]; then
    if ! grep -q "name: ${TF_DERIVED_RG}" /tmp/cluster-manifests-generated.yaml; then
        echo "FAIL: Generated manifest does not contain Terraform RG name (${TF_DERIVED_RG})"
        grep -n 'name:' /tmp/cluster-manifests-generated.yaml | head -n 25
        exit 1
    else
        echo "PASS: Manifest references Terraform RG name (${TF_DERIVED_RG})"
    fi
fi

echo "All manifest generation tests passed."
