#!/bin/bash
# =============================================================================
# deploy-azure.sh  —  Deploy Langflow to Azure
#
# Architecture:
#   Backend  → Azure App Service (Docker container via ACR)
#   Frontend → Azure Static Web Apps (React SPA on CDN)
#
# Usage:
#   ./deploy-azure.sh              # Full deploy (provision + backend + frontend)
#   ./deploy-azure.sh --provision  # Provision/update Azure infrastructure only
#   ./deploy-azure.sh --backend    # Build + deploy backend Docker image only
#   ./deploy-azure.sh --frontend   # Build + deploy React frontend only (~1 min)
# =============================================================================
set -euo pipefail

# --- Parse flags -------------------------------------------------------------
DO_PROVISION=false
DO_BACKEND=false
DO_FRONTEND=false

if [[ $# -eq 0 ]]; then
  DO_PROVISION=true; DO_BACKEND=true; DO_FRONTEND=true
fi

for arg in "$@"; do
  case $arg in
    --provision) DO_PROVISION=true ;;
    --backend)   DO_BACKEND=true ;;
    --frontend)  DO_FRONTEND=true ;;
    *) echo "Unknown flag: $arg"; echo "Usage: $0 [--provision] [--backend] [--frontend]"; exit 1 ;;
  esac
done

# --- Colours -----------------------------------------------------------------
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║      Langflow  →  Azure Deployment       ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Backend  : App Service (Docker container)"
echo "  Frontend : Static Web Apps (React CDN)"
echo ""

# =============================================================================
# PRE-FLIGHT
# =============================================================================
step "Checking tools..."

for cmd in az azd; do
  command -v "$cmd" &>/dev/null || fail "'$cmd' not found.
  az  → https://docs.microsoft.com/cli/azure/install-azure-cli
  azd → brew tap azure/azd && brew install azd"
done

if $DO_BACKEND; then
  command -v docker &>/dev/null || fail "'docker' not found → https://docs.docker.com/get-docker/"
  docker info &>/dev/null       || fail "Docker is not running. Start Docker Desktop and try again."
fi

if $DO_FRONTEND; then
  command -v node &>/dev/null || fail "'node' not found → https://nodejs.org"
  command -v npm  &>/dev/null || fail "'npm' not found"
fi

ok "All tools available"

# =============================================================================
# PROVISION  (azd provision — idempotent: creates or updates infrastructure)
# =============================================================================
if $DO_PROVISION; then
  step "Provisioning Azure infrastructure..."
  azd provision
  ok "Infrastructure ready"
fi

# --- Helper: read a value from azd environment -------------------------------
get_env() { azd env get-values 2>/dev/null | grep "^${1}=" | cut -d'=' -f2- | tr -d '"'; }

step "Reading Azure resource names..."

ACR_NAME=$(get_env  AZURE_CONTAINER_REGISTRY_NAME)
ACR_ENDPOINT=$(get_env AZURE_CONTAINER_REGISTRY_ENDPOINT)
APP_NAME=$(get_env  WEB_NAME)
RESOURCE_GROUP=$(get_env AZURE_RESOURCE_GROUP)
WEB_URI=$(get_env   WEB_URI)
SWA_NAME=$(get_env  FRONTEND_NAME)
SWA_URI=$(get_env   FRONTEND_URI)
# Token fetched directly from Azure (not stored in azd env as it's a secret)
SWA_TOKEN=$(az staticwebapp secrets list --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.apiKey" -o tsv 2>/dev/null || true)

[[ -n "$ACR_NAME" && -n "$APP_NAME" && -n "$RESOURCE_GROUP" ]] || \
  fail "Could not read resource names from azd environment.
  Run './deploy-azure.sh --provision' first."

ok "Backend : $APP_NAME  |  Frontend : $SWA_NAME"

# =============================================================================
# BACKEND  (Docker: build locally → push to ACR → update App Service)
# =============================================================================
if $DO_BACKEND; then

  step "Logging in to Azure Container Registry: $ACR_NAME"
  az acr login --name "$ACR_NAME"

  IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
  FULL_IMAGE="$ACR_ENDPOINT/langflow:$IMAGE_TAG"
  LATEST_IMAGE="$ACR_ENDPOINT/langflow:latest"

  step "Building Docker image from local source code..."
  echo "  Tag    : $FULL_IMAGE"
  echo "  Note   : First build ~10-15 min; subsequent builds are faster."
  echo ""

  docker build \
    -t "$FULL_IMAGE" \
    -t "$LATEST_IMAGE" \
    -f Dockerfile .

  step "Pushing image to ACR..."
  docker push "$FULL_IMAGE"
  docker push "$LATEST_IMAGE"
  ok "Image pushed"

  step "Updating App Service to use the new image..."
  az webapp config container set \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --docker-custom-image-name "$FULL_IMAGE" \
    --docker-registry-server-url "https://$ACR_ENDPOINT" \
    --output none

  az webapp restart \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --output none

  ok "Backend deployed → $WEB_URI"
fi

# =============================================================================
# FRONTEND  (Build React → deploy to Azure Static Web Apps CDN)
# =============================================================================
if $DO_FRONTEND; then

  step "Building React frontend..."
  echo "  API calls use relative paths (/api/v1/*)"
  echo "  SWA linked backend proxies them to the App Service automatically"
  echo ""

  pushd src/frontend > /dev/null

  # Install node_modules if missing (e.g. fresh checkout)
  [[ -d node_modules ]] || npm ci

  # Build — leave BACKEND_URL empty so frontend uses relative /api/* paths
  # that get proxied by SWA linked backend to the App Service
  BACKEND_URL="" npm run build

  ok "Frontend built (src/frontend/build/)"

  step "Deploying to Azure Static Web Apps: $SWA_NAME"
  npx --yes @azure/static-web-apps-cli deploy \
    --app-location build \
    --deployment-token "$SWA_TOKEN" \
    --env production

  popd > /dev/null
  ok "Frontend deployed → $SWA_URI"
fi

# =============================================================================
# DONE
# =============================================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                     Deployment Complete!                      ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
printf "║  🌐 App URL  : %-47s ║\n" "$SWA_URI"
printf "║  ⚙  Backend  : %-47s ║\n" "$WEB_URI"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Change frontend?  ./deploy-azure.sh --frontend    (~2 min)"
echo "  Change backend?   ./deploy-azure.sh --backend     (~10-15 min)"
echo "  Change infra?     ./deploy-azure.sh --provision"
echo "  View backend logs: az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP"
echo "  Tear down all:    azd down"
echo ""
