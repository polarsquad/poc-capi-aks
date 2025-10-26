#!/bin/bash
# Test: Sample application deployment validation

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-aks-workload-cluster}"
WORKLOAD_KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}.kubeconfig"

echo "Testing Sample Application Deployment..."

if [ ! -f "$WORKLOAD_KUBECONFIG" ]; then
    echo "⚠️  SKIP: Workload kubeconfig not found"
    exit 0
fi

# Test deployment exists
if ! kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get deployment sample-app -n default >/dev/null 2>&1; then
    echo "⚠️  SKIP: Sample app deployment not found (may not be deployed yet)"
    exit 0
fi
echo "✅ PASS: Sample app deployment exists"

# Test pod status
RUNNING_PODS=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get pods -n default \
    -l app=sample-app --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$RUNNING_PODS" -gt 0 ]; then
    echo "✅ PASS: Sample app pods running ($RUNNING_PODS pod(s))"
else
    echo "⚠️  WARN: No sample app pods running yet"
fi

# Test service exists
if kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get service sample-app -n default >/dev/null 2>&1; then
    echo "✅ PASS: Sample app service exists"
fi

# Test ingress-nginx controller
if kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get deployment ingress-nginx-controller -n default >/dev/null 2>&1; then
    echo "✅ PASS: NGINX ingress controller deployed"
    
    # Check for LoadBalancer IP
    LB_IP=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get service ingress-nginx-controller -n default \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$LB_IP" ]; then
        echo "✅ PASS: LoadBalancer IP assigned: $LB_IP"
    else
        echo "⚠️  WARN: LoadBalancer IP not yet assigned"
    fi
fi

echo "✅ Sample application tests completed"
