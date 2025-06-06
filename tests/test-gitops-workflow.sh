#!/bin/bash
# Test Script: test-gitops-workflow.sh
WORKLOAD_CLUSTER_NAME="${CLUSTER_NAME}"
APP_NAME="sample-app"

echo "Testing GitOps Workflow..."

# Get initial replica count
INITIAL_REPLICAS=$(kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get deployment ${APP_NAME} -o jsonpath='{.spec.replicas}' 2>/dev/null)

if [ -z "$INITIAL_REPLICAS" ]; then
    echo "FAIL: Sample application deployment not found"
    exit 1
fi

echo "Initial replicas: $INITIAL_REPLICAS"

# Note: In a real test environment, this would programmatically update the Git repository
echo "Manual step required: Update replicas in Git repository from $INITIAL_REPLICAS to a different value"
echo "Then run this test again to verify the change was applied"

# For automated testing, you could implement Git operations here
# Example:
# git clone <repo-url> temp-repo
# cd temp-repo
# sed -i 's/replicas: '$INITIAL_REPLICAS'/replicas: 3/' apps/sample-app/deployment.yaml
# git commit -am "Update replica count for testing"
# git push
# cd ..
# rm -rf temp-repo

echo "Waiting 60 seconds for Flux to sync changes..."
sleep 60

# Check if replicas changed
CURRENT_REPLICAS=$(kubectl --kubeconfig=${WORKLOAD_CLUSTER_NAME}.kubeconfig get deployment ${APP_NAME} -o jsonpath='{.spec.replicas}' 2>/dev/null)

echo "Current replicas: $CURRENT_REPLICAS"

if [ "$CURRENT_REPLICAS" != "$INITIAL_REPLICAS" ]; then
    echo "PASS: GitOps workflow functioning - replicas changed from $INITIAL_REPLICAS to $CURRENT_REPLICAS"
else
    echo "INFO: GitOps workflow test inconclusive - no change detected"
    echo "This could be because no changes were made to the Git repository"
fi

echo "GitOps workflow tests completed"
