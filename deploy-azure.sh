#!/bin/bash
set -e

echo "Langflow Azure Deployment"
echo "========================="
echo ""

# -------------------------------------------------------------------
# Pre-flight checks
# -------------------------------------------------------------------

for cmd in az azd docker; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: '$cmd' is not installed."
        case "$cmd" in
            az)     echo "  Install: https://docs.microsoft.com/cli/azure/install-azure-cli" ;;
            azd)    echo "  Install: brew tap azure/azd && brew install azd" ;;
            docker) echo "  Install: https://docs.docker.com/get-docker/" ;;
        esac
        exit 1
    fi
done

# Make sure Docker daemon is running
if ! docker info &> /dev/null; then
    echo "Error: Docker is not running. Please start Docker Desktop."
    exit 1
fi

echo "[1/6] Pre-flight checks passed"

# -------------------------------------------------------------------
# Step 1 – Provision infrastructure (azd provision)
# -------------------------------------------------------------------

# Check if already provisioned by looking for ACR name in azd env
ACR_NAME=$(azd env get-values 2>/dev/null | grep "^AZURE_CONTAINER_REGISTRY_NAME=" | cut -d'=' -f2 | tr -d '"' || true)

if [ -z "$ACR_NAME" ]; then
    echo ""
    echo "[2/6] Provisioning Azure infrastructure..."
    azd provision
    echo ""
    # Re-read values after provision
    ACR_NAME=$(azd env get-values | grep "^AZURE_CONTAINER_REGISTRY_NAME=" | cut -d'=' -f2 | tr -d '"')
else
    echo "[2/6] Infrastructure already provisioned (ACR: $ACR_NAME)"
fi

# Read all azd outputs
ACR_ENDPOINT=$(azd env get-values | grep "^AZURE_CONTAINER_REGISTRY_ENDPOINT=" | cut -d'=' -f2 | tr -d '"')
APP_NAME=$(azd env get-values | grep "^WEB_NAME=" | cut -d'=' -f2 | tr -d '"')
RESOURCE_GROUP=$(azd env get-values | grep "^AZURE_RESOURCE_GROUP=" | cut -d'=' -f2 | tr -d '"')
WEB_URI=$(azd env get-values | grep "^WEB_URI=" | cut -d'=' -f2 | tr -d '"')

if [ -z "$ACR_ENDPOINT" ] || [ -z "$APP_NAME" ] || [ -z "$RESOURCE_GROUP" ]; then
    echo "Error: Could not read provisioned resource names from azd environment."
    echo "  ACR_ENDPOINT=$ACR_ENDPOINT"
    echo "  APP_NAME=$APP_NAME"
    echo "  RESOURCE_GROUP=$RESOURCE_GROUP"
    echo ""
    echo "Try running: azd provision"
    exit 1
fi

# -------------------------------------------------------------------
# Step 2 – Log in to ACR
# -------------------------------------------------------------------

echo ""
echo "[3/6] Logging in to Container Registry: $ACR_NAME"
az acr login --name "$ACR_NAME"

# -------------------------------------------------------------------
# Step 3 – Build Docker image from local source
# -------------------------------------------------------------------

IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
FULL_IMAGE="$ACR_ENDPOINT/langflow:$IMAGE_TAG"
LATEST_IMAGE="$ACR_ENDPOINT/langflow:latest"

echo ""
echo "[4/6] Building Docker image from local source code..."
echo "      Image: $FULL_IMAGE"
echo "      This may take 10-15 minutes on first build."
echo ""

docker build \
    -t "$FULL_IMAGE" \
    -t "$LATEST_IMAGE" \
    -f Dockerfile .

# -------------------------------------------------------------------
# Step 4 – Push to ACR
# -------------------------------------------------------------------

echo ""
echo "[5/6] Pushing image to Azure Container Registry..."
docker push "$FULL_IMAGE"
docker push "$LATEST_IMAGE"

# -------------------------------------------------------------------
# Step 5 – Update App Service to use the new image
# -------------------------------------------------------------------

echo ""
echo "[6/6] Updating App Service: $APP_NAME"

az webapp config container set \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --docker-custom-image-name "$FULL_IMAGE" \
    --docker-registry-server-url "https://$ACR_ENDPOINT"

az webapp restart \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP"

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------

echo ""
echo "========================================"
echo "  Deployment complete!"
echo "========================================"
echo ""
echo "  URL:            $WEB_URI"
echo "  App Service:    $APP_NAME"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Image:          $FULL_IMAGE"
echo ""
echo "Useful commands:"
echo "  View logs:      az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP"
echo "  Redeploy:       ./deploy-azure.sh"
echo "  Tear down:      azd down"
echo ""
