# Langflow Azure Deployment

This directory contains Azure deployment configuration for Langflow using Azure Developer CLI (azd).

**🎯 This deployment builds from your local source code**, including any frontend or backend changes you've made.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) - `az` command
- [Azure Developer CLI](https://aka.ms/azd-install) - `azd` command
- [Docker](https://docs.docker.com/get-docker/) - For local image builds
- An Azure subscription
- An existing PostgreSQL server (connection string required)

## What Gets Deployed

When you run the deployment:
1. ✅ **Builds Docker image from your local code** (both frontend and backend)
2. ✅ Creates Azure Container Registry (ACR) to store your custom image
3. ✅ Pushes your built image to ACR
4. ✅ Creates App Service Plan (Linux)
5. ✅ Creates App Service (Web App for Containers)
6. ✅ Configures managed identity for secure ACR access
7. ✅ Deploys your custom Langflow application

## Quick Start

### 1. Install Azure Developer CLI

```bash
# macOS
brew tap azure/azd && brew install azd

# Windows
winget install microsoft.azd

# Linux
curl -fsSL https://aka.ms/install-azd.sh | bash
```

### 2. Login to Azure

```bash
azd auth login
az login
```

### 3. Create Environment File

Create a `.env` file in the project root with your configuration:

```bash
# Copy the example file
cp .azure/.env.example .env

# Edit with your values
# Required:
LANGFLOW_DATABASE_URL="postgresql://username:password@your-postgres-server:5432/langflow?sslmode=require"
LANGFLOW_SUPERUSER="admin"
LANGFLOW_SUPERUSER_PASSWORD="your-secure-password"

# Optional (defaults shown):
LANGFLOW_CONFIG_DIR="/home/langflow-data"
LANGFLOW_LOG_LEVEL="INFO"
APP_SERVICE_PLAN_SKU="B2"
DOCKER_IMAGE="langflowai/langflow:latest"
```

### 4. Initialize and Deploy

```bash
# Initialize azd (first time only)
azd init

# Choose environment name (e.g., "dev" or "prod")
# Choose Azure subscription
# Choose Azure region (e.g., "eastus", "westus2")

# Provision infrastructure and deploy
azd up
```

That's it! The deployment will:
1. Create a resource group
2. Create an App Service Plan (Linux)
3. Create an App Service (Web App for Containers)
4. Deploy the Langflow Docker container
5. Configure all environment variables

## Manual Deployment Steps

If you prefer to do it step by step:

```bash
# 1. Provision infrastructure only
azd provision

# 2. Deploy the application only
azd deploy

# 3. View the deployment
azd show
```

## Configuration

### Environment Variables

All configuration is done through environment variables. Create a `.env` file:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LANGFLOW_DATABASE_URL` | Yes | - | PostgreSQL connection string |
| `LANGFLOW_SUPERUSER` | Yes | - | Admin username for Langflow |
| `LANGFLOW_SUPERUSER_PASSWORD` | Yes | - | Admin password for Langflow |
| `LANGFLOW_CONFIG_DIR` | No | `/home/langflow-data` | Config directory path |
| `LANGFLOW_LOG_LEVEL` | No | `INFO` | Log level (DEBUG, INFO, WARNING, ERROR) |
| `APP_SERVICE_PLAN_SKU` | No | `B2` | App Service Plan SKU (B1, B2, S1, etc.) |

**Note:** The deployment builds from your local source code automatically. No need to specify a Docker image.

### PostgreSQL Connection String Format

```
postgresql://username:password@hostname:port/database?sslmode=require
```

Examples:
- Azure PostgreSQL: `postgresql://admin:password@myserver.postgres.database.azure.com:5432/langflow?sslmode=require`
- External server: `postgresql://user:pass@example.com:5432/langflow`

## App Service Plans

Choose the right SKU for your needs:

| SKU | Cores | RAM | Monthly Cost* | Use Case |
|-----|-------|-----|--------------|----------|
| B1 | 1 | 1.75 GB | ~$13 | Testing, very light use |
| **B2** | 2 | 3.5 GB | ~$55 | **Recommended for production** |
| B3 | 4 | 7 GB | ~$110 | High load |
| S1 | 1 | 1.75 GB | ~$70 | Production with auto-scale |
| P1v3 | 2 | 8 GB | ~$120 | High performance |

*Prices approximate for US regions

Set in `.env`:
```bash
APP_SERVICE_PLAN_SKU="B2"
```

## Accessing Your Deployment

After deployment completes, azd will show you the URL:

```
Endpoint: https://app-xxxxx.azurewebsites.net
```

You can also get the URL anytime:

```bash
azd show --output json | jq -r '.services.web.endpoint'
```

Or visit the Azure Portal:
1. Go to your resource group (`rg-{environment-name}`)
2. Click on the App Service
3. Click "Browse" at the top

## Monitoring and Logs

### View Real-time Logs

```bash
# Stream logs from App Service
az webapp log tail --name <app-name> --resource-group <resource-group>
```

### View Logs in Portal

1. Azure Portal → Your App Service
2. Left menu → "Log stream"
3. Or "Logs" for historical queries

### Container Logs

```bash
# Download container logs
az webapp log download --name <app-name> --resource-group <resource-group>
```

## Updating the Deployment
Your Code

After making changes to your code:

```bash
# The build will automatically include your latest changes
azd deploy
```
Build Performance

First build may take **10-15 minutes** as it:
To update to a newer version of Langflow:

```bash
# Pull latest changes from Langflow repository
git pull upstream main  # or merge upstream changes

# Deploy with the new code
The deployment will:
1. Build a new Docker image from your current code
2. Push it to ACR with a new tag
3. Update the App Service to use the new image

### Update 
### Update Environment Variables

1. Edit your `.env` file
2. Run:
```bash
azd deploy
```

### Update to New Langflow Version

Change the Docker image in `.env`:
```bash
DOCKER_IMAGE="langflowai/langflow:v1.x.x"
```

Then deploy:
```bash
azd deploy
```

### Scale Up/Down

Change the SKU in `.env`:
```bash
APP_SERVICE_PLAN_SKU="B3"  # Scale up to B3
```

Then provision:
```bash
azd provision
```

## Troubleshooting

### Container Won't Start

Check logs:
```bash
az webapp log tail --name <app-name> --resource-group <resource-group>
```

Common issues:
- Invalid database connection string
- Database not accessible from Azure (firewall rules)
- Missing required environment variables

### Database Connection Issues

Test PostgreSQL connectivity:
1. Ensure your PostgreSQL server allows connections from Azure
2. Verify firewall rules include Azure services
3. Check connection string format includes `sslmode=require`

### Health Check Failing

The deployment uses `/health` as the health check endpoint. If this fails:
1. Check container logs
2. Verify Langflow is starting correctly
3. Check if port 7860 is exposed

### Application Errors

1. Check Application Logs in Azure Portal
2. Increase log level: Set `LANGFLOW_LOG_LEVEL=DEBUG` in `.env`
3. Redeploy with `azd deploy`

## Cleanup

To delete all Azure resources:

```bash
azd down
```

This will delete:
- Resource group
- App Service
- App Service Plan
- All associated resources

**Note:** This does NOT delete your external PostgreSQL database.

## Security Notes

   │  └─ Docker: Your custom-built image from ACR
   │     └─ Port: 7860 → 80/443
   │
   ├─→ Azure Container Registry (ACR)
   │   └─ Stores your built imagession enforced
3. **FTP Disabled**: FTP access is disabled for security
4. **Environment Variables**: Stored encrypted in App Service configuration
5. **Database SSL**: Use `sslmode=require` in connection string

### Additional Security (Optional)

For enhanced security, consider:
- Using Azure Key Vault for secrets (requires additional configuration)
- Container Registry (Basic): ~$5/month
- **Total: ~$60ion for network isolation
- Private endpoints for database connectivity
- Azure Front Door with WAF for DDoS protection

## Architecture

```
Internet
   │
   ▼
Azure App Service (Linux Container)
   │
   ├─ App Service Plan (B2)
   │  └─ Docker: langflowai/langflow:latest
   │     └─ Port: 7860 → 80/443
   │
   └─→ Your PostgreSQL Server (external)
```

## Cost Breakdown

Estimated monthly costs (B2 configuration):
- App Service Plan (B2): ~$55/month
- **Total: ~$55/month**

Plus your existing PostgreSQL server costs.

## Support

- [Langflow Documentation](https://docs.langflow.org/)
- [Azure App Service Documentation](https://docs.microsoft.com/azure/app-service/)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)

## Files in This Deployment

```
langflow/
├── azure.yaml                          # azd configuration
├── .azure/
│   ├── plan.md                         # Deployment plan
│   └── config.json                     # azd service config
└── infra/                              # Infrastructure as Code
    ├── main.bicep                      # Main deployment template
    ├── main.parameters.json            # Parameter mappings
    ├── abbreviations.json              # Azure naming conventions
    └── core/
        └── host/
            ├── appserviceplan.bicep    # App Service Plan
            └── appservice.bicep        # App Service (Web App)
```
