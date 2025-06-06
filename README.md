# Azure AKS with ClusterAPI and FluxCD

A comprehensive Infrastructure as Code solution for Azure Kubernetes Service (AKS) using ClusterAPI for cluster lifecycle management and FluxCD for GitOps-based application deployment.

## Features

- ✅ **Entirely Infrastructure as Code**: Terraform for basic Azure resources
- ✅ **Cluster Lifecycle Management**: ClusterAPI with Azure provider (CAPZ)
- ✅ **GitOps Continuous Delivery**: FluxCD v2 for Kubernetes Resource Management
- ✅ **Test-Driven Development**: Comprehensive test suite
- ✅ **Disaster Recovery**: Automated cluster recreation capabilities

## Quick Start

Refer to [guide](/docs/GETTING_STARTED.md)

## Architecture

The solution creates:

1. **Azure Infrastructure** (via Terraform):
   - Resource Group
   - Service Principal with RBAC
   - Required networking and security configurations

2. **ClusterAPI Management Cluster** (Kind):
   - Local Kubernetes cluster for managing AKS lifecycle
   - Azure provider (CAPZ) installation
   - Credential management

3. **AKS Workload Cluster** (via ClusterAPI):
   - Managed Kubernetes cluster in Azure
   - Multiple node pools
   - Azure integration (AAD, networking, etc.)

4. **FluxCD GitOps** (on AKS):
   - Git repository synchronization
   - Automated application deployment
   - Infrastructure component management

## Project Structure

```
poc-capi-aks/
├── terraform/              # Azure infrastructure
├── cluster-api/            # ClusterAPI configurations
│   ├── management/         # Management cluster setup
│   └── workload/          # AKS cluster manifests
├── flux-config/           # FluxCD and GitOps configs
│   ├── apps/              # Application manifests
│   ├── clusters/          # Cluster-specific configs
│   └── infrastructure/    # Infrastructure components
├── tests/                 # Comprehensive test suite
├── docs/                  # Detailed documentation
├── setup.sh              # Complete setup script
└── cleanup.sh            # Cleanup script
```

## Testing

The project includes a comprehensive test-driven development approach:

```bash
# Run all tests
./tests/test-e2e-system.sh

# Individual test categories
./tests/test-resource-group.sh      # Azure infrastructure
./tests/test-management-cluster.sh  # ClusterAPI setup
./tests/test-aks-provisioning.sh   # AKS cluster
./tests/test-flux-installation.sh  # FluxCD
./tests/test-sample-app.sh         # Application deployment
./tests/test-disaster-recovery.sh  # DR procedures
```

## Prerequisites

- Azure subscription with permissions
- GitHub account and personal access token
- Local tools: `az`, `kubectl`, `helm`, `kind`, `clusterctl`, `flux`, `terraform`

## GitOps Workflow

1. Make changes to application manifests in your Git repository
2. FluxCD automatically syncs changes to the cluster
3. Applications are deployed/updated automatically
4. Monitor via Kubernetes resources and FluxCD status

## Contributing

1. Follow the TDD approach - tests first
2. Update documentation for changes
3. Ensure all tests pass
4. Use GitOps principles for application changes

## Cleanup

To remove all resources:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

## License

Apache License 2.0 - see [LICENSE](LICENSE) file for details.
