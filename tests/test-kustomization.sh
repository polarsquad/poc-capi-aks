#!/bin/bash
# Test Script: test-kustomization.sh
CLUSTER_NAME="aks-workload-cluster"
KUSTOMIZATION_NAME="apps"

echo "Testing Kustomization Deployment..."

# Test Kustomization resource exists
kubectl --kubeconfig=${CLUSTER_NAME}.kubeconfig get kustomization $KUSTOMIZATION_NAME -n flux-system 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Kustomization resource exists"
else
    echo "FAIL: Kustomization resource not found"
    exit 1
fi

# Test Kustomization applied successfully
KUSTOMIZATION_STATUS=$(kubectl --kubeconfig=${CLUSTER_NAME}.kubeconfig get kustomization $KUSTOMIZATION_NAME -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$KUSTOMIZATION_STATUS" = "True" ]; then
    echo "PASS: Kustomization applied successfully"
else
    echo "FAIL: Kustomization application failed (Status: $KUSTOMIZATION_STATUS)"
    exit 1
fi

echo "Kustomization tests completed successfully"
