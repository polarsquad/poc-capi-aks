#!/bin/bash
# Test Script: test-azure-provider.sh

echo "Testing Azure ClusterAPI Provider..."

# Test Azure provider pods are running
kubectl get pods -n capz-system --field-selector=status.phase=Running 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Azure provider pods running"
else
    echo "FAIL: Azure provider not running"
    exit 1
fi

# Test Azure credentials secret exists
kubectl get secret azure-cluster-identity-secret -n default 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Azure credentials configured"
else
    echo "FAIL: Azure credentials missing"
    exit 1
fi

echo "Azure provider tests completed successfully"
