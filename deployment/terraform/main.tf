# Configures the Azure Resource Manager provider with the specified subscription
provider "azurerm" {
  features {}
  subscription_id = "578cb0e7-8d21-4544-9b28-1360e9a76b9b"
}

# Configures the Azure Active Directory provider (used for App Registration, etc.)
provider "azuread" {}

variable "google_api_key" {
  description = "Google API Key for accessing Google services"
  type        = string
  sensitive   = true
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "email-labeling-rg"
}

variable "storage_group_name" {
  description = "Name of the Azure Storage Group"
  type        = string
  default     = "emaillabelingstg"
}

variable "consumption_plan_name" {
  description = "Name of the Azure Consumption Plan for the Function App"
  type        = string
  default     = "consumption-plan-email-labeling"
}

variable "function_app_name" {
  description = "Name of the Azure Function App"
  type        = string
  default     = "email-labeling-app"
}

variable "app_insights_name" {
  description = "Name of the Azure Application Insights instance"
  type        = string
  default     = "email-labeling-appinsights"
}

variable "email_app_registration_name" {
  description = "Name of the Azure AD Application Registration for email labeling app"
  type        = string
  default     = "email-labeling-app-registration"
}

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
  name     = var.resource_group_name
  location = "westeurope"
}

# Creates a storage account for holding the Function App package
resource "azurerm_storage_account" "sa" {
  name                     = var.storage_group_name
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
  name                = var.consumption_plan_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Y1"
  os_type             = "Linux"
}

# Registers a new Azure AD Application (App Registration) for OAuth2 access to Microsoft Graph
resource "azuread_application" "email_app" {
  display_name     = var.email_app_registration_name
  sign_in_audience = "AzureADandPersonalMicrosoftAccount"

  api {
    mapped_claims_enabled          = true
    requested_access_token_version = 2

    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access example on behalf of the signed-in user."
      admin_consent_display_name = "Access example"
      enabled                    = true
      id                         = "891ab914-0b08-4ac9-8e38-b80b33d0e7c0" # Self generated UUID
      type                       = "User"
      user_consent_description   = "Allow the application to access example on your behalf."
      user_consent_display_name  = "Access example"
      value                      = "user_impersonation"
    }
  }

  web {
    redirect_uris = ["https://${var.function_app_name}.azurewebsites.net/api/auth-callback"]
    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }
}

# Create a client secret for the function app (used in OAuth login)
resource "azuread_application_password" "email_app_secret" {
  application_id = azuread_application.email_app.id
  display_name   = "${var.email_app_registration_name}-secret"
  end_date       = timeadd("2025-05-14T00:00:00Z", "8760h") # 1 year
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
    "ENABLE_ORYX_BUILD"              = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "WEBSITE_RUN_FROM_PACKAGE"       = "1"
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "AzureWebJobsFeatureFlags"       = "EnableWorkerIndexing"
    "CLIENT_ID"                      = azuread_application.email_app.client_id
    "CLIENT_SECRET"                  = azuread_application_password.email_app_secret.value
    "TENANT_ID"                      = data.azurerm_client_config.current.tenant_id
    "REDIRECT_URI"                   = "https://${var.function_app_name}.azurewebsites.net/api/auth-callback"
    "GEMINI_API_KEY"                 = var.google_api_key

    # Application Insights integration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.app_insights.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.app_insights.connection_string
  }

  site_config {
    application_stack {
      python_version = "3.12"
    }
    cors {
      allowed_origins = [
        "https://portal.azure.com"
      ]
    }
  }
}

# For logging
resource "azurerm_application_insights" "app_insights" {
  name                = var.app_insights_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}
