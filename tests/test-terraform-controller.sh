#!/bin/bash
# Test Script: test-terraform-controller.sh
set -euo pipefail

NS=flux-system
TF_NAME=aks-infra

echo "[TEST] Terraform Controller & CR readiness"

# Check controller HelmRelease
if ! kubectl get helmrelease tf-controller -n $NS >/dev/null 2>&1; then
  echo "FAIL: HelmRelease tf-controller not found in namespace $NS"; exit 1; fi

# Check Terraform CR exists
if ! kubectl get terraform.$(kubectl api-resources --namespaced -o name | grep '^terraform\.' | head -n1) $TF_NAME -n $NS >/dev/null 2>&1; then
  # Fallback direct kind plural
  if ! kubectl get terraform $TF_NAME -n $NS >/dev/null 2>&1; then
    echo "FAIL: Terraform CR $TF_NAME not found in $NS"; exit 1
  fi
fi

echo "Waiting for Terraform CR to report Ready..."
for i in {1..30}; do
  READY=$(kubectl get terraform $TF_NAME -n $NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [ "$READY" = "True" ]; then
    echo "PASS: Terraform CR Ready"; break
  fi
  sleep 10
  echo "  Retry $i: Not ready yet"
  if [ $i -eq 30 ]; then
    echo "FAIL: Terraform CR not Ready within timeout"; exit 1
  fi
done

# Basic output secret check
if kubectl get secret terraform-outputs -n $NS >/dev/null 2>&1; then
  echo "PASS: terraform-outputs secret present"
else
  echo "WARN: terraform-outputs secret missing (outputs may not be configured)"
fi

# Validate Resource Group via terraform output vs Azure
TF_RG=$(kubectl get secret terraform-outputs -n $NS -o jsonpath='{.data.resource_group_name}' 2>/dev/null | base64 -d || echo "")
if [ -n "$TF_RG" ]; then
  echo "Terraform output resource_group_name: $TF_RG"
  if [ "$(az group exists --name "$TF_RG" 2>/dev/null || echo false)" = "true" ]; then
    echo "PASS: Azure Resource Group $TF_RG exists"
  else
    echo "FAIL: Azure Resource Group $TF_RG from terraform outputs does not exist"; exit 1
  fi
else
  echo "WARN: resource_group_name not found in terraform-outputs secret"
fi

# Confirm cluster manifest applied (Cluster resource present)
CLUSTER_NAME=${CLUSTER_NAME:-aks-workload-cluster}
if kubectl get cluster $CLUSTER_NAME >/dev/null 2>&1; then
  echo "PASS: Cluster resource $CLUSTER_NAME present"
else
  echo "FAIL: Cluster resource $CLUSTER_NAME not found"; exit 1
fi

echo "[TEST] Terraform Controller validation completed successfully"
