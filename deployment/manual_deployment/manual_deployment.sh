#!/bin/bash

# Get the directories
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
BUILT_ARTIFACT_DIR="${SCRIPT_DIR}/build_artifacts"

# Define artifact paths
ZIP_NAME="zip_deployment.zip"
ZIP_DIR="${BUILT_ARTIFACT_DIR}/zip_for_manual_deployment"
ZIP_PATH="${ZIP_DIR}/${ZIP_NAME}"
PYTHON_SITE_PKG_DIR="${BUILT_ARTIFACT_DIR}/.python_packages/lib/site-packages"

# Define Azure Function App details
RESOURCE_GROUP="email-labeling-rg"
FUNCTION_APP_NAME="peps-email-labeling-app"

# Ensure dir for holding the zip file exists
mkdir -p "${ZIP_DIR}"

# Clean up any existing zip file
rm -f "${ZIP_PATH}"

# Clean up previous Python packages
if [ -d "${PYTHON_SITE_PKG_DIR}" ]; then
    echo "🧹 Cleaning old Python packages..."
    rm -rf "${PYTHON_SITE_PKG_DIR}"/*
fi

# Check required files exist
REQUIRED_FILES=("function_app.py" "host.json" "requirements.txt")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${PROJECT_ROOT}/${file}" ]; then
        echo "❌ Error: Required file '${file}' not found in ${PROJECT_ROOT}"
        exit 1
    fi
done

# Install dependencies to .python_packages
echo "📦 Installing dependencies..."
pip install -r "${PROJECT_ROOT}/requirements.txt" --target="${PYTHON_SITE_PKG_DIR}"

# Change the working directory to the code directory for zipping
echo "📦 Creating deployment zip..."
cd "${PROJECT_ROOT}" > /dev/null  # Needed for correct relative paths in zip

# Create zip
# NOTE: When zipping files, often the parent directory structure is included. This can cause issues 
# when deploying to Azure Functions. When zipping, you want to be in the directory where the files
# are located, so that the zip contains only the files and not the entire directory structure.
zip -r "${ZIP_PATH}" \
    ./function_app.py \
    ./host.json \
    ./requirements.txt > /dev/null

# Add Python packages to the zip
cd "${BUILT_ARTIFACT_DIR}" > /dev/null
zip -r "${ZIP_PATH}" ./.python_packages > /dev/null

# Return to the original code directory
cd "${PROJECT_ROOT}"

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
