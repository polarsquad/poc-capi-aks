#!/bin/bash
# Test Script: test-node-pools.sh
WORKLOAD_CLUSTER_NAME="${CLUSTER_NAME}"

echo "Testing Node Pool Configuration..."

# Test minimum node count
NODE_COUNT=$(kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get nodes --no-headers | wc -l)
if [ $NODE_COUNT -ge 1 ]; then
    echo "PASS: Sufficient nodes ($NODE_COUNT) available"
else
    echo "FAIL: Insufficient nodes ($NODE_COUNT)"
    exit 1
fi

# Test node readiness
READY_NODES=$(kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get nodes --no-headers | grep Ready | wc -l)
if [ $READY_NODES -eq $NODE_COUNT ]; then
    echo "PASS: All nodes are ready ($READY_NODES/$NODE_COUNT)"
else
    echo "FAIL: Not all nodes are ready ($READY_NODES/$NODE_COUNT)"
    exit 1
fi

# Test node pool configuration
kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get nodes -o wide

echo "Node pool tests completed successfully"
