# GitOps AKS with ClusterAPI and Flux

Automated setup for Azure Kubernetes Service (AKS) using Cluster API (CAPZ), Flux GitOps, and Terraform.

## Overview

This project provisions a complete GitOps-driven AKS infrastructure:

- **Management Cluster**: Local kind cluster running Cluster API controllers
- **Workload Cluster**: AKS cluster provisioned via Cluster API Azure provider (CAPZ)
- **GitOps**: Flux CD managing both clusters from this Git repository
- **Infrastructure**: Terraform-managed Azure service principal and resource group

![GitOps-driven AKS infrastructure](azure_kubernetes_fluxcd.svg)

## Prerequisites

Install the following tools (or use [mise](https://mise.jdx.dev/) with `mise.example.toml`):

- `kubectl` (1.34+)
- `az` CLI (latest(requires python > 3.10))
- `kind` (latest)
- `clusterctl` (1.10.7+)
- `flux` CLI (2.7.2+)
- `helm` (3.x)
- `terraform` (latest)
- `docker` (running)

## Quick Start

1. **Login to Azure**:
   ```bash
   az login
   ```

2. **Configure environment** (copy and edit):
   Note: Python greater than 3.10 is required to install the Azure CLI. If not already installed, run `mise use python@3.10.11` for a mise-compatible version to the Azure CLI.
   ```bash
   cp mise.example.toml mise.toml
   # Edit mise.toml with your GitHub and Azure details
   mise trust && mise install
   ```


3. **Run setup**:
   ```bash
   ./setup.sh
   ```

The script will:
- Create Azure resources (service principal, resource group)
- Create local kind management cluster
- Install Cluster API with Azure provider
- Deploy Flux on management cluster
- Provision AKS workload cluster
- Deploy Flux and applications on workload cluster
- Open the ingress-nginx LoadBalancer IP in your browser
- Run end-to-end system tests

## Project Structure

```
.
├── setup.sh                    # Main setup automation
├── cleanup.sh                  # Complete teardown script
├── terraform/                  # Azure infrastructure (SP, RG)
├── capi-workload/             # Management cluster GitOps
│   ├── flux-system/           # Flux controllers (auto-generated)
│   └── infrastructure/        # Cluster API manifests
│       └── aks-infrastructure/
│           └── cluster.yaml   # AKS cluster definition
└── aks-workload/              # Workload cluster GitOps
    ├── flux-system/           # Flux controllers (auto-generated)
    └── apps/                  # Application manifests
        └── sample-apps/
            ├── ingress-nginx.yaml
            └── deployment.yaml
```

## Configuration

Key environment variables in `mise.toml`:

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_OWNER` | GitHub username/org | - |
| `GITHUB_REPO` | Repository name | `poc-capi-aks` |
| `GITHUB_TOKEN` | Personal access token | - |
| `CLUSTER_NAME` | AKS cluster name | `aks-workload-cluster` |
| `AZURE_LOCATION` | Azure region | `swedencentral` |
| `KUBERNETES_VERSION` | K8s version | `1.33.3` |
| `WORKER_MACHINE_COUNT` | Node count | `1` |
| `AZURE_NODE_MACHINE_TYPE` | VM size | `standard_b2s` |

## Usage

### Switch to Workload Cluster
```bash
export KUBECONFIG="${HOME}/.kube/aks-workload-cluster.kubeconfig"
kubectl get nodes
```

### Check Flux Status
```bash
flux get all
```

### View Kustomizations
```bash
kubectl get kustomization -A
```

### Access Ingress
```bash
kubectl get svc -n default ingress-nginx-controller
```

### Run tests manually:
```bash
./tests/test-e2e-system.sh
```

## Cleanup

Remove all resources:
```bash
./cleanup.sh
```

This will delete:
- Workload AKS cluster
- Flux installations
- Management kind cluster
- Azure service principal and resource group
- Generated kubeconfig files

## How It Works

1. **Terraform** creates Azure service principal with contributor role and resource group
2. **Kind** creates local management cluster with Cluster API installed
3. **Flux** (management) watches `capi-workload/` directory in Git
4. **Cluster API** provisions AKS cluster based on `cluster.yaml` manifest
5. **Flux** (workload) watches `aks-workload/` directory in Git
6. **Applications** are deployed via Flux Kustomizations on workload cluster

## GitOps Workflow

1. Make changes to manifests in `aks-workload/apps/`
2. Commit and push to Git
3. Flux automatically reconciles changes to workload cluster
4. Check status: `flux get kustomizations -n default`

## Troubleshooting

**Cluster not provisioning:**
```bash
kubectl describe cluster aks-workload-cluster
kubectl get azureasomanagedcluster -o yaml
```

**Flux reconciliation issues:**
```bash
flux logs --all-namespaces
flux reconcile kustomization flux-system -n flux-system
```

**Kubeconfig not found:**
```bash
clusterctl get kubeconfig aks-workload-cluster > ~/.kube/aks-workload-cluster.kubeconfig
```

## License

See [LICENSE](LICENSE) file.
