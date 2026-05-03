# Quick Start: Deploy Langflow to Azure

Your Langflow deployment is now configured to build from **your local source code** and deploy to Azure App Service.

## What's Changed

✅ Builds Docker image from your local code (includes frontend/backend changes)  
✅ Creates Azure Container Registry to store your custom image  
✅ Uses managed identity for secure container access  
✅ Deploys to Azure App Service with your PostgreSQL database

## Prerequisites Checklist

- [ ] Azure CLI installed (`az`)
- [ ] Azure Developer CLI installed (`azd`)
- [ ] Docker installed and running
- [ ] PostgreSQL connection string ready
- [ ] Admin credentials decided

## Quick Deploy (3 Steps)

### 1. Create .env file

```bash
cp .azure/.env.example .env
```

Edit `.env` and fill in:
```bash
LANGFLOW_DATABASE_URL="postgresql://user:pass@server:5432/langflow?sslmode=require"
LANGFLOW_SUPERUSER="admin"
LANGFLOW_SUPERUSER_PASSWORD="your-secure-password"
```

### 2. Login to Azure

```bash
azd auth login
```

### 3. Deploy Everything

```bash
azd up
```

Or use the helper script:
```bash
./deploy-azure.sh
```

That's it! The deployment will:
1. Build your Docker image (10-15 min first time)
2. Create Azure resources
3. Push image to Container Registry
4. Deploy to App Service

## After Deployment

Get your URL:
```bash
azd show
```

View logs:
```bash
az webapp log tail --name <app-name> --resource-group <rg-name>
```

## Update Your Code

After making changes:
```bash
azd deploy
```

This rebuilds the image with your latest changes and redeploys.

## Cost

- **App Service (B2):** ~$55/month
- **Container Registry:** ~$5/month
- **Total:** ~$60/month (+ your PostgreSQL costs)

## Architecture

```
Your Local Code → Docker Build → Azure Container Registry → App Service → Internet
                                          ↑
                                   Managed Identity
```

## Troubleshooting

**Build fails?**
- Ensure Docker is running
- Check you have enough disk space (build needs ~5GB)

**Deployment fails?**
- Verify PostgreSQL connection string
- Check database firewall allows Azure services

**Container won't start?**
- Check logs: `az webapp log tail --name <app-name> --resource-group <rg-name>`
- Verify environment variables in Azure Portal

## Files Created

```
langflow/
├── Dockerfile              # Production build from local source
├── azure.yaml              # azd configuration
├── deploy-azure.sh         # Deployment helper script
├── .azure/
│   ├── README.md          # Full documentation
│   └── .env.example       # Environment template
└── infra/                 # Infrastructure as Code (Bicep)
    ├── main.bicep
    ├── main.parameters.json
    └── core/
        └── host/
            ├── appservice.bicep
            ├── appserviceplan.bicep
            └── container-registry.bicep
```

## Next Steps

1. Review [.azure/README.md](.azure/README.md) for detailed docs
2. Configure your `.env` file
3. Run `azd up` to deploy
4. Access your Langflow at the provided URL

## Support

- Full docs: [.azure/README.md](.azure/README.md)
- Deployment plan: [.azure/plan.md](.azure/plan.md)
- Langflow docs: https://docs.langflow.org/
