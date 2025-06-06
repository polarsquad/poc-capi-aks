#!/bin/bash
# Test Script: test-sample-app.sh
WORKLOAD_CLUSTER_NAME="${CLUSTER_NAME}"
APP_NAMESPACE="default"
APP_NAME="sample-app"

echo "Testing Sample Application Deployment..."

# Test application pods are running
kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get pods -l app=${APP_NAME} -n ${APP_NAMESPACE} --field-selector=status.phase=Running 2>/dev/null
if [ $? -eq 0 ]; then
    RUNNING_PODS=$(kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get pods -l app=${APP_NAME} -n ${APP_NAMESPACE} --field-selector=status.phase=Running --no-headers | wc -l)
    if [ $RUNNING_PODS -gt 0 ]; then
        echo "PASS: Sample application pods running ($RUNNING_PODS pods)"
    else
        echo "FAIL: Sample application pods not running"
        exit 1
    fi
else
    echo "FAIL: Sample application pods not found"
    exit 1
fi

# Test service exists
kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get service ${APP_NAME} -n ${APP_NAMESPACE} 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Sample application service exists"
else
    echo "FAIL: Sample application service not found"
    exit 1
fi

# Test deployment is ready
kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get deployment ${APP_NAME} -n ${APP_NAMESPACE} -o jsonpath='{.status.readyReplicas}{"\n"}{end}' 2>/dev/null
READY_REPLICAS=$?
if [ $READY_REPLICAS -gt 0 ]; then
    echo "PASS: Sample application deployment is ready"
else
    echo "FAIL: Sample application deployment not ready"
    exit 1
fi

echo "Sample application tests completed successfully"
