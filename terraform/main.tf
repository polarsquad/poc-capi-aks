terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

# Variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "aks-cluster-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "service_principal_name" {
  description = "Name of the service principal"
  type        = string
  default     = "aks-cluster-sp"
}

# Data sources
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "poc"
    Project     = "capi-aks"
    ManagedBy   = "terraform"
  }
}

# Azure AD Application
resource "azuread_application" "main" {
  display_name = var.service_principal_name
  owners       = [data.azurerm_client_config.current.object_id]
}

# Service Principal
resource "azuread_service_principal" "main" {
  application_id = azuread_application.main.application_id
  owners         = [data.azurerm_client_config.current.object_id]
}

# Service Principal Password
resource "azuread_service_principal_password" "main" {
  service_principal_id = azuread_service_principal.main.object_id
  end_date_relative    = "8760h" # 1 year
}

# Role Assignment - Contributor on Subscription
resource "azurerm_role_assignment" "contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.main.object_id
}

# Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "service_principal_client_id" {
  description = "Client ID of the service principal"
  value       = azuread_service_principal.main.application_id
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

output "tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}
