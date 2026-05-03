# Deploy Langflow to Azure

Deploys the fork to **Azure App Service (Web App for Containers)** using the
existing [docker/build_and_push.Dockerfile](../../docker/build_and_push.Dockerfile).
Functionally equivalent to the [render.yaml](../../render.yaml) setup:
Sweden Central region, port 10000, SQLite at `/app/data/.cache/langflow/langflow.db`,
persistent `/app/data` mount.

## Flow

```
GitHub repo → az acr build → Azure Container Registry → App Service (Web App for Containers)
```

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- `az login` and a default subscription set (`az account set --subscription <id>`)
- Local Docker daemon (Docker Desktop) — the Dockerfile uses BuildKit-only syntax
  (`RUN --mount=type=cache`), so the build runs locally via `docker buildx` and pushes
  the result to ACR. `az acr build` does not enable BuildKit and will fail on this Dockerfile.

## Deploy

From the repo root:

```bash
./scripts/azure/deploy_langflow_azure.sh
```

All settings have defaults; override via env vars when names need to be unique:

```bash
ACR_NAME=reblaiacr \
WEBAPP_NAME=mylangflow \
STORAGE_ACCOUNT=reblaidata \
./scripts/azure/deploy_langflow_azure.sh
```

| Variable | Default |
|---|---|
| `RESOURCE_GROUP` | `rg-rebl-ai` |
| `LOCATION` | `swedencentral` |
| `ACR_NAME` | `reblaiacr` (must be **globally** unique, alphanumeric) |
| `APP_SERVICE_PLAN` | `langflow-plan` |
| `APP_SERVICE_SKU` | `B2` |
| `WEBAPP_NAME` | `rockon-langflow-app` (becomes `<name>.azurewebsites.net`) |
| `STORAGE_ACCOUNT` | `reblaidata` (must be **globally** unique) |
| `FILE_SHARE_NAME` | `rebl-langflow-data` |
| `FILE_SHARE_QUOTA_GIB` | `10` (cap on the Azure Files share; raise non-destructively, lowering below current usage fails) |
| `IMAGE_NAME` / `IMAGE_TAG` | `langflow` / `latest` |
| `IMAGE_PLATFORM` | `linux/amd64` (don't change unless you switch to an ARM App Service plan) |
| `LANGFLOW_PORT` | `10000` |
| `LANGFLOW_LOG_LEVEL` | `INFO` |
| `LANGFLOW_DATABASE_URL` | `sqlite:////app/data/.cache/langflow/langflow.db` |
| `LANGFLOW_AUTO_LOGIN` | `false` |
| `LANGFLOW_SSRF_PROTECTION_ENABLED` | `true` |
| `LANGFLOW_ENABLE_SUPERUSER_CLI` | `false` |
| `LANGFLOW_STORE_ENVIRONMENT_VARIABLES` | `true` |
| `LANGFLOW_API_KEY_SOURCE` | `db` |
| `LANGFLOW_SUPERUSER` | `admin` |
| `LANGFLOW_SUPERUSER_PASSWORD` | `Rockon123` (override per-deploy; do not rely on the default in production) |
| `HEALTH_CHECK_PATH` | `/health_check` |

The script is idempotent — re-running it rebuilds the image and updates the Web
App in place. The Azure Files mount at `/app/data` (which holds the SQLite DB
and uploaded files) survives `az webapp restart`, container redeploys, and
re-runs of this script; data is only lost if the storage account / file share
is deleted.

ref. for more env details https://docs.langflow.org/environment-variables

### Forcing a fresh deploy after code changes

`docker buildx build --push` always rebuilds, but App Service caches the
`:latest` digest. Cleanest option is to push a unique tag per deploy:

```bash
IMAGE_TAG=$(git rev-parse --short HEAD) ./scripts/azure/deploy_langflow_azure.sh
```

The script's container-set step will repoint the Web App at the new tag and
restart it.

## Render → Azure mapping

| Render config | Azure equivalent |
|---|---|
| `runtime: docker` + `dockerfilePath` | `docker buildx build --push` to ACR |
| `repo` / `branch` | GitHub Actions or `az acr build` from local |
| `plan: standard` | App Service Plan `--sku B2` (or `S2` for more power) |
| `region: swedencentral` | `--location swedencentral` |
| `healthCheckPath: /health_check` | `az webapp config set --generic-configurations '{"healthCheckPath": "..."}'` |
| `envVars` | `az webapp config appsettings set` |
| `disk.mountPath` | Azure Files share via `az webapp config storage-account add` |
