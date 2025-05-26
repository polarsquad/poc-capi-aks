#!/bin/bash
# Test Script: test-flux-installation.sh
CLUSTER_NAME="aks-workload-cluster"

echo "Testing FluxCD Installation..."

# Test Flux namespace exists
kubectl --kubeconfig=${CLUSTER_NAME}.kubeconfig get namespace flux-system 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Flux namespace exists"
else
    echo "FAIL: Flux namespace not found"
    exit 1
fi

# Test Flux controllers are running
FLUX_PODS=$(kubectl --kubeconfig=${CLUSTER_NAME}.kubeconfig get pods -n flux-system --field-selector=status.phase=Running --no-headers | wc -l)
if [ $FLUX_PODS -ge 4 ]; then
    echo "PASS: Flux controllers running ($FLUX_PODS pods)"
else
    echo "FAIL: Insufficient Flux controllers running ($FLUX_PODS pods)"
    exit 1
fi

# Test Flux readiness
flux check --kubeconfig=${CLUSTER_NAME}.kubeconfig 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Flux system ready"
else
    echo "FAIL: Flux system not ready"
    exit 1
fi

echo "FluxCD installation tests completed successfully"
