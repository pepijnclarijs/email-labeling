#!/bin/bash

# CONFIGURATION
APP_NAME="EmailLabelingApp"
REDIRECT_URI="http://localhost:8000/callback"
PERMISSION="Mail.Read"
API_ID="00000003-0000-0000-c000-000000000000" # Microsoft Graph API

echo "Creating app registration..."
appInfo=$(az ad app create \
  --display-name "$APP_NAME" \
  --sign-in-audience "AzureADandPersonalMicrosoftAccount" \
  --web-redirect-uris "$REDIRECT_URI" \
  --query "{appId: appId, objectId: id}" \
  --output json)

APP_ID=$(echo "$appInfo" | jq -r .appId)
APP_OBJECT_ID=$(echo "$appInfo" | jq -r .objectId)
echo "App created with appId: $APP_ID"

echo "Creating client secret..."
secretInfo=$(az ad app credential reset \
  --id "$APP_ID" \
  --append \
  --display-name "${APP_NAME}Secret" \
  --years 1 \
  --query "{clientSecret: password}" \
  --output json)

CLIENT_SECRET=$(echo "$secretInfo" | jq -r .clientSecret)
echo "Client secret created."

echo "Adding Mail.Read permission..."
az ad app permission add \
  --id "$APP_ID" \
  --api "$API_ID" \
  --api-permissions "$PERMISSION=Delegated"

echo "App registration complete."
echo
echo "🔑 Client ID: $APP_ID"
echo "🔐 Client Secret: $CLIENT_SECRET"
echo "🔁 Redirect URI: $REDIRECT_URI"
echo
echo "⚠️  Next step: Implement OAuth2 login flow in your frontend to request user consent."
