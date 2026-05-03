# Azure Deployment Plan: Langflow to Azure App Service

**Status:** Approved - Simplified  
**Created:** May 3, 2026  
**Mode:** MODIFY (existing application with Docker setup)  
**Recipe:** Azure Developer CLI (azd) with Bicep

---

## Executive Summary

Deploy the existing Langflow application to Azure App Service as a Docker container only. User has existing PostgreSQL server. No Redis, no Azure Storage, no monitoring needed.

---

## 1. Requirements Analysis

### Application Profile
- **Type:** Web application (Python/FastAPI backend + React frontend)
- **Current Setup:** Docker containerized, runs on port 7860
- **Pre-built Images:** `langflowai/langflow:latest` available on Docker Hub
- **Database:** PostgreSQL required
- **Caching:** Redis (optional but recommended)
- **Storage:** File storage for logs, uploads, and configurations

### Scale & Budget
- **Scale:** Development/Production ready
- **Expected Traffic:** TBD (can scale with App Service Plan)
- **Budget Tier:** Basic/Standard (recommended for production)

---

## 2. Current Architecture

### Existing Components
```
Langflow Application (Port 7860)
├── PostgreSQL Database (Port 5432)
├── Redis Cache (Port 6379) - Optional
├── RabbitMQ (Port 5672) - Optional, for worker tasks
└── File Storage (Volumes)
```

### Key Environment Variables
- `LANGFLOW_DATABASE_URL` - PostgreSQL connection string
- `LANGFLOW_CONFIG_DIR` - Storage directory for logs/files
- `LANGFLOW_SUPERUSER` / `LANGFLOW_SUPERUSER_PASSWORD` - Admin credentials
- `LANGFLOW_REDIS_HOST`, `LANGFLOW_REDIS_PORT` - Redis configuration
- `BROKER_URL`, `RESULT_BACKEND` - RabbitMQ/Celery configuration (optional)

---

## 3. Target Azure Architecture (Simplified)

### Azure Services Mapping

| Component | Azure Service | Justification |
|-----------|---------------|---------------|
| **Langflow App** | Azure App Service (Linux Container) | Managed PaaS with container support, auto-scaling, SSL |
| **PostgreSQL** | User's existing server | Already configured |
| **Redis Cache** | Not included | Not needed for this deployment |
| **File Storage** | Container ephemeral storage | Langflow uses S3, not Azure Storage |
| **Monitoring** | App Service logs only | No Application Insights |

### Architecture Diagram
```
Internet
   │
   ↓
Azure App Service (Linux Container)
   ├── Container: langflowai/langflow:latest
   ├── Port: 7860 → 80/443
   │
   └─→ User's PostgreSQL Server (existing)
```

---

## 4. Implementation Plan

### Phase 1: Infrastructure Setup (Bicep)
- [x] **Step 1.1:** Create Resource Group (handled by azd)
- [x] **Step 1.2:** Provision App Service Plan (Linux, B1 or higher)
- [x] **Step 1.3:** Provision App Service (Web App for Containers)
  - Configure container settings
  - Set environment variables
  - Enable logging
  - HTTPS only

### Phase 2: Configuration
- [ ] **Step 2.1:** Generate `azure.yaml` for azd
- [ ] **Step 2.2:** Create Bicep infrastructure templates
  - `main.bicep` - Resource group and orchestration
  - `app-service.bicep` - App Service and Plan
  - `database.bicep` - PostgreSQL server
  - `redis.bicep` - Redis cache
  - `storage.bicep` - Storage account
  - `monitoring.bicep` - Application Insights
- [ ] **Step 2.3:** Configure environment variables in App Service
  - Database connection string
  - Redis connection string
  -x] **Step 2.1:** Generate `azure.yaml` for azd
- [x] **Step 2.2:** Create Bicep infrastructure template
  - `main.bicep` - App Service Plan and App Service
- [x] **Step 2.3:** Configure environment variables in App Service
  - Database connection string (user provided)
  - Superuser credentials (user provided)
  - Config directory path
  - Port configuration
- [ ] **Step 4.1:** Create deployment documentation
- [ ] **Step 4.2:** Document environment variables
- [ ] **Step 4.3:** Create `.azure` folder structure
- [ ] **Step 4.4:** Test Bicep templates locally with `az deployment` or `azd provision`

---

## 5. Deployment Recipe: Azure Developer CLI (azd)

### Why azd?
- Sx] **Step 3.1:** Enable HTTPS only
- [x] **Step 3.2:** Set minimum TLS version to 1.2
langflow/
├── azure.yaml                 # azd configuration
├── .azure/
│   └── plan.md               # This file
└── infra/
    ├── main.bicep            # Main infrastructure orchestration
    ├── main.parameters.json  # Parameter file
    ├── app-service.bicep     # App Service resources
    ├── database.bicep        # PostgreSQL resources
    ├── redis.bicep           # Redis cache
    ├── storage.bicep         # Storage account
    └── monitoring.bicep      # Application Insights
```

### Deployment Commands
```bash
# Initialize azd (if first time)
azd init

# Provision infrastructure
azd provision

# Deploy application
azd deploy

# Or do both in one command
azd up
```

---

## 6. Configuration Details

### App Service Settings

**Container Configuration:**
```yaml
Container Image: docker.io/langflowai/langflow:latest
Port: 7860
Startup Command: (use default from image)
```

**Application Settings (Environment Variables):**
```bash
LANGFLOW_DATABASE_URL=postgresql://<admin-user>:<password>@<postgres-server>.postgres.database.azure.com:5432/langflow?sslmode=require
LANGFLOW_CONFIG_DIR=/home/langflow-data
LANGFLOW_SUPERUSER=<admin-username>
LANGFLOW_SUPERUSER_PASSWORD=<secure-password>
LANGFLOW_REDIS_HOST=<redis-name>.redis.cache.windows.net
LANGFLOW_REDIS_PORT=6380
LANGFLOW_REDIS_PASSWORD=<redis-key>
WEBSITES_PORT=7860
WEBSITES_ENABLE_APP_SERVICE_STORAGE=true
```

**Health Check:**
```
Path: /health (or /api/v1/health depending on Langflow version)
Interval: 60 seconds
```

### PostgreSQL Configuration
- **SKU:** Burstable B1ms (minimum) or General Purpose for production
- **Storage:** 32 GB (can scale up)
- **Backup:** 7-day retention (default)
- **SSL:** Enforce SSL enabled
- **Firewall:** Allow Azure services

### Redis Configuration
- **SKU:** Basic C0 (250 MB) for dev, Standard C1+ for production
- **TLS Port:** 6380
- **Access Keys:** Use primary key initially
- **Non-TLS Port:** Disabled (security best practice)

### Storage Configuration
- **Type:** Standard LRS or ZRS for redundancy
- **Azure Files Share:** Mount to `/home/langflow-data` in container
- **Access Tier:** Hot
- **Protocol:** SMB 3.0

---

## 7. Cost Estimation (Monthly, USD)

| Service | Tier | Est. Cost |
|---------|------|-----------|
| App Service Plan | B2 (2 Core, 3.5 GB RAM) | ~$70 |
| PostgreSQL Flexible | B1ms (1-2 vCore, 2 GB RAM) | ~$25 |
| Redis Cache | Basic C0 (250 MB) | ~$16 |
| Storage Account | General Purpose v2, 10 GB | ~$1 |
| Application Insights | First 5 GB free | ~$0-5 |
| **Total (Development)** | | **~$112-117** |

**Production Tier (Recommended):**
- App Service: S1 (~$70) or P1v3 (~$120)
- PostgreSQL: GP_Standard_D2s_v3 (~$150)
- Redis: Standard C1 (~$55)
- Total: ~$275-330/month

| App Service Plan | B1 (1 Core, 1.75 GB RAM) | ~$13 |
| App Service Plan | B2 (2 Core, 3.5 GB RAM) | ~$55 |
| App Service Plan | S1 (1 Core, 1.75 GB RAM) | ~$70 |
| **Recommended:** | **B2** | **~$55/month** |

**Notes:**
- B1 may be too small for production workloads
- B2 provides better performance with 2 cores
- S1+ adds deployment slots and auto-scalings** - Monitor security exceptions

### Optional Enhanced Security
- **Key Vault** - For secret management
- **Private Endpoints** - For network isolation
- **VNet Integration** - Private communication between services
- **Azure Front Door** - WAF and DDoS protection

---

## 9. Monitoring & Operations

### Telemetry
- **Application Insights** - APM, request traces, exceptions
- **App Service Logs** - Container logs, HTTP logs
- **PostgreSQL Logs** - Query logs, error logs
- **Redis Insights** - Cache hit/miss rates

### Health Checks
- App Service health probe on `/health`
- PostgreSQL connection monitoring
- Redis availability monitoring

### Backup & DR
- PostgreSQL automated backups (7-day retention)
- App Service configuration backup
- Storage account geo-redundancy (optional)

---

## 10. Post-Deployment

### Validation Steps
1. Verify App Service is running
2. Test database connectivity
3. Verify Redis cache (if enabled)
4. Check storage mount
5. Access Langflow UI at `https://<app-name>.azurewebsites.net`
6. Create test superuser account
7. Test flow creation and execution
8. Review Application Insights telemetry

### Documentation to Create
- Deployment runbook
- Environment variables reference
- Troubleshooting guide
- Scaling procedures
- Backup/restore procedures

---

## 11. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Container startup timeout | High | Increase startup timeout, enable App Service storage |
| Database connection failures | High | Verify firewall rules, use SSL, test connection string |
| Storage mount issues | Medium | Use Azure Files with proper access keys |
| Performance issues | Medium | Scale App Service Plan, enable Redis cache |
| Cold start latency | Low | Use Always On setting (Basic tier+) |

---

## 12. Alternative Approaches Considered

### Option 1: Azure Container Apps (ACA)
- **Pro:** More modern, consumption-based pricing
- **Con:** More complex for simple web apps, newer service
- **Decision:** App Service is simpler for this use case

### Option 2: Azure Kubernetes Service (AKS)
- **Pro:** Full Kubernetes control, best for microservices
- **Con:** Overhead for single container app, more expensive
- **Decision:** App Service is more cost-effective

### Option 3: Azure Container Instances (ACI)
- **Pro:** Simple, cheap for dev/test
- **Con:** No scaling, no managed domain, no integrated monitoring
- **Decision:** App Service provides better production features

---

## 13. Next Steps

### Immediate Actions Required
1. **User Decision Points:**
   - Confirm Azure subscription and region
   - Confirm PostgreSQL admin credentials
   - Confirm superuser credentials for Langflow
   - Approve this deployment plan
   - Choose tier (development vs production)

2. **After Approval:**
   - Generate Bicep infrastructure templates
   - Create azure.yaml configuration
   - Set up parameters file
   - Invoke **azure-validate** skill for pre-deployment checks
   - Invoke **azure-deploy** skill to provision and deploy

### Timeline Estimate
- Infrastructure generation: 15-30 minutes
- Deployment: 10-20 minutes
- Validation & testing: 15-30 minutes
- **Total:** 40-80 minutes

---

## 14. Questions for User

Before proceeding, please confirm:

1. **Azure Context:**
   - Which Azure subscription should be used?
   - Which region? (e.g., eastus, westus2, westeurope)

2. **Configuration:**
   - What should the Langflow superuser username/password be?
   - Should we include Redis cache? (Recommended: Yes)
   - Should we include RabbitMQ for background workers? (Optional)

3. **Tier Selection:**
   - Development tier (~$112/month) or Production tier (~$275/month)?

4. **Security:**
   - Do you need VNet integration or private endpoints?
   - Should we use Key Vault for secrets management?

5. **Custom Image:**
   - Will you use the public `langflowai/langflow:latest` image or need to build a custom one?

---

## Approval

**Status:** ⏸️ PENDING USER APPROVAL

Please review this plan and confirm:
- [ ] I approve the architecture and Azure services selected
- [ ] I have answered the questions above
- [ ] I understand the estimated costs
- [ ] I'm ready to proceed with infrastructure generation

Once approved, I will:
1. Generate all Bicep templates
2. Create azure.yaml configuration
3. Validate the deployment configuration
4. Guide you through the deployment process

---

**End of Plan**
