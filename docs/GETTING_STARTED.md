# Getting Started Guide

This guide walks you through setting up the Azure AKS cluster with ClusterAPI (CAPI + CAPZ + ASO) and FluxCD step-by-step using the automation in this repository.

## Prerequisites Checklist

Install the following tools on macOS (Homebrew shown) and ensure you are authenticated to Azure and GitHub.

### Required CLI Tools
- Azure CLI (`az`)
- kubectl
- helm
- kind
- terraform
- git
- clusterctl
- flux
### Recommended but not required
- k9s 

### This project uses Mise for tool installation
For more information see https://mise.jdx.dev
If your none of the below methods of installation cover your use-case, visit https://mise.jdx.dev/installing-mise.html

### Install (macOS/Homebrew)
```bash
# If using homebrew
brew update && brew mise

# The .mise.toml file defines all required tools and their versions:

# Install all tools with: 
mise install
```

### Install (Linux/macOS)
```bash
curl https://mise.run | sh

# The .mise.toml file defines all required tools and their versions:

# Install all tools with: 
mise install
```

### Install (Windows)
```bash
# If using chocolatey
choco install mise

# Or if using winget
winget install jdx.mise

# The .mise.toml file defines all required tools and their versions:

# Install all tools with: 
mise install
```

### Accounts / Access
- Azure subscription: Owner/Contributor access to create Resource Group + Service Principal
- GitHub Personal Access Token (classic) with scopes: `repo`, `admin:repo_hook`, `admin:public_key`
- Docker Desktop running (Kind management cluster)

### Versions (Current Baseline)
- Kubernetes (management / Kind): v1.34.0
- ClusterAPI Core: v1.11.2
- CAPZ (Azure Provider): v1.21.0
- Azure Service Operator API: v1api20240901
- Workload Kubernetes (AKS): 1.33.2 (configurable)

### Management Cluster Characteristics
- Memory reservation: system-reserved=8Gi (bootstrap.sh) to mitigate OOM
- Eviction thresholds tuned (500Mi hard / 1Gi soft)
- Harmless OpenAPI warnings (`unrecognized format int32/int64`) filtered during bootstrap
- Secrets created:
   - `azure-cluster-identity-secret`: minimal (clientSecret)
   - `azure-cluster-identity`: full credential set (subscription / tenant / client IDs + secret)

```
### 1. Azure Setup

```bash
# Login to Azure
az login

# Verify you have the correct subscription selected
az account show

# If needed, set the correct subscription
az account set --subscription "Your Subscription Name"
```

### 2. GitHub Setup

Create a GitHub personal access token with proper scopes:
- Go to https://github.com/settings/tokens
- Click "Generate new token (classic)"
- Required scopes:
  - ✅ `repo` (Full control of private repositories)
  - ✅ `admin:repo_hook` (Full control of repository hooks)
  - ✅ `admin:public_key` (Full control of user public keys) - for deploy keys
- Save the token securely - you'll need it for the `mise.toml` file

### 3. Docker Desktop

Ensure Docker Desktop is running (required for Kind):
```bash
docker version
```

## Step-by-Step Setup

### Step 1: Clone and Configure

```bash
# Clone this repository
git clone https://github.com/polarsquad/poc-capi-aks.git
cd poc-capi-aks

# Update environment configuration
cp mise.example.toml mise.toml && vim mise.toml

# Edit the file with your values
# Required to edit: GITHUB_TOKEN, GITHUB_OWNER, ARM_SUBSCRIPTION_ID
# Other environment variable values are optional to change
```
Mise should automatically load your edited mise.toml file environment variables. If this is not the case, confirm the missing variables with `printenv` then ensure the config is trusted with `mise trust mise.toml`
If still missing, try `mise activate`, then `mise doctor` for more debugging information

**Key environment variables to configure:**
- `GITHUB_TOKEN`: Your GitHub personal access token (required scopes: repo, admin:repo_hook, admin:public_key)
- `GITHUB_OWNER`: Your GitHub username or organization
- `ARM_SUBSCRIPTION_ID`: Your Azure Subscription ID (the rest of the Azure credentials (subscription ID, tenant ID, client ID/secret) will be automatically populated from Terraform outputs)

### Step 2: Configure Terraform Variables

```bash
# Copy Terraform variables template and edit values
cp terraform/terraform.tfvars.example terraform/terraform.tfvars && vim terraform/terraform.tfvars
```

Example (adjust if desired; these defaults match the repository's Terraform variable defaults):
```hcl
resource_group_name        = "aks-workload-cluster-rg"
location                   = "swedencentral"      # Or eastus, westeurope, etc.
service_principal_name     = "aks-workload-cluster-sp"
```

Notes:
- The cluster manifest now uses `RESOURCE_GROUP_NAME` directly for ownership.
- Scripts/tests derive `RESOURCE_GROUP_NAME` from Terraform outputs if not explicitly exported.

### Step 3: Run Automated Setup

```bash
# It's important to run the setup script from the repository's root directory
# Make setup script executable and run
chmod +x setup.sh
./setup.sh
```

The setup script will:
1. ✅ Check prerequisites
2. ✅ Apply Terraform (RG + Service Principal)
3. ✅ Bootstrap CAPI management cluster (Kind + CAPI + CAPZ + ASO)
4. ✅ Create identity secrets (`azure-cluster-identity-secret` & `azure-cluster-identity` + `azure-credentials.env`)
5. ✅ Deploy workload cluster manifests (waits for Cluster `Available` condition only)
6. ✅ Bootstrap FluxCD to your GitHub repo (template processing currently commented out)
7. ✅ Run test suite

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
# Bootstrap management cluster (creates Kind cluster, installs ClusterAPI + CAPZ)
cd cluster-api/management
chmod +x bootstrap.sh
./bootstrap.sh

# Setup Azure credentials (extracts from Terraform, creates K8s secrets)
chmod +x setup-azure-credentials.sh
./setup-azure-credentials.sh
cd ../..
```

This creates:
- Kind cluster named `capi-management`
- ClusterAPI v1.11.2 controllers
- CAPZ v1.21.0 provider for Azure
- Two Kubernetes secrets: `azure-cluster-identity-secret` and `azure-cluster-identity`
- Saves credentials to `azure-credentials.env` file

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

### Azure Resources (via Terraform)
- **Resource Group**: `aks-workload-cluster-rg` (location: swedencentral)
- **Service Principal**: `aks-workload-cluster-sp` (Contributor on subscription)
- **Managed Identity**: Auto-created for AKS cluster
- **Role Assignments**: Service principal linked to subscription

### ClusterAPI Management Layer (Local Kind Cluster)
- **Kind Cluster**: `capi-management` running Kubernetes v1.34.0
- **ClusterAPI Core**: v1.11.2 for cluster lifecycle management
- **CAPZ Provider**: v1.21.0 (Cluster API Provider Azure)
- **Azure Service Operator (ASO)**: For native Azure resource management
- **Secrets**: `azure-cluster-identity` with service principal credentials

### AKS Workload Cluster (via ClusterAPI + ASO)
- **AKS Cluster**: `aks-workload-cluster` 
  - Kubernetes Version: 1.33.2
  - Location: swedencentral (or your configured location)
  - Network Plugin: Azure CNI
- **System Node Pool** (`pool0`):
  - Mode: System
  - Count: 2 nodes
  - VM Size: Standard_D2s_v3
  - Type: VirtualMachineScaleSets
- **User Node Pool** (`pool1`):
  - Mode: User
  - Count: 2 nodes
  - VM Size: Standard_D2s_v3
  - Type: VirtualMachineScaleSets
- **Kubeconfig**: Generated at `aks-workload-cluster.kubeconfig` (repo root)
- **Readiness Wait**: Current automation waits only for Cluster `Available`; ASO resource readiness (ManagedCluster) may lag.

### Kubernetes Resources Created
- **ClusterAPI Resources**:
  - `Cluster`: Main cluster definition
  - `AzureASOManagedControlPlane`: Control plane configuration
  - `AzureASOManagedCluster`: Infrastructure configuration
  - `MachinePool` (x2): Node pool definitions
  - `AzureASOManagedMachinePool` (x2): Azure-specific node pool specs

- **Azure Service Operator Resources**:
  - `ResourceGroup`: Azure resource group in Kubernetes
  - `ManagedCluster`: AKS cluster representation
  - `ManagedClustersAgentPool` (x2): Node pools

### GitOps & Applications
- **FluxCD Components** (in `flux-system` namespace):
  - Source Controller: Git repository monitoring
  - Kustomize Controller: Manifest reconciliation
  - Helm Controller: Helm release management
  - Notification Controller: Event notifications
- **GitRepository**: Connection to `${GITHUB_OWNER}/${GITHUB_REPO}`
- **Kustomizations**: Auto-sync for apps and infrastructure
- **Sample App**: nginx:1.29.2 deployment (2 replicas)
- **Infrastructure**: NGINX Ingress Controller (LoadBalancer)

![AKS Bootstrap & GitOps Architecture](../aks_bootstrap_architecture.png)

*Figure: High-level bootstrap and GitOps flow from Terraform provisioning through ClusterAPI/CAPZ/ASO to Flux-managed workloads.*

### Terraform Controller (GitOps Terraform Execution)
This repository now leverages the Terraform Controller (installed via Flux HelmRelease) to run Terraform inside the management cluster:

1. `flux-config/infrastructure/terraform-controller/helmrepository.yaml` and `helmrelease.yaml` install the controller.
2. `flux-config/infrastructure/terraform-controller/terraform.yaml` defines a `Terraform` CR (`aks-infra`) pointing to `./terraform`.
3. The controller automatically plans and applies with `approvePlan: auto`.
4. Azure credentials are sourced from existing secrets created during bootstrap (`azure-cluster-identity` & `azure-cluster-identity-secret`).
5. Outputs are written to secret `terraform-outputs` (extend consumption as needed for dynamic manifests).

Inspect Terraform run status:
```bash
kubectl get terraform -n flux-system
kubectl describe terraform aks-infra -n flux-system
kubectl logs -n flux-system deployment/tf-controller --tail=100
```

View outputs:
```bash
kubectl get secret terraform-outputs -n flux-system -o yaml
```

Development Notes:
- Local state is used for simplicity; migrate to Azure Storage backend for production.
- Changes to `terraform/` code trigger reconcile automatically after push.
- If Azure credentials rotate, re-run `setup-azure-credentials.sh` then ensure secrets are updated before next apply cycle.

## Next Steps

After successful setup:

1. **Add your applications:**
   - Create manifests in `apps/` directory
   - Update `apps/kustomization.yaml`
   - Commit and push changes

2. **Monitor deployments:**
   ```bash
   # Watch Flux sync status
   watch flux get all
   
   # Monitor application pods
   kubectl get pods -A
   ```

## Troubleshooting

### Common Issues

1. **Kind cluster OOM (Out of Memory):**
   ```bash
   # Increase Docker Desktop memory to 8GB+
   # Docker Desktop > Settings > Resources > Memory
   
   # The bootstrap.sh includes memory reservation settings
   # If issues persist, restart Docker Desktop
   docker restart $(docker ps -q --filter name=capi-management)
   ```

2. **Azure Resource Group location mismatch:**
   ```bash
   # Error: "Resource group already exists in location 'eastus'"
   # But your config specifies 'swedencentral'
   
   # Solution: Delete existing resource group
   az group delete --name aks-workload-cluster-rg --yes --no-wait
   
   # Update mise.toml with correct AZURE_LOCATION
   # Rerun setup
   ```

3. **ClusterAPI webhook timeouts:**
   ```bash
   # Check CAPZ system pods
   kubectl get pods -n capz-system
   kubectl get pods -n capi-system
   
   # If pods are CrashLoopBackOff, restart them
   kubectl delete pod -n capz-system -l control-plane=controller-manager
   kubectl delete pod -n capi-system -l control-plane=controller-manager
   
   # Check webhook service
   kubectl get svc -n capi-system capi-webhook-service
   ```

4. **ASO "WaitingForOwner" errors:**
   ```bash
   # Check if ResourceGroup was created
   kubectl get resourcegroup.resources.azure.com -A
   
   # Check ManagedCluster status
   kubectl get managedcluster.containerservice.azure.com -A -o yaml
   
   # Verify azure-cluster-identity secret
   kubectl get secret azure-cluster-identity -o yaml
   
   # Check ASO controller logs
   kubectl logs -n capz-system deployment/azureserviceoperator-controller-manager --tail=50
   ```

5. **Cluster not provisioning in Azure:**
   ```bash
   # Check cluster status in Kubernetes
   kubectl get cluster aks-workload-cluster -o yaml
   
   # Check Azure resources
   kubectl get managedcluster.containerservice.azure.com aks-workload-cluster -o yaml
   
   # Verify credentials in secret
   kubectl get secret azure-cluster-identity -o jsonpath='{.data.clientSecret}' | base64 -d
   
   # Check if cluster exists in Azure
   az aks show --name aks-workload-cluster --resource-group aks-workload-cluster-rg
   ```

6. **FluxCD bootstrap fails with GitHub token error:**
   ```bash
   # Error: "403 Resource not accessible by personal access token"
   # Your token needs proper scopes: repo, admin:repo_hook, admin:public_key
   
   # Create new token with correct scopes
   # Update GITHUB_TOKEN in mise.toml
   
   # Retry FluxCD bootstrap
   ./flux-config/bootstrap-flux.sh
   ```

7. **"unrecognized format" warnings:**
   ```bash
   # These warnings about int32/int64 formats are harmless
   # They come from OpenAPI validation in kubectl/client-go
   # The bootstrap script filters them out, but they don't affect functionality
   ```

8. **Variable substitution issues in manifests:**
   ```bash
   # If you see ${CLUSTER_NAME} in applied resources
   # Ensure environment variables are exported
   printenv | grep CLUSTER_NAME
   
   # The deploy.sh uses envsubst for variable substitution
   # Check cluster-generated.yaml for substituted values
   cat cluster-api/workload/cluster-generated.yaml
   ```

### Getting Help

- Check the logs: `flux logs --follow`
- Verify YAML syntax: `kubectl apply --dry-run=client -f <file>`
- Run individual tests: `./tests/test-<component>.sh`

## Accessing Your Cluster

After successful setup, you have multiple ways to access your cluster:

```bash
# Option 1: Export KUBECONFIG (recommended)
export KUBECONFIG=$(pwd)/aks-workload-cluster.kubeconfig

# Option 2: Use kubectl with --kubeconfig flag
kubectl --kubeconfig=aks-workload-cluster.kubeconfig get nodes

# Option 3: Use az aks get-credentials (if using Azure CLI)
az aks get-credentials --resource-group aks-workload-cluster-rg --name aks-workload-cluster

# Verify access
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

## Monitoring Your Deployment

```bash
# Watch cluster provisioning (from management cluster context)
kubectl config use-context kind-capi-management
kubectl get cluster aks-workload-cluster -w

# Check all ClusterAPI resources
kubectl get cluster,azureasomanagedcontrolplane,azureasomanagedcluster,machinepool -A

# Monitor Azure resources via ASO
kubectl get resourcegroup,managedcluster -A
kubectl get managedclustersagentpool -A

# Check FluxCD status (from workload cluster)
export KUBECONFIG=$(pwd)/aks-workload-cluster.kubeconfig
flux get all
flux get sources git
flux get kustomizations

# Watch application deployments
kubectl get deployments -A
kubectl get svc -A
```

## Cleanup

To remove all resources:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

This will:
1. Delete the AKS workload cluster (ClusterAPI resources)
2. Delete the Kind management cluster
3. Prompt to destroy Azure infrastructure via Terraform (optional)
4. Clean up local kubeconfig files
5. Remove generated manifests

**Manual cleanup steps if needed:**

```bash
# Delete cluster resources
kubectl delete cluster aks-workload-cluster

# Delete Kind cluster
kind delete cluster --name capi-management

# Delete Azure resources
cd terraform
terraform destroy
cd ..

# Delete Azure resource group (if Terraform fails)
az group delete --name aks-workload-cluster-rg --yes
```

**Note:** 
- The GitHub repository will need to be deleted manually if no longer needed
- FluxCD may have created deploy keys in your GitHub repository that should be removed
- Check for any Azure resources that weren't managed by Terraform

## Understanding the Architecture

### Component Versions
- **ClusterAPI Core**: v1.11.2
- **CAPZ (Azure Provider)**: v1.21.0
- **Azure Service Operator API**: v1api20240901
- **Kubernetes**: 1.33.2 (workload cluster)
- **Kind**: 1.34.0 (management cluster)

### Resource Hierarchy
```
Azure Subscription
└── Resource Group (aks-workload-cluster-rg)
    └── AKS Managed Cluster (aks-workload-cluster)
        ├── System Node Pool (pool0) - 2 nodes
        └── User Node Pool (pool1) - 2 nodes

Kind Management Cluster (capi-management)
└── ClusterAPI Resources
    ├── Cluster
    ├── AzureASOManagedControlPlane
    ├── AzureASOManagedCluster
    └── MachinePools (pool0, pool1)
```

### Key Files and Their Purpose
- **`mise.toml`**: Environment variables (optionally omit RESOURCE_GROUP_NAME & SERVICE_PRINCIPAL_NAME—tests derive from Terraform outputs)
- **`terraform/terraform.tfvars`**: Authoritative Azure RG / location / service principal names
- **`cluster-api/workload/cluster.yaml`**: Template; rendered by `envsubst` → `cluster-generated.yaml`
- **`cluster-api/workload/cluster-generated.yaml`**: Applied manifest (transient)
- **`cluster-api/workload/deploy.sh`**: Applies manifests & waits for `Cluster` Available (single wait)
- **`flux-config/bootstrap-flux.sh`**: Flux bootstrap (template processing commented out; enable if you add `*.yaml.template` files)
- **`flux-config/clusters/aks-workload-cluster.yaml`**: GitOps root (created by bootstrap)
- **`tests/*.sh`**: Validation & DR scripts (dynamic Terraform output consumption)

### Dynamic Name Resolution
Scripts & tests resolve names in this precedence order:
1. Terraform outputs (`terraform -chdir=terraform output -raw <name>`) 
2. `terraform.tfvars` parsing
3. Environment variables (`RESOURCE_GROUP_NAME`, `SERVICE_PRINCIPAL_NAME`)
4. Conventions (default SP name only)

Set `STRICT_RG_LOCATION=1` to fail (instead of warn) on resource group location mismatch in tests.

### Mixed API Versions
- `MachinePool`: `cluster.x-k8s.io/v1beta2`
- Azure ASO infra custom resources: `infrastructure.cluster.x-k8s.io/v1beta1`
This mix is expected with current CAPZ/ASO releases. Ensure your `clusterctl` version matches the documented CAPI release.

### Terraform Outputs
Inspect outputs after apply:
```bash
terraform -chdir=terraform output
```
Useful outputs consumed by scripts: `resource_group_name`, `service_principal_name`, `service_principal_client_id`, `service_principal_client_secret`, `subscription_id`, `tenant_id`.

### Flux Template Processing (Optional)
The `bootstrap-flux.sh` script has commented envsubst logic. If you introduce variables into Flux manifests:
1. Rename `*.yaml` → `*.yaml.template`
2. Uncomment the template block
3. Ensure variables are exported before running bootstrap.

## Security Best Practices

1. **Rotate credentials regularly:**
   ```bash
   # Service principal credentials expire based on Azure AD settings
   # Set calendar reminder to rotate
   
   # Check credential expiration
   az ad sp credential list --id ${AZURE_CLIENT_ID}
   
   # Generate new credentials
   cd terraform
   terraform apply  # This will rotate the service principal password
   
   # Update kubernetes secret
   kubectl delete secret azure-cluster-identity
   ./cluster-api/management/setup-azure-credentials.sh
   ```

2. **Secure your `mise.toml` file:**
   ```bash
   # Never commit mise.toml to Git
   # .gitignore should include mise.toml
   
   # Use restrictive permissions
   chmod 640 mise.toml
   ```

3. **GitHub token security:**
   - Use tokens with minimal required scopes
   - Set expiration dates on personal access tokens
   - Consider using GitHub App authentication for production
   - Rotate tokens periodically

4. **Azure RBAC:**
   - Service principal has Contributor role - consider more restrictive roles
   - Use Managed Identity where possible instead of service principals
   - Enable Azure AD integration for AKS for user authentication

5. **Network security:**
   - Current setup uses public AKS cluster for ease of use
   - For production, consider:
     - Private AKS clusters
     - Network policies
     - Azure Firewall integration
     - Authorized IP ranges for API server access

6. **Secrets management:**
   - Current setup stores credentials in Kubernetes secrets
   - For production, use:
     - Azure Key Vault with CSI driver integration
     - External Secrets Operator
     - Sealed Secrets for GitOps

## Advanced Configuration

### Changing Kubernetes Version
Edit `mise.toml`:
```bash
export KUBERNETES_VERSION="1.33.2"  # or another supported version
```

### Adding More Node Pools
Edit `cluster-api/workload/cluster.yaml` and add another MachinePool and AzureASOManagedMachinePool section.

### Changing Node Pool Size
Edit `mise.toml`:
```bash
export WORKER_MACHINE_COUNT=3  # Number of nodes per pool
export AZURE_NODE_MACHINE_TYPE="Standard_D4s_v3"  # Larger VM size
```

### Custom Location
Edit both `mise.toml` and `terraform/terraform.tfvars` to use the same location:
```bash
# mise.toml
AZURE_LOCATION = "westeurope"

# terraform.tfvars
location = "westeurope"
```

**Important:** Ensure both files use the same location to avoid resource group mismatch errors.

