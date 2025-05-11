#!/bin/bash

# Define variables
APP_NAME="my-github-app"                  # Change this to your preferred app name
SUBSCRIPTION_ID=$(az account show --query id --output tsv)  # Fetch the current subscription ID
GITHUB_REPO="your-username/your-repo"     # Set your GitHub repo (if not using the current directory repo)

# Create Service Principal with necessary role and fetch credentials
SP_CREDS=$(az ad sp create-for-rbac --name "$APP_NAME" --role contributor --scopes /subscriptions/"$SUBSCRIPTION_ID" --sdk-auth)

# Extract values from the credentials
CLIENT_ID=$(echo $SP_CREDS | jq -r .appId)
CLIENT_SECRET=$(echo $SP_CREDS | jq -r .password)
TENANT_ID=$(echo $SP_CREDS | jq -r .tenant)
SUBSCRIPTION_ID=$(echo $SP_CREDS | jq -r .subscriptionId)

# Format the credentials as JSON for GitHub
CREDS_JSON=$(cat <<EOF
{
  "clientId": "$CLIENT_ID",
  "clientSecret": "$CLIENT_SECRET",
  "tenantId": "$TENANT_ID",
  "subscriptionId": "$SUBSCRIPTION_ID",
  "resourceManagerEndpointUrl": "https://management.azure.com/"
}
EOF
)

# Save the credentials as a GitHub Secret
echo "$CREDS_JSON" | gh secret set AZURE_CREDENTIALS --repo "$GITHUB_REPO"

echo "GitHub secret 'AZURE_CREDENTIALS' has been created and stored successfully!"
