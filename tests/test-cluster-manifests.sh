#!/bin/bash
# Test Script: test-cluster-manifests.sh
WORKLOAD_CLUSTER_NAME="${CLUSTER_NAME}"

echo "Testing ClusterAPI Manifests..."

# Test cluster manifest syntax
kubectl apply --dry-run=client -f ./cluster-api/workload/cluster.yaml 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Cluster manifest syntax valid"
else
    echo "FAIL: Cluster manifest has syntax errors"
    exit 1
fi

# Test required fields are present after applying manifests
kubectl apply -f ../cluster-api/workload/ 2>/dev/null
CLUSTER_EXISTS=$(kubectl get cluster $WORKLOAD_CLUSTER_NAME -o name 2>/dev/null)
if [ -n "$CLUSTER_EXISTS" ]; then
    echo "PASS: Cluster resource created"
else
    echo "FAIL: Cluster resource not found"
    exit 1
fi

echo "Cluster manifest tests completed successfully"
