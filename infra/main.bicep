targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Name of the App Service Plan')
param appServicePlanName string = ''

@description('Name of the App Service')
param appServiceName string = ''

@description('Name of the Container Registry')
param containerRegistryName string = ''

@description('SKU for the App Service Plan')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1v3'
  'P2v3'
])
param appServicePlanSku string = 'B2'

@description('Docker image to use for the container')
param dockerImage string = ''

@description('Docker image tag')
param dockerImageTag string = 'latest'

@description('Port the container listens on')
param containerPort string = '7860'

@description('PostgreSQL connection string')
@secure()
param databaseUrl string = ''

@description('Langflow superuser username')
param langflowSuperuser string = ''

@description('Langflow superuser password')
@secure()
param langflowSuperuserPassword string = ''

@description('Langflow configuration directory')
param langflowConfigDir string = '/home/langflow-data'

@description('Langflow log level')
@allowed([
  'DEBUG'
  'INFO'
  'WARNING'
  'ERROR'
  'CRITICAL'
])
param langflowLogLevel string = 'INFO'

// Tags for all resources
var tags = {
  'azd-env-name': environmentName
  application: 'langflow'
}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Organize all naming
var appServicePlanNameFinal = !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
var appServiceNameFinal = !empty(appServiceName) ? appServiceName : '${abbrs.webSitesAppService}${resourceToken}'
var containerRegistryNameFinal = !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistry}${resourceToken}'

// Resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

// Container Registry for storing Docker images
module containerRegistry './core/host/container-registry.bicep' = {
  name: 'containerregistry'
  scope: rg
  params: {
    name: containerRegistryNameFinal
    location: location
    tags: tags
  }
}

// App Service Plan
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: appServicePlanNameFinal
    location: location
    tags: tags
    sku: {
      name: appServicePlanSku
    }
    kind: 'linux'
    reserved: true
  }
}

// App Service
module appService './core/host/appservice.bicep' = {
  name: 'appservice'
  scope: rg
  params: {
    name: appServiceNameFinal
    location: location
    tags: union(tags, { 'azd-service-name': 'web' })
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'docker'
    runtimeVersion: !empty(dockerImage) ? '${containerRegistry.outputs.loginServer}/${dockerImage}:${dockerImageTag}' : 'nginx:latest'
    kind: 'app,linux,container'
    httpsOnly: true
    managedIdentity: true
    appSettings: {
      WEBSITES_PORT: containerPort
      DOCKER_REGISTRY_SERVER_URL: 'https://${containerRegistry.outputs.loginServer}'
      DOCKER_ENABLE_CI: 'true'
      LANGFLOW_DATABASE_URL: databaseUrl
      LANGFLOW_CONFIG_DIR: langflowConfigDir
      LANGFLOW_SUPERUSER: langflowSuperuser
      LANGFLOW_SUPERUSER_PASSWORD: langflowSuperuserPassword
      LANGFLOW_LOG_LEVEL: langflowLogLevel
    }
    healthCheckPath: '/health'
    containerRegistryName: containerRegistry.outputs.name
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name

output WEB_URI string = appService.outputs.uri
output WEB_NAME string = appService.outputs.name
output APP_SERVICE_PLAN_NAME string = appServicePlan.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name
