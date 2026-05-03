#!/usr/bin/env bash
#
# Deploy Langflow to Azure App Service (Web App for Containers) using
# the repo's docker/build_and_push.Dockerfile. Mirrors the existing
# render.yaml setup (Sweden Central region) with a persistent
# /app/data mount and the LANGFLOW_* env vars.
#
# Usage:
#   ./deploy_langflow_azure.sh
#
# Override defaults via environment variables, e.g.:
#   ACR_NAME=reblaiacr WEBAPP_NAME=mylangflow ./deploy_langflow_azure.sh
#
# Requires: az CLI logged in (`az login`) with a default subscription set.

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-rebl-ai}"
LOCATION="${LOCATION:-swedencentral}"
ACR_NAME="${ACR_NAME:-reblaiacr}" # Globally unique
APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-rebl-langflow-plan}"
WEBAPP_NAME="${WEBAPP_NAME:-rockon-langflow-dev}"
APP_SERVICE_SKU="${APP_SERVICE_SKU:-B2}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-reblaidata}" # Globally unique
FILE_SHARE_NAME="${FILE_SHARE_NAME:-rebl-langflow-data}"
FILE_SHARE_QUOTA_GIB="${FILE_SHARE_QUOTA_GIB:-10}"
IMAGE_NAME="${IMAGE_NAME:-rebl-langflow}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-./docker/build_and_push.Dockerfile}"
IMAGE_PLATFORM="${IMAGE_PLATFORM:-linux/amd64}"
LANGFLOW_PORT="${LANGFLOW_PORT:-10000}"
LANGFLOW_LOG_LEVEL="${LANGFLOW_LOG_LEVEL:-INFO}"
LANGFLOW_DATABASE_URL="${LANGFLOW_DATABASE_URL:-sqlite:////app/data/.cache/langflow/langflow.db}"
LANGFLOW_AUTO_LOGIN="${LANGFLOW_AUTO_LOGIN:-false}"
LANGFLOW_SSRF_PROTECTION_ENABLED="${LANGFLOW_SSRF_PROTECTION_ENABLED:-true}"
LANGFLOW_ENABLE_SUPERUSER_CLI="${LANGFLOW_ENABLE_SUPERUSER_CLI:-false}"
LANGFLOW_STORE_ENVIRONMENT_VARIABLES="${LANGFLOW_STORE_ENVIRONMENT_VARIABLES:-true}"
LANGFLOW_API_KEY_SOURCE="${LANGFLOW_API_KEY_SOURCE:-db}"
LANGFLOW_SUPERUSER="${LANGFLOW_SUPERUSER:-admin}"
LANGFLOW_SUPERUSER_PASSWORD="${LANGFLOW_SUPERUSER_PASSWORD:-Rockon123}"
HEALTH_CHECK_PATH="${HEALTH_CHECK_PATH:-/health_check}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if ! command -v az >/dev/null 2>&1; then
  echo "az CLI not found. Install from https://learn.microsoft.com/cli/azure/install-azure-cli" >&2
  exit 1
fi

echo "==> Step 1: create resource group, ACR, App Service plan"
if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none
fi

if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az acr create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ACR_NAME" \
    --sku Basic \
    --admin-enabled true \
    -o none
fi

if ! az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az appservice plan create \
    --name "$APP_SERVICE_PLAN" \
    --resource-group "$RESOURCE_GROUP" \
    --is-linux \
    --sku "$APP_SERVICE_SKU" \
    -o none
fi

echo "==> Step 2: build and push image to ACR (using $DOCKERFILE_PATH)"
# The Dockerfile uses BuildKit-only syntax (RUN --mount=type=cache, # syntax=docker/dockerfile:1),
# which `az acr build` does not enable. Build locally with docker buildx and push instead.
# Requires Docker Desktop / a docker daemon running locally.
if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI not found. Install Docker Desktop to build the image with BuildKit." >&2
  exit 1
fi
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

az acr login --name "$ACR_NAME"
docker buildx build \
  --platform "$IMAGE_PLATFORM" \
  --file "$DOCKERFILE_PATH" \
  --tag "$FULL_IMAGE" \
  --push \
  .

echo "==> Step 3: create / update Web App pointing at the ACR image"
ACR_PASSWORD="$(az acr credential show --name "$ACR_NAME" --query 'passwords[0].value' -o tsv)"

if ! az webapp show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az webapp create \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --name "$WEBAPP_NAME" \
    --deployment-container-image-name "$FULL_IMAGE" \
    -o none
else
  az webapp config container set \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --docker-custom-image-name "$FULL_IMAGE" \
    --docker-registry-server-url "https://${ACR_LOGIN_SERVER}" \
    --docker-registry-server-user "$ACR_NAME" \
    --docker-registry-server-password "$ACR_PASSWORD" \
    -o none
fi

az webapp config appsettings set \
  --name "$WEBAPP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    "DOCKER_REGISTRY_SERVER_URL=https://${ACR_LOGIN_SERVER}" \
    "DOCKER_REGISTRY_SERVER_USERNAME=${ACR_NAME}" \
    "DOCKER_REGISTRY_SERVER_PASSWORD=${ACR_PASSWORD}" \
  -o none

echo "==> Step 4: configure Langflow env vars and listening port"
az webapp config appsettings set \
  --name "$WEBAPP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    "WEBSITES_PORT=${LANGFLOW_PORT}" \
    "LANGFLOW_DATABASE_URL=${LANGFLOW_DATABASE_URL}" \
    "LANGFLOW_HOST=0.0.0.0" \
    "LANGFLOW_PORT=${LANGFLOW_PORT}" \
    "LANGFLOW_LOG_LEVEL=${LANGFLOW_LOG_LEVEL}" \
    "LANGFLOW_AUTO_LOGIN=${LANGFLOW_AUTO_LOGIN}" \
    "LANGFLOW_SSRF_PROTECTION_ENABLED=${LANGFLOW_SSRF_PROTECTION_ENABLED}" \
    "LANGFLOW_ENABLE_SUPERUSER_CLI=${LANGFLOW_ENABLE_SUPERUSER_CLI}" \
    "LANGFLOW_STORE_ENVIRONMENT_VARIABLES=${LANGFLOW_STORE_ENVIRONMENT_VARIABLES}" \
    "LANGFLOW_API_KEY_SOURCE=${LANGFLOW_API_KEY_SOURCE}" \
    "LANGFLOW_SUPERUSER=${LANGFLOW_SUPERUSER}" \
    "LANGFLOW_SUPERUSER_PASSWORD=${LANGFLOW_SUPERUSER_PASSWORD}" \
  -o none

az webapp config set \
  --name "$WEBAPP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --generic-configurations "{\"healthCheckPath\": \"${HEALTH_CHECK_PATH}\"}" \
  -o none

echo "==> Step 5: provision persistent storage and mount at /app/data"
if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    -o none
fi

STORAGE_KEY="$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query '[0].value' -o tsv)"

share_exists="$(az storage share exists \
  --name "$FILE_SHARE_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$STORAGE_KEY" \
  --query exists -o tsv)"
if [[ "$share_exists" != "true" ]]; then
  az storage share create \
    --name "$FILE_SHARE_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --quota "$FILE_SHARE_QUOTA_GIB" \
    -o none
else
  az storage share update \
    --name "$FILE_SHARE_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --quota "$FILE_SHARE_QUOTA_GIB" \
    -o none
fi

mount_exists="$(az webapp config storage-account list \
  --name "$WEBAPP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?name=='${FILE_SHARE_NAME}'] | length(@)" -o tsv)"
if [[ "$mount_exists" == "0" ]]; then
  az webapp config storage-account add \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --custom-id "$FILE_SHARE_NAME" \
    --storage-type AzureFiles \
    --account-name "$STORAGE_ACCOUNT" \
    --share-name "$FILE_SHARE_NAME" \
    --access-key "$STORAGE_KEY" \
    --mount-path /app/data \
    -o none
fi

az webapp restart --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" -o none

echo
echo "Deployment complete."
echo "URL: https://${WEBAPP_NAME}.azurewebsites.net"
echo "Health check: https://${WEBAPP_NAME}.azurewebsites.net${HEALTH_CHECK_PATH}"
