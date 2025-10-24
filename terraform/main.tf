terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.47.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.6.0"
    }
  }
}

provider "azurerm" {
  features {}
  arm_subscription_id = var.arm_subscription_id
}

provider "azuread" {}

# Variables
variable "arm_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "azure_resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "aks-workload-cluster-rg"
}

variable "azure_location" {
  description = "Azure region"
  type        = string
  default     = "swedencentral"
}

variable "azure_service_principal_name" {
  description = "Name of the service principal"
  type        = string
  default     = "aks-workload-cluster-sp"
}

# Data sources
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.azure_resource_group_name
  location = var.azure_location

  tags = {
    Environment = "poc"
    Project     = "capi-aks"
    ManagedBy   = "terraform"
  }
}

# Azure AD Application
resource "azuread_application" "main" {
  display_name = var.azure_service_principal_name
  owners       = [data.azurerm_client_config.current.object_id]
}

# Service Principal
resource "azuread_service_principal" "main" {
  client_id = azuread_application.main.arm_client_id
  owners         = [data.azurerm_client_config.current.object_id]
}

# Service Principal Password
resource "azuread_service_principal_password" "main" {
  service_principal_id = azuread_service_principal.main.id
}

# Role Assignment - Contributor on Subscription
resource "azurerm_role_assignment" "contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.main.object_id
}

# Outputs
output "azure_resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "azure_resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "service_principal_client_id" {
  description = "Client ID of the service principal"
  value       = azuread_service_principal.main.client_id
}

output "service_principal_client_secret" {
  description = "Client secret of the service principal"
  value       = azuread_service_principal_password.main.value
  sensitive   = true
}

output "service_principal_object_id" {
  description = "Object ID of the service principal"
  value       = azuread_service_principal.main.object_id
}

output "arm_tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "arm_subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "azure_service_principal_name" {
  description = "Configured name of the service principal"
  value       = var.azure_service_principal_name
}
