# Terraform state configuration
# This file should be customized for your specific backend configuration

terraform {
  # Uncomment and configure for remote state storage
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "terraformstatestorage"
  #   container_name       = "tfstate"
  #   key                  = "capi-aks.terraform.tfstate"
  # }
}

# Example terraform.tfvars configuration:
# resource_group_name = "my-aks-cluster-rg"
# location = "eastus"
# service_principal_name = "my-aks-cluster-sp"
