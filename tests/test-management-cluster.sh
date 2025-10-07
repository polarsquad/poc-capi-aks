#!/bin/bash
# Test Script: test-management-cluster.sh

echo "Testing ClusterAPI Management Cluster..."

# Test if management cluster is accessible
kubectl cluster-info --context kind-$(CAPI_CLUSTER_NAME) 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Management cluster accessible"
else
    echo "FAIL: Management cluster not accessible"
    exit 1
fi

# Test ClusterAPI CRDs are installed
kubectl get crd clusters.cluster.x-k8s.io 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: ClusterAPI CRDs installed"
else
    echo "FAIL: ClusterAPI CRDs not found"
    exit 1
fi

echo "Management cluster tests completed successfully"
