# Getting Started Guide

This guide walks you through setting up the Azure AKS cluster with ClusterAPI and FluxCD step-by-step.

## Prerequisites Checklist

Before you begin...

### 1. Software Installation

Install the following tools on your macOS system:

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install azure-cli kubectl helm kind terraform git clusterctl fluxcd/tap/flux

### 2. Azure Setup

```bash
# Login to Azure
az login

# Verify you have the correct subscription selected
az account show

# If needed, set the correct subscription
az account set --subscription "Your Subscription Name"
```

### 3. GitHub Setup

Create a GitHub personal access token:
- Go to https://github.com/settings/tokens
- Generate a new token with the following permissions in the `repo` scope - `content:read+write, admin:read+write` including mandatory `metadata:read` permissions.
- Save the token securely

### 4. Docker Desktop

Ensure Docker Desktop is running (required for Kind):
```bash
docker version
```

## Step-by-Step Setup

### Step 1: Clone and Configure

```bash
# Clone this repository
git clone <repository-url>
cd poc-capi-aks

# Copy environment configuration
cp .env.example .env

# Edit .env file with your values
vim .env
```

### Step 2: Configure Terraform Variables

```bash
# Copy Terraform variables template
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit with your specific values
vim terraform/terraform.tfvars
```

Example `terraform.tfvars`:
```hcl
resource_group_name = "my-aks-cluster-rg"
location = "eastus"
service_principal_name = "my-aks-cluster-sp"
```

### Step 3: Run Automated Setup

```bash
# First source the environment variables in your terminal
source .env
```

```bash
# It's important to run the setup script from the repository's root directory
# Make setup script executable and run
chmod +x setup.sh
./setup.sh
```

The setup script will:
1. ✅ Check all prerequisites
2. ✅ Create Azure infrastructure with Terraform
3. ✅ Bootstrap ClusterAPI management cluster
4. ✅ Configure Azure credentials
5. ✅ Create AKS workload cluster
6. ✅ Setup FluxCD GitOps
7. ✅ Run comprehensive tests

### Step 4: Verify Installation

```bash
# Run the test suite
./tests/test-e2e-system.sh

# Check cluster status
export KUBECONFIG=cluster-api/workload/aks-workload-cluster.kubeconfig
kubectl get nodes

# Check Flux status
flux get all
```

## Manual Step-by-Step (Alternative)

If you prefer to run each step manually:

### 1. Azure Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
cd ..
```

### 2. ClusterAPI Management Cluster

```bash
# Bootstrap management cluster
./cluster-api/management/bootstrap.sh

# Setup Azure credentials
./cluster-api/management/setup-azure-credentials.sh
```

### 3. Create AKS Cluster

```bash
cd cluster-api/workload
./deploy.sh
cd ../..
```

### 4. Setup FluxCD

```bash
./flux-config/bootstrap-flux.sh
```

### 5. Test Everything

```bash
./tests/test-e2e-system.sh
```

## What Gets Created

### Azure Resources
- Resource Group: `aks-cluster-rg`
- Service Principal: `aks-cluster-sp` with Contributor role
- AKS Cluster: `aks-workload-cluster`
- Virtual Network and associated networking resources

### Local Resources
- Kind cluster: `capi-management` (ClusterAPI management)
- Kubeconfig: `cluster-api/workload/aks-workload-cluster.kubeconfig`

### GitOps Repository
- GitHub repository: `${GITHUB_OWNER}/${GITHUB_REPO}`
- FluxCD configuration for the AKS cluster
- Sample application manifests

## Next Steps

After successful setup:

1. **Clone your GitOps repository:**
   ```bash
   git clone https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}
   cd ${GITHUB_REPO}
   ```

2. **Add your applications:**
   - Create manifests in `apps/` directory
   - Update `apps/kustomization.yaml`
   - Commit and push changes

3. **Monitor deployments:**
   ```bash
   # Watch Flux sync status
   watch flux get all
   
   # Monitor application pods
   kubectl get pods -A
   ```

## Troubleshooting

### Common Issues

1. **Kind cluster creation fails:**
   ```bash
   # Ensure Docker is running
   docker ps
   
   # Delete and recreate
   kind delete cluster --name capi-management
   ./cluster-api/management/bootstrap.sh
   ```

2. **Azure authentication issues:**
   ```bash
   # Re-login to Azure
   az logout && az login
   
   # Check current subscription
   az account show
   ```

3. **ClusterAPI not working:**
   ```bash
   # Check management cluster
   kubectl cluster-info --context kind-capi-management
   
   # Check ClusterAPI controllers
   kubectl get pods -n capi-system
   kubectl get pods -n capz-system
   ```

4. **AKS cluster creation fails:**
   ```bash
   # Check cluster status
   kubectl get cluster aks-workload-cluster -o yaml
   
   # Check events
   kubectl get events --sort-by=.metadata.creationTimestamp
   ```

5. **FluxCD not syncing:**
   ```bash
   # Check Flux controllers
   kubectl get pods -n flux-system
   
   # Check Flux logs
   flux logs --follow
   
   # Force reconciliation
   flux reconcile source git flux-system
   ```

### Getting Help

- Check the logs: `flux logs --follow`
- Verify YAML syntax: `kubectl apply --dry-run=client -f <file>`
- Run individual tests: `./tests/test-<component>.sh`

## Cleanup

To remove all resources:

```bash
./cleanup.sh
```

This will:
- Delete the AKS cluster
- Delete the management cluster
- Destroy Azure infrastructure
- Clean up local files

**Note:** The GitHub repository will need to be deleted manually if no longer needed.

## Security Best Practices

1. **Rotate credentials regularly:**
   ```bash
   # Service principal credentials expire in 1 year
   # Set calendar reminder to rotate
   ```

2. **Use Azure Key Vault for production:**
   - Store sensitive values in Key Vault
   - Use Azure Key Vault provider for Secrets Store CSI driver

3. **Enable private clusters for production:**
   - Edit `cluster.yaml` to set `enablePrivateCluster: true`
   - Configure VPN or bastion host access

4. **Implement proper RBAC:**
   - Configure Azure AD integration
   - Use least privilege access principles
