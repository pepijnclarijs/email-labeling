# This terraform file creates a resource group, storage account, app service plan and function app.

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "email-labeling-rg"
  location = "East US"
}

resource "azurerm_storage_account" "sa" {
  name                     = "emaillabelingstg"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_app_service_plan" "plan" {
  name                = "email-labeling-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "FunctionApp"
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_function_app" "func" {
  name                       = "email-labeling-func"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.plan.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  version                    = "~4"
  os_type                    = "linux"
  runtime_stack              = "python"
  functions_extension_version = "~4"

  site_config {
    application_stack {
      python_version = "3.10"
    }
  }
}
