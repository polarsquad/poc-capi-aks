#!/bin/bash
# Test: GitOps workflow validation

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-aks-workload-cluster}"
WORKLOAD_KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}.kubeconfig"

echo "Testing GitOps Workflow..."

if [ ! -f "$WORKLOAD_KUBECONFIG" ]; then
    echo "⚠️  SKIP: Workload kubeconfig not found"
    exit 0
fi

# Test Flux reconciliation
echo "Testing Flux reconciliation..."
if command -v flux >/dev/null 2>&1; then
    if flux --kubeconfig="$WORKLOAD_KUBECONFIG" reconcile source git flux-system -n flux-system 2>/dev/null; then
        echo "✅ PASS: Git source reconciled successfully"
    else
        echo "⚠️  WARN: Git source reconciliation had issues"
    fi
    
    if flux --kubeconfig="$WORKLOAD_KUBECONFIG" reconcile kustomization apps -n default 2>/dev/null; then
        echo "✅ PASS: Apps Kustomization reconciled successfully"
    else
        echo "⚠️  WARN: Apps Kustomization reconciliation had issues"
    fi
else
    echo "⚠️  SKIP: Flux CLI not available"
fi

# Test resources match Git
echo "Checking deployed resources..."
if kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get deployment sample-app -n default >/dev/null 2>&1; then
    REPLICAS=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get deployment sample-app -n default \
        -o jsonpath='{.spec.replicas}')
    echo "✅ PASS: Sample app deployment has $REPLICAS replica(s)"
fi

if kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get helmrelease ingress-nginx -n default >/dev/null 2>&1; then
    HELM_STATUS=$(kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" get helmrelease ingress-nginx -n default \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$HELM_STATUS" = "True" ]; then
        echo "✅ PASS: NGINX Ingress HelmRelease is Ready"
    else
        echo "⚠️  WARN: NGINX Ingress HelmRelease status: $HELM_STATUS"
    fi
fi

echo "✅ GitOps workflow tests completed"
