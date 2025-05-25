# --- For CI/CD with GitHub --- #

# Define required GitHub-related variables
variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token with repo and admin:repo_hook permissions"
}

variable "github_owner" {
  type        = string
  description = "GitHub username or organization"
}

variable "github_repo" {
  type        = string
  description = "Name of the GitHub repository where secrets will be stored"
}

# GitHub provider for managing repo secrets
provider "github" {
  token = var.github_token # Needed for letting terraform manage GitHub secrets
  owner = var.github_owner
}

# App Registration for GitHub Actions to deploy the Function App
resource "azuread_application" "github_actions_app" {
  display_name = "GitHubActionsDeployer"
}

# App Secret for GitHub Actions
resource "azuread_application_password" "github_actions_app_secret" {
  application_id = azuread_application.github_actions_app.id
  display_name   = "GitHubActionsAppSecret"
  end_date       = timeadd("2025-05-13T00:00:00Z", "8760h") # 1 year
}

# Service Principal for github actions
resource "azuread_service_principal" "github_actions_sp" {
  client_id = azuread_application.github_actions_app.client_id
}

# Assign function app contributor role to Service Principal for zip deployment
resource "azurerm_role_assignment" "github_actions_function_app_contributor" {
  scope                = azurerm_linux_function_app.alfa.id # Must be set directly on the Function App, not the resource group
  role_definition_name = "Contributor"                      # or "Website Contributor" if you want finer granularity
  principal_id         = azuread_service_principal.github_actions_sp.object_id
}

# Assign Storage Blob Data Contributor role to Service Principal
resource "azurerm_role_assignment" "github_actions_blob_data_contributor" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_actions_sp.object_id
}

# Needed for zip deployment using azure cli
resource "azurerm_role_assignment" "github_actions_website_contributor" {
  scope                = azurerm_linux_function_app.alfa.id
  role_definition_name = "Website Contributor"
  principal_id         = azuread_service_principal.github_actions_sp.object_id
}

# Store all credentials in a single JSON-formatted GitHub secret
resource "github_actions_secret" "azure_credentials_json" {
  repository  = var.github_repo
  secret_name = "AZURE_CREDENTIALS"
  plaintext_value = jsonencode({
    clientId       = azuread_application.github_actions_app.client_id
    clientSecret   = azuread_application_password.github_actions_app_secret.value
    tenantId       = data.azurerm_client_config.current.tenant_id
    subscriptionId = data.azurerm_client_config.current.subscription_id
  })
}
