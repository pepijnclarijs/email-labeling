# Configures the Azure Resource Manager provider with the specified subscription
provider "azurerm" {
  features {}
  subscription_id = "578cb0e7-8d21-4544-9b28-1360e9a76b9b"
}

# Configures the Azure Active Directory provider (used for App Registration, etc.)
provider "azuread" {}

# Retrieves information about the currently authenticated Azure client
# Used for tenant ID and object ID of the user/service principal running Terraform
data "azurerm_client_config" "current" {}

# Retrieve well-known Microsoft application IDs
data "azuread_application_published_app_ids" "well_known" {}

# Reference the Microsoft Graph service principal using its application ID
resource "azuread_service_principal" "msgraph" {
  client_id    = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
  use_existing = true
}

# Creates a resource group to hold all other resources
resource "azurerm_resource_group" "rg" {
  name     = "email-labeling-rg"
  location = "westeurope"
}

# Creates a storage account for holding the Function App package
resource "azurerm_storage_account" "sa" {
  name                     = "emaillabelingstg"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Creates a blob container to hold the deployment package for the Function App
resource "azurerm_storage_container" "functions" {
  name                  = "functions"
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = "private"
}

# Uploads a placeholder zip package to the storage container
resource "azurerm_storage_blob" "function_zip" {
  name                   = "function.zip"
  storage_account_name   = azurerm_storage_account.sa.name
  storage_container_name = azurerm_storage_container.functions.name
  type                   = "Block"
  source                 = "./placeholder_file.zip"
}

# Generates a Shared Access Signature (SAS) token for the uploaded blob
# This is used to let the Function App access the zip package securely
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

# Defines the serverless hosting plan for the Function App. Y1 is pay as you go. Cheapest option
resource "azurerm_service_plan" "consumption" {
  name                = "consumption-plan-email-labeling"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Y1"
  os_type             = "Linux"
}

# Deploys the Azure Linux Function App
resource "azurerm_linux_function_app" "alfa" {
  name                       = "peps-email-labeling-app"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
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

# Registers a new Azure AD Application (App Registration) for OAuth2 access to Microsoft Graph
resource "azuread_application" "email_app" {
  display_name = "EmailLabelingApp"

  web {
    redirect_uris = ["http://localhost:8000/callback"]
  }

  # Requests delegated Mail.Read permission from Microsoft Graph
  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

    resource_access {
      id   = azuread_service_principal.msgraph.app_role_ids["Mail.Read"]
      type = "Scope"
    }
  }
}

# Creates a client secret for the App Registration
resource "azuread_application_password" "app_secret" {
  application_id = azuread_application.email_app.id
  display_name   = "EmailLabelingAppSecret"
  end_date       = timeadd("2025-05-13T16:22:36Z", "8760h") # 1 year
}

# Creates a Key Vault to securely store secrets (e.g., client ID and client secret)
resource "azurerm_key_vault" "kv" {
  name                       = "emailLabelingKv"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

# Stores the client ID in Key Vault
resource "azurerm_key_vault_secret" "client_id" {
  name         = "ClientIdEmailLabelingApp"
  value        = azuread_application.email_app.id
  key_vault_id = azurerm_key_vault.kv.id
}

# Stores the client secret in Key Vault
resource "azurerm_key_vault_secret" "client_secret" {
  name         = "ClientSecretEmailLabelingApp"
  value        = azuread_application_password.app_secret.value
  key_vault_id = azurerm_key_vault.kv.id
}

# Grants the currently authenticated user/service principal permission to manage secrets in the Key Vault
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Restore", "Purge"]
}
