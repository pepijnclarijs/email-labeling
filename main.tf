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

  lifecycle {
    ignore_changes = [
      source,
      content_md5,
      content_type,
      metadata
    ]
  }
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

variable "function_app_name" {
  default = "peps-email-labeling-app"
}

# Deploys the Azure Linux Function App
resource "azurerm_linux_function_app" "alfa" {
  name                       = var.function_app_name
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  service_plan_id            = azurerm_service_plan.consumption.id

  # Make a system assigned managed identity available to the Function App
  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"      = "python"
    "WEBSITE_RUN_FROM_PACKAGE"      = "https://${azurerm_storage_account.sa.name}.blob.core.windows.net/${azurerm_storage_container.functions.name}/${azurerm_storage_blob.function_zip.name}?${data.azurerm_storage_account_sas.function_sas.sas}"
    "CLIENT_ID"                    = azuread_application.email_app.client_id
    "CLIENT_SECRET"                = azuread_application_password.email_app_secret.value
    "TENANT_ID"                    = data.azurerm_client_config.current.tenant_id
    "REDIRECT_URI"                 = "https://${var.function_app_name}.azurewebsites.net/api/azure_app"  
  }

  site_config {
    application_stack {
      python_version = "3.12"
    }
  }
}

# Create a client secret for the EmailLabelingApp (used in OAuth login)
resource "azuread_application_password" "email_app_secret" {
  application_id = azuread_application.email_app.id
  display_name   = "EmailLabelingAppSecret"
  end_date       = timeadd("2025-05-14T00:00:00Z", "8760h") # 1 year
}


# Registers a new Azure AD Application (App Registration) for OAuth2 access to Microsoft Graph
resource "azuread_application" "email_app" {
  display_name = "EmailLabelingApp"

  web {
    redirect_uris = ["https://${var.function_app_name}.azurewebsites.net/api/azure_app"]  # TODO: This name is actually dependent on the folder name of the function app. Also, this redirect URI must be exactly the same as the ones used in the environment variables of the function app.
    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }

  # Requests delegated Mail.Read permission from Microsoft Graph
  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

    resource_access {
      id   = azuread_service_principal.msgraph.app_role_ids["Mail.Read"]
      type = "Scope"
    }

    resource_access {
      id   = azuread_service_principal.msgraph.app_role_ids["Mail.ReadWrite"]
      type = "Scope"
    }

    resource_access {
      id   = azuread_service_principal.msgraph.app_role_ids["MailboxSettings.Read"]
      type = "Scope"
    }
  }
}

# --- For CI/CD with GitHub --- #

# GitHub Actions App Registration
resource "azuread_application" "github_actions_app" {
  display_name = "GitHubActionsEmailDeployer"
}

# App Secret for GitHub Actions
resource "azuread_application_password" "github_actions_secret" {
  application_id = azuread_application.github_actions_app.id
  display_name   = "GitHubActionsSecret"
  end_date       = timeadd("2025-05-13T00:00:00Z", "8760h") # 1 year
}

# Service Principal associated with the App Registration
resource "azuread_service_principal" "github_actions_sp" {
  client_id = azuread_application.github_actions_app.client_id
}

# Assign Storage Blob Data Contributor role to Service Principal
resource "azurerm_role_assignment" "github_actions_blob_data_contributor" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_actions_sp.object_id
}

# Outputs for GitHub Actions secrets
output "github_actions_credentials_json" {
  value = jsonencode({
    clientId                   = azuread_application.github_actions_app.client_id
    clientSecret               = azuread_application_password.github_actions_secret.value
    tenantId                   = data.azurerm_client_config.current.tenant_id
    subscriptionId             = data.azurerm_client_config.current.subscription_id
    resourceManagerEndpointUrl = "https://management.azure.com/"
  })
  sensitive = true
}