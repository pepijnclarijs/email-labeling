provider "azurerm" {
  features {}
  subscription_id = "578cb0e7-8d21-4544-9b28-1360e9a76b9b"
}

resource "azurerm_resource_group" "rg" {
  name     = "email-labeling-rg"
  location = "westeurope"
}

resource "azurerm_storage_account" "sa" {
  name                     = "emaillabelingstg"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "functions" {
  name                  = "functions"
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "function_zip" {
  name                   = "function.zip"
  storage_account_name   = azurerm_storage_account.sa.name
  storage_container_name = azurerm_storage_container.functions.name
  type                   = "Block"
  source                 = "./placeholder_file.zip"  // Ensure this file exists locally
}

data "azurerm_storage_account_sas" "function_sas" {
  connection_string = azurerm_storage_account.sa.primary_connection_string
  https_only        = true
  start             = "2025-04-27T00:00:00Z"
  expiry            = "2027-04-27T00:00:00Z"

  resource_types {
    service   = false
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    filter  = false
    tag     = false
  }
}

resource "azurerm_service_plan" "consumption" {
  name                = "consumption-plan-email-labeling"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name = "Y1"  // Consumption plan requires SKU Y1 on Linux
  os_type  = "Linux"
}

resource "azurerm_linux_function_app" "alfa" {
  name                = "peps-email-labeling-app"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  service_plan_id            = azurerm_service_plan.consumption.id

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "python"
    "WEBSITE_RUN_FROM_PACKAGE" = "https://${azurerm_storage_account.sa.name}.blob.core.windows.net/${azurerm_storage_container.functions.name}/${azurerm_storage_blob.function_zip.name}?${data.azurerm_storage_account_sas.function_sas.sas}"
  }

  site_config {
    application_stack {
      python_version = "3.12"
    }
  }
}
