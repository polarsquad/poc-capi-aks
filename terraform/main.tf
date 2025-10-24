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
  
  # Service principal authentication via environment variables
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  
  # Force service principal authentication (disable Azure CLI and OIDC)
  use_cli  = false
  use_oidc = false
}

provider "azuread" {
  # Service principal authentication via environment variables
  tenant_id     = var.tenant_id
  client_id     = var.client_id
  client_secret = var.client_secret
  
  # Force service principal authentication (disable Azure CLI and OIDC)
  use_cli  = false
  use_oidc = false
}

# Variables - Azure Authentication
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
  sensitive   = true
}

variable "client_id" {
  description = "Service principal client ID"
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "Service principal client secret"
  type        = string
  sensitive   = true
}

# Variables - Infrastructure
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "aks-workload-cluster-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "swedencentral"
}

variable "service_principal_name" {
  description = "Name of the service principal"
  type        = string
  default     = "aks-workload-cluster-sp"
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
  client_id = azuread_application.main.client_id
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

output "tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "service_principal_name" {
  description = "Configured name of the service principal"
  value       = var.service_principal_name
}
