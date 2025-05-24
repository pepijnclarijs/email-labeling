#!/bin/bash

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define paths and Azure details
ZIP_NAME="zip_deployment.zip"
ZIP_DIR="${SCRIPT_DIR}/for_zip"
ZIP_PATH="${ZIP_DIR}/${ZIP_NAME}"

PYTHON_PKG_DIR="${SCRIPT_DIR}/.python_packages/lib/site-packages"

RESOURCE_GROUP="email-labeling-rg"
FUNCTION_APP_NAME="peps-email-labeling-app"

# Ensure for_zip directory exists
mkdir -p "${ZIP_DIR}"

# Clean up any existing zip file
rm -f "${ZIP_PATH}"

# Clean up previous Python packages
if [ -d "${PYTHON_PKG_DIR}" ]; then
    echo "🧹 Cleaning old Python packages..."
    rm -rf "${PYTHON_PKG_DIR}"/*
fi

# Check required files exist
REQUIRED_FILES=("function_app.py" "host.json" "requirements.txt")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${SCRIPT_DIR}/${file}" ]; then
        echo "❌ Error: Required file '${file}' not found in ${SCRIPT_DIR}"
        exit 1
    fi
done

# Install dependencies to .python_packages
echo "📦 Installing dependencies..."
pip install -r "${SCRIPT_DIR}/requirements.txt" --target="${PYTHON_PKG_DIR}"

# Create zip
cd "${SCRIPT_DIR}" || exit 1

echo "📦 Creating deployment zip..."
zip -r "${ZIP_PATH}" \
    function_app.py \
    host.json \
    requirements.txt \
    .python_packages/ > /dev/null

echo "✅ Zip created at ${ZIP_PATH}"

# Deploy using Azure CLI
echo "🚀 Deploying to Azure Function App '${FUNCTION_APP_NAME}' in resource group '${RESOURCE_GROUP}'..."
az functionapp deployment source config-zip \
    -g "${RESOURCE_GROUP}" \
    -n "${FUNCTION_APP_NAME}" \
    --src "${ZIP_PATH}"

if [ $? -eq 0 ]; then
    echo "✅ Deployment successful!"
else
    echo "❌ Deployment failed."
    exit 1
fi
