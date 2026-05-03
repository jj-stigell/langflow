targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// --- Optional name overrides (generated if empty) ---
param appServicePlanName string = ''
param appServiceName string = ''
param containerRegistryName string = ''
param staticWebAppName string = ''

@description('App Service Plan SKU')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'P1v3', 'P2v3'])
param appServicePlanSku string = 'B2'

// --- Container settings ---
@description('Docker image name in ACR (populated by deploy-azure.sh after first build)')
param dockerImage string = ''

@description('Docker image tag')
param dockerImageTag string = 'latest'

@description('Port the backend container listens on')
param containerPort string = '7860'

// --- Langflow settings ---
@secure()
param databaseUrl string = ''
param langflowSuperuser string = ''
@secure()
param langflowSuperuserPassword string = ''
param langflowConfigDir string = '/home/langflow-data'
@allowed(['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'])
param langflowLogLevel string = 'INFO'

// --- S3 / file storage settings ---
param langflowStorageType string = 's3'
param langflowS3BucketName string = ''
param langflowS3Prefix string = ''
@secure()
param awsAccessKeyId string = ''
@secure()
param awsSecretAccessKey string = ''
param awsDefaultRegion string = ''

// -------------------------------------------------------------------
var tags = { 'azd-env-name': environmentName, application: 'langflow' }
var abbrs = loadJsonContent('./abbreviations.json')
var token = toLower(uniqueString(subscription().id, environmentName, location))

var planName = !empty(appServicePlanName)    ? appServicePlanName    : '${abbrs.webServerFarms}${token}'
var appName  = !empty(appServiceName)        ? appServiceName        : '${abbrs.webSitesAppService}${token}'
var acrName  = !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistry}${token}'
var swaName  = !empty(staticWebAppName)      ? staticWebAppName      : '${abbrs.webStaticSites}${token}'

// -------------------------------------------------------------------
// Resource Group
// -------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

// -------------------------------------------------------------------
// Container Registry  (stores the backend Docker image)
// -------------------------------------------------------------------
module acr './core/host/container-registry.bicep' = {
  name: 'acr'
  scope: rg
  params: { name: acrName, location: location, tags: tags }
}

// -------------------------------------------------------------------
// App Service Plan  (Linux)
// -------------------------------------------------------------------
module plan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: planName
    location: location
    tags: tags
    sku: { name: appServicePlanSku }
    kind: 'linux'
    reserved: true
  }
}

// -------------------------------------------------------------------
// App Service  (Docker container – FastAPI backend)
// -------------------------------------------------------------------
module app './core/host/appservice.bicep' = {
  name: 'appservice'
  scope: rg
  params: {
    name: appName
    location: location
    tags: union(tags, { 'azd-service-name': 'web' })
    appServicePlanId: plan.outputs.id
    runtimeName: 'docker'
    runtimeVersion: !empty(dockerImage)
      ? '${acr.outputs.loginServer}/${dockerImage}:${dockerImageTag}'
      : 'nginx:latest'
    kind: 'app,linux,container'
    httpsOnly: true
    managedIdentity: true
    containerRegistryName: acr.outputs.name
    appSettings: {
      WEBSITES_PORT: containerPort
      DOCKER_REGISTRY_SERVER_URL: 'https://${acr.outputs.loginServer}'
      DOCKER_ENABLE_CI: 'true'
      LANGFLOW_DATABASE_URL: databaseUrl
      LANGFLOW_CONFIG_DIR: langflowConfigDir
      LANGFLOW_SUPERUSER: langflowSuperuser
      LANGFLOW_SUPERUSER_PASSWORD: langflowSuperuserPassword
      LANGFLOW_LOG_LEVEL: langflowLogLevel
      LANGFLOW_STORAGE_TYPE: langflowStorageType
      LANGFLOW_OBJECT_STORAGE_BUCKET_NAME: langflowS3BucketName
      LANGFLOW_OBJECT_STORAGE_PREFIX: langflowS3Prefix
      AWS_ACCESS_KEY_ID: awsAccessKeyId
      AWS_SECRET_ACCESS_KEY: awsSecretAccessKey
      AWS_DEFAULT_REGION: awsDefaultRegion
    }
    healthCheckPath: '/health'
  }
}

// -------------------------------------------------------------------
// Static Web App  (React frontend on Azure CDN)
// Linked backend proxies /api/* requests to the App Service
// -------------------------------------------------------------------
module swa './core/host/static-web-app.bicep' = {
  name: 'staticwebapp'
  scope: rg
  params: {
    name: swaName
    // SWA is a global service; location must be one of the supported regions
    location: 'westus2'
    tags: union(tags, { 'azd-service-name': 'frontend' })
    linkedBackendId: app.outputs.id
    linkedBackendRegion: location
  }
}

// -------------------------------------------------------------------
// Outputs  (read by deploy-azure.sh via `azd env get-values`)
// -------------------------------------------------------------------
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name

output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer

output WEB_NAME string = app.outputs.name
output WEB_URI string = app.outputs.uri

output FRONTEND_NAME string = swa.outputs.name
output FRONTEND_URI string = swa.outputs.uri
// Deployment token fetched at deploy time via: az staticwebapp secrets list
