# TDD Plan: Azure AKS Cluster with FluxCD and ClusterAPI

## Overview
This test-driven development plan creates an Azure AKS cluster using ClusterAPI for cluster lifecycle management and FluxCD for GitOps-based application deployment.

## Prerequisites
- Azure subscription with appropriate permissions
- Git repository for GitOps configuration
- Local development environment with kubectl, helm, and azure-cli

## Phase 1: Infrastructure Foundation

### Test 1.1: Azure Resource Group Creation
**Test Description**: Verify Azure resource group exists and is properly configured

```bash
# Test Script: test-resource-group.sh
#!/bin/bash
RG_NAME="aks-cluster-rg"
LOCATION="eastus"

# Test if resource group exists
az group show --name $RG_NAME --query "name" -o tsv 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Resource group $RG_NAME exists"
else
    echo "FAIL: Resource group $RG_NAME does not exist"
    exit 1
fi

# Test location
ACTUAL_LOCATION=$(az group show --name $RG_NAME --query "location" -o tsv)
if [ "$ACTUAL_LOCATION" = "$LOCATION" ]; then
    echo "PASS: Resource group in correct location"
else
    echo "FAIL: Resource group in wrong location"
    exit 1
fi
```

**Implementation**: Create Terraform/ARM template for resource group

### Test 1.2: Service Principal and RBAC
**Test Description**: Verify service principal exists with correct permissions

```bash
# Test Script: test-service-principal.sh
#!/bin/bash
SP_NAME="aks-cluster-sp"

# Test if service principal exists
SP_ID=$(az ad sp list --display-name $SP_NAME --query "[0].appId" -o tsv)
if [ -n "$SP_ID" ]; then
    echo "PASS: Service principal exists"
else
    echo "FAIL: Service principal not found"
    exit 1
fi

# Test role assignment
az role assignment list --assignee $SP_ID --scope "/subscriptions/$(az account show --query id -o tsv)" \
    --query "[?roleDefinitionName=='Contributor']" -o tsv
if [ $? -eq 0 ]; then
    echo "PASS: Service principal has Contributor role"
else
    echo "FAIL: Service principal missing required permissions"
    exit 1
fi
```

**Implementation**: Create service principal with required RBAC roles

## Phase 2: ClusterAPI Management Cluster

### Test 2.1: Management Cluster Bootstrap
**Test Description**: Verify kind/local cluster exists for ClusterAPI management

```bash
# Test Script: test-management-cluster.sh
#!/bin/bash

# Test if management cluster is accessible
kubectl cluster-info --context kind-capi-management 2>/dev/null
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
```

**Implementation**: Bootstrap kind cluster and install ClusterAPI components

### Test 2.2: Azure Provider Installation
**Test Description**: Verify Azure ClusterAPI provider is installed and configured

```bash
# Test Script: test-azure-provider.sh
#!/bin/bash

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
```

**Implementation**: Install and configure Azure ClusterAPI provider (CAPZ)

## Phase 3: Target AKS Cluster Creation

### Test 3.1: Cluster Manifest Validation
**Test Description**: Verify ClusterAPI manifests are valid and complete

```bash
# Test Script: test-cluster-manifests.sh
#!/bin/bash
CLUSTER_NAME="aks-workload-cluster"

# Test cluster manifest syntax
kubectl apply --dry-run=client -f cluster-manifests/ 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Cluster manifest syntax valid"
else
    echo "FAIL: Cluster manifest has syntax errors"
    exit 1
fi

# Test required fields are present
CLUSTER_EXISTS=$(kubectl get cluster $CLUSTER_NAME -o name 2>/dev/null)
if [ -n "$CLUSTER_EXISTS" ]; then
    echo "PASS: Cluster resource created"
else
    echo "FAIL: Cluster resource not found"
    exit 1
fi
```

**Implementation**: Create ClusterAPI manifests for AKS cluster

### Test 3.2: AKS Cluster Provisioning
**Test Description**: Verify AKS cluster is provisioned and accessible

```bash
# Test Script: test-aks-provisioning.sh
#!/bin/bash
CLUSTER_NAME="aks-workload-cluster"
RG_NAME="aks-cluster-rg"

# Test cluster provisioning status
CLUSTER_PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}')
if [ "$CLUSTER_PHASE" = "Provisioned" ]; then
    echo "PASS: Cluster provisioned successfully"
else
    echo "FAIL: Cluster not provisioned (Phase: $CLUSTER_PHASE)"
    exit 1
fi

# Test Azure AKS resource exists
az aks show --resource-group $RG_NAME --name $CLUSTER_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: AKS cluster exists in Azure"
else
    echo "FAIL: AKS cluster not found in Azure"
    exit 1
fi

# Test cluster connectivity
kubectl get nodes --context $CLUSTER_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Can connect to AKS cluster"
else
    echo "FAIL: Cannot connect to AKS cluster"
    exit 1
fi
```

**Implementation**: Apply ClusterAPI manifests and wait for provisioning

### Test 3.3: Node Pool Configuration
**Test Description**: Verify node pools are configured correctly

```bash
# Test Script: test-node-pools.sh
#!/bin/bash
CLUSTER_NAME="aks-workload-cluster"

# Test minimum node count
NODE_COUNT=$(kubectl get nodes --context $CLUSTER_NAME --no-headers | wc -l)
if [ $NODE_COUNT -ge 2 ]; then
    echo "PASS: Sufficient nodes ($NODE_COUNT) available"
else
    echo "FAIL: Insufficient nodes ($NODE_COUNT)"
    exit 1
fi

# Test node readiness
READY_NODES=$(kubectl get nodes --context $CLUSTER_NAME --no-headers | grep Ready | wc -l)
if [ $READY_NODES -eq $NODE_COUNT ]; then
    echo "PASS: All nodes are ready"
else
    echo "FAIL: Not all nodes are ready ($READY_NODES/$NODE_COUNT)"
    exit 1
fi
```

**Implementation**: Configure appropriate node pools in ClusterAPI manifests

## Phase 4: FluxCD GitOps Setup

### Test 4.1: Flux Installation
**Test Description**: Verify FluxCD is installed on the target cluster

```bash
# Test Script: test-flux-installation.sh
#!/bin/bash
CLUSTER_NAME="aks-workload-cluster"

# Test Flux namespace exists
kubectl get namespace flux-system --context $CLUSTER_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Flux namespace exists"
else
    echo "FAIL: Flux namespace not found"
    exit 1
fi

# Test Flux controllers are running
FLUX_PODS=$(kubectl get pods -n flux-system --context $CLUSTER_NAME --field-selector=status.phase=Running --no-headers | wc -l)
if [ $FLUX_PODS -ge 4 ]; then
    echo "PASS: Flux controllers running ($FLUX_PODS pods)"
else
    echo "FAIL: Insufficient Flux controllers running ($FLUX_PODS pods)"
    exit 1
fi

# Test Flux readiness
flux check --context $CLUSTER_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Flux system ready"
else
    echo "FAIL: Flux system not ready"
    exit 1
fi
```

**Implementation**: Install FluxCD using flux bootstrap command

### Test 4.2: Git Repository Connection
**Test Description**: Verify FluxCD can connect to Git repository

```bash
# Test Script: test-git-connection.sh
#!/bin/bash
CLUSTER_NAME="aks-workload-cluster"
REPO_NAME="flux-config"

# Test GitRepository resource exists
kubectl get gitrepository $REPO_NAME -n flux-system --context $CLUSTER_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: GitRepository resource exists"
else
    echo "FAIL: GitRepository resource not found"
    exit 1
fi

# Test repository sync status
SYNC_STATUS=$(kubectl get gitrepository $REPO_NAME -n flux-system --context $CLUSTER_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$SYNC_STATUS" = "True" ]; then
    echo "PASS: Git repository synced successfully"
else
    echo "FAIL: Git repository sync failed"
    exit 1
fi
```

**Implementation**: Configure GitRepository and authentication

### Test 4.3: Kustomization Deployment
**Test Description**: Verify Kustomization resources are deployed

```bash
# Test Script: test-kustomization.sh
#!/bin/bash
CLUSTER_NAME="aks-workload-cluster"
KUSTOMIZATION_NAME="apps"

# Test Kustomization resource exists
kubectl get kustomization $KUSTOMIZATION_NAME -n flux-system --context $CLUSTER_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Kustomization resource exists"
else
    echo "FAIL: Kustomization resource not found"
    exit 1
fi

# Test Kustomization applied successfully
KUSTOMIZATION_STATUS=$(kubectl get kustomization $KUSTOMIZATION_NAME -n flux-system --context $CLUSTER_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$KUSTOMIZATION_STATUS" = "True" ]; then
    echo "PASS: Kustomization applied successfully"
else
    echo "FAIL: Kustomization application failed"
    exit 1
fi
```

**Implementation**: Create Kustomization resources for application deployment

## Phase 5: Application Deployment Tests

### Test 5.1: Sample Application Deployment
**Test Description**: Verify sample application deploys via GitOps

```bash
# Test Script: test-sample-app.sh
#!/bin/bash
CLUSTER_NAME="aks-workload-cluster"
APP_NAMESPACE="default"
APP_NAME="sample-app"

# Test application pods are running
kubectl get pods -l app=$APP_NAME -n $APP_NAMESPACE --context $CLUSTER_NAME --field-selector=status.phase=Running 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Sample application pods running"
else
    echo "FAIL: Sample application pods not running"
    exit 1
fi

# Test service exists
kubectl get service $APP_NAME -n $APP_NAMESPACE --context $CLUSTER_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS: Sample application service exists"
else
    echo "FAIL: Sample application service not found"
    exit 1
fi
```

**Implementation**: Create sample application manifests in Git repository

### Test 5.2: GitOps Workflow Validation
**Test Description**: Verify changes in Git trigger deployments

```bash
# Test Script: test-gitops-workflow.sh
#!/bin/bash
CLUSTER_NAME="aks-workload-cluster"
APP_NAME="sample-app"

# Make a change to the Git repository (automated test would modify a file)
INITIAL_REPLICAS=$(kubectl get deployment $APP_NAME --context $CLUSTER_NAME -o jsonpath='{.spec.replicas}')

# Update replicas in Git (this would be done programmatically in real test)
echo "Manual step: Update replicas in Git repository"

# Wait for sync and verify change
sleep 30
CURRENT_REPLICAS=$(kubectl get deployment $APP_NAME --context $CLUSTER_NAME -o jsonpath='{.spec.replicas}')

if [ "$CURRENT_REPLICAS" != "$INITIAL_REPLICAS" ]; then
    echo "PASS: GitOps workflow functioning"
else
    echo "FAIL: GitOps workflow not updating deployments"
    exit 1
fi
```

**Implementation**: Document GitOps workflow and create test procedures

## Phase 6: Integration and End-to-End Tests

### Test 6.1: Complete System Validation
**Test Description**: Comprehensive system test covering all components

```bash
# Test Script: test-e2e-system.sh
#!/bin/bash

echo "Running comprehensive system validation..."

# Run all individual test scripts
./test-resource-group.sh && \
./test-service-principal.sh && \
./test-management-cluster.sh && \
./test-azure-provider.sh && \
./test-cluster-manifests.sh && \
./test-aks-provisioning.sh && \
./test-node-pools.sh && \
./test-flux-installation.sh && \
./test-git-connection.sh && \
./test-kustomization.sh && \
./test-sample-app.sh

if [ $? -eq 0 ]; then
    echo "PASS: All system components validated successfully"
else
    echo "FAIL: System validation failed"
    exit 1
fi
```

### Test 6.2: Disaster Recovery Test
**Test Description**: Verify cluster can be recreated from Git configuration

```bash
# Test Script: test-disaster-recovery.sh
#!/bin/bash
CLUSTER_NAME="aks-workload-cluster"

echo "Testing disaster recovery scenario..."

# Delete cluster (in test environment only)
kubectl delete cluster $CLUSTER_NAME

# Wait for deletion
sleep 300

# Recreate cluster from manifests
kubectl apply -f cluster-manifests/

# Wait for provisioning
sleep 900

# Verify cluster and applications are restored
./test-aks-provisioning.sh && \
./test-flux-installation.sh && \
./test-sample-app.sh

if [ $? -eq 0 ]; then
    echo "PASS: Disaster recovery successful"
else
    echo "FAIL: Disaster recovery failed"
    exit 1
fi
```

## Implementation Timeline

### Week 1: Foundation (Phase 1-2)
- Set up Azure resources and permissions
- Bootstrap ClusterAPI management cluster
- Install and configure Azure provider

### Week 2: Cluster Creation (Phase 3)
- Create ClusterAPI manifests
- Provision AKS cluster
- Validate cluster connectivity and node configuration

### Week 3: GitOps Setup (Phase 4)
- Install FluxCD on target cluster
- Configure Git repository connection
- Set up Kustomization resources

### Week 4: Applications and Testing (Phase 5-6)
- Deploy sample applications
- Validate GitOps workflows
- Run comprehensive integration tests
- Document disaster recovery procedures

## Repository Structure

```
project-root/
├── terraform/                 # Azure infrastructure
├── cluster-api/
│   ├── management/           # Management cluster setup
│   └── workload/            # AKS cluster manifests
├── flux-config/
│   ├── clusters/            # Cluster-specific configs
│   ├── apps/               # Application manifests
│   └── infrastructure/     # Infrastructure components
├── tests/                  # All test scripts
└── docs/                  # Documentation
```

## Success Criteria

The implementation is complete when:
1. All test scripts pass consistently
2. AKS cluster can be created and destroyed via ClusterAPI
3. Applications deploy automatically via FluxCD GitOps
4. Changes to Git repository trigger application updates
5. Complete system can be recreated from Git configuration
6. Disaster recovery procedures are validated

## Continuous Integration

Integrate all tests into CI/CD pipeline:
- Run infrastructure tests on Terraform changes
- Run cluster tests on ClusterAPI manifest changes
- Run application tests on Git repository changes
- Schedule periodic end-to-end tests