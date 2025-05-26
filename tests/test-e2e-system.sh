#!/bin/bash
# Test Script: test-e2e-system.sh

echo "Running comprehensive system validation..."

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Array of test scripts to run
TESTS=(
    "test-resource-group.sh"
    "test-service-principal.sh"
    "test-management-cluster.sh"
    "test-azure-provider.sh"
    "test-cluster-manifests.sh"
    "test-aks-provisioning.sh"
    "test-node-pools.sh"
    "test-flux-installation.sh"
    "test-git-connection.sh"
    "test-kustomization.sh"
    "test-sample-app.sh"
)

FAILED_TESTS=()
PASSED_TESTS=()

# Run each test
for test in "${TESTS[@]}"; do
    echo "================================================"
    echo "Running: $test"
    echo "================================================"
    
    if [ -f "$SCRIPT_DIR/$test" ]; then
        chmod +x "$SCRIPT_DIR/$test"
        if "$SCRIPT_DIR/$test"; then
            PASSED_TESTS+=("$test")
            echo "✅ $test PASSED"
        else
            FAILED_TESTS+=("$test")
            echo "❌ $test FAILED"
        fi
    else
        echo "⚠️  Test script $test not found"
        FAILED_TESTS+=("$test (not found)")
    fi
    
    echo ""
done

# Summary
echo "================================================"
echo "TEST SUMMARY"
echo "================================================"
echo "Total tests: ${#TESTS[@]}"
echo "Passed: ${#PASSED_TESTS[@]}"
echo "Failed: ${#FAILED_TESTS[@]}"
echo ""

if [ ${#PASSED_TESTS[@]} -gt 0 ]; then
    echo "✅ PASSED TESTS:"
    for test in "${PASSED_TESTS[@]}"; do
        echo "  - $test"
    done
    echo ""
fi

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo "❌ FAILED TESTS:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    echo ""
fi

if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo "🎉 All system components validated successfully!"
    exit 0
else
    echo "💥 System validation failed - ${#FAILED_TESTS[@]} test(s) failed"
    exit 1
fi
