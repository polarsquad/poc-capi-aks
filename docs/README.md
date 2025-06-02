# Azure AKS Cluster with ClusterAPI and FluxCD

This project implements a complete Infrastructure as Code solution for Azure Kubernetes Service (AKS) using ClusterAPI for cluster lifecycle management and FluxCD for GitOps-based application deployment.

## Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Developer     │    │  Git Repository  │    │  Azure Cloud    │
│   Workstation   │    │   (GitOps)       │    │                 │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │ClusterAPI   │ │    │ │ App Manifests│ │    │ │ AKS Cluster │ │
│ │Management   │ │    │ │              │ │    │ │             │ │
│ │Cluster(Kind)│ │────┼─┤ Infrastructure│ │    │ │ ┌─────────┐ │ │
│ │             │ │    │ │              │ │    │ │ │FluxCD   │ │ │
│ └─────────────┘ │    │ │ Flux Config  │ │    │ │ │         │ │ │
│                 │    │ └──────────────┘ │    │ │ └─────────┘ │ │
└─────────────────┘    └──────────────────┘    │ │             │ │
                                  │             │ │ ┌─────────┐ │ │
                                  └─────────────┼─┤ │Sample   │ │ │
                                                │ │ │App      │ │ │
                                                │ │ └─────────┘ │ │
                                                │ └─────────────┘ │
                                                └─────────────────┘
```

## Components

- **Terraform**: Azure infrastructure provisioning
- **ClusterAPI (CAPI)**: Kubernetes cluster lifecycle management
- **Azure Provider (CAPZ)**: Azure-specific ClusterAPI implementation
- **FluxCD**: GitOps continuous delivery
- **Kind**: Local Kubernetes cluster for ClusterAPI management

## Prerequisites

### Software Requirements

1. **Azure CLI**: `az` command
2. **kubectl**: Kubernetes command-line tool
3. **helm**: Kubernetes package manager
4. **clusterctl**: ClusterAPI CLI
5. **flux**: FluxCD CLI
6. **kind**: Kubernetes in Docker
7. **terraform**: Infrastructure as Code tool
8. **git**: Version control
9. **docker**: Container runtime

### Azure Requirements

1. Azure subscription with appropriate permissions
2. Azure CLI logged in: `az login`
3. Sufficient quota for:
   - Resource groups
   - Virtual machines
   - Load balancers
   - Storage accounts

### GitHub Requirements

1. GitHub account
2. Personal access token with repo permissions
3. Environment variable: `export GITHUB_TOKEN=<your-token>`

## Quick Start

### 1. Clone and Setup

```bash
git clone <this-repository>
cd poc-capi-aks
```

### 2. Install Prerequisites

```bash
# Install on macOS using Homebrew
brew install azure-cli kubectl helm kind terraform

# Install ClusterAPI CLI
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.6.1/clusterctl-darwin-amd64 -o clusterctl
chmod +x clusterctl
sudo mv clusterctl /usr/local/bin/

# Install Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash
```

### 3. Azure Infrastructure Setup

```bash
# Login to Azure
az login

# Create Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with your values

# Initialize and apply Terraform
cd terraform
terraform init
terraform plan
terraform apply
cd ..
```

### 4. ClusterAPI Management Cluster

```bash
# Bootstrap management cluster
chmod +x cluster-api/management/bootstrap.sh
./cluster-api/management/bootstrap.sh

# Setup Azure credentials
chmod +x cluster-api/management/setup-azure-credentials.sh
./cluster-api/management/setup-azure-credentials.sh
```

### 5. Create AKS Workload Cluster

```bash
cd cluster-api/workload
chmod +x deploy.sh
./deploy.sh
cd ../..
```

### 6. Setup FluxCD

```bash
# Set GitHub repository details
export GITHUB_OWNER="your-github-username"
export GITHUB_REPO="poc-capi-aks"
export GITHUB_TOKEN="your-github-token"

# Bootstrap Flux
chmod +x flux-config/bootstrap-flux.sh
./flux-config/bootstrap-flux.sh
```

### 7. Run Tests

```bash
# Make all test scripts executable
chmod +x tests/*.sh

# Run comprehensive test suite
./tests/test-e2e-system.sh
```

## Project Structure

```
poc-capi-aks/
├── terraform/                  # Azure infrastructure
│   ├── main.tf                # Main Terraform configuration
│   ├── backend.tf             # Backend configuration
│   └── terraform.tfvars.example
├── cluster-api/
│   ├── management/            # Management cluster setup
│   │   ├── bootstrap.sh       # Bootstrap script
│   │   └── setup-azure-credentials.sh
│   └── workload/             # AKS cluster manifests
│       ├── cluster.yaml      # ClusterAPI manifests
│       ├── deploy.sh         # Deployment script
│       └── kustomization.yaml
├── flux-config/
│   ├── bootstrap-flux.sh     # Flux bootstrap script
│   ├── clusters/             # Cluster-specific configs
│   ├── apps/                # Application manifests
│   │   └── sample-app/      # Sample nginx application
│   └── infrastructure/      # Infrastructure components
│       └── ingress-nginx.yaml
├── tests/                   # Test scripts
│   ├── test-e2e-system.sh   # End-to-end test suite
│   ├── test-resource-group.sh
│   ├── test-service-principal.sh
│   ├── test-management-cluster.sh
│   ├── test-azure-provider.sh
│   ├── test-cluster-manifests.sh
│   ├── test-aks-provisioning.sh
│   ├── test-node-pools.sh
│   ├── test-flux-installation.sh
│   ├── test-git-connection.sh
│   ├── test-kustomization.sh
│   ├── test-sample-app.sh
│   ├── test-gitops-workflow.sh
│   └── test-disaster-recovery.sh
└── docs/                   # Documentation
    └── README.md          # This file
```

## Testing

The project includes comprehensive test scripts that follow the Test-Driven Development (TDD) approach:

### Individual Tests

```bash
# Test Azure infrastructure
./tests/test-resource-group.sh
./tests/test-service-principal.sh

# Test ClusterAPI setup
./tests/test-management-cluster.sh
./tests/test-azure-provider.sh

# Test AKS cluster
./tests/test-cluster-manifests.sh
./tests/test-aks-provisioning.sh
./tests/test-node-pools.sh

# Test FluxCD
./tests/test-flux-installation.sh
./tests/test-git-connection.sh
./tests/test-kustomization.sh

# Test applications
./tests/test-sample-app.sh
./tests/test-gitops-workflow.sh
```

### End-to-End Test

```bash
./tests/test-e2e-system.sh
```

### Disaster Recovery Test

```bash
./tests/test-disaster-recovery.sh
```

## GitOps Workflow

1. **Make changes** to application manifests in the `flux-config/apps/` directory
2. **Commit and push** changes to your Git repository
3. **FluxCD automatically syncs** changes to the cluster (within 1 minute by default)
4. **Verify deployment** using kubectl or the test scripts

Example workflow:
```bash
# Clone your GitOps repository
git clone https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}
cd ${GITHUB_REPO}

# Make changes to applications
vi apps/sample-app/deployment.yaml

# Commit and push
git add .
git commit -m "Update sample app configuration"
git push

# Flux will automatically sync within 1 minute
```

## Customization

### Modifying Cluster Configuration

Edit `cluster-api/workload/cluster.yaml` to customize:
- Kubernetes version
- Node pool size and VM types
- Network configuration
- Azure-specific settings

### Adding Applications

1. Create a new directory under `flux-config/apps/`
2. Add your Kubernetes manifests
3. Create a `kustomization.yaml` file
4. Update `flux-config/apps/kustomization.yaml` to include your app
5. Commit and push to your GitOps repository

### Infrastructure Components

Add infrastructure components (monitoring, logging, etc.) under `flux-config/infrastructure/`.

## Troubleshooting

### Common Issues

1. **ClusterAPI management cluster not accessible**
   ```bash
   kind get clusters
   kubectl cluster-info --context kind-capi-management
   ```

2. **Azure credentials not working**
   ```bash
   az account show
   kubectl get secret azure-cluster-identity-secret -o yaml
   ```

3. **AKS cluster not provisioning**
   ```bash
   kubectl get cluster aks-workload-cluster -o yaml
   kubectl describe cluster aks-workload-cluster
   ```

4. **FluxCD not syncing**
   ```bash
   flux get all
   flux logs --follow
   ```

### Cleanup

To completely remove all resources:

```bash
# Delete AKS cluster
kubectl delete cluster aks-workload-cluster

# Delete management cluster
kind delete cluster --name capi-management

# Destroy Azure infrastructure
cd terraform
terraform destroy
cd ..
```

## Security Considerations

- Service principal credentials are stored as Kubernetes secrets
- Use Azure Key Vault for production environments
- Enable RBAC and Azure AD integration
- Regularly rotate service principal credentials
- Use private clusters for production workloads

## Contributing

1. Follow the TDD approach - write tests first
2. Update documentation for any changes
3. Test all changes with the test suite
4. Follow GitOps principles for application changes

## References

- [ClusterAPI Documentation](https://cluster-api.sigs.k8s.io/)
- [ClusterAPI Azure Provider](https://capz.sigs.k8s.io/)
- [FluxCD Documentation](https://fluxcd.io/)
- [Azure AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
