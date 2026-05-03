@description('The name of the App Service')
param name string

@description('The location of the App Service')
param location string = resourceGroup().location

@description('Tags for the App Service')
param tags object = {}

@description('The resource ID of the App Service Plan')
param appServicePlanId string

@description('The runtime name')
param runtimeName string

@description('The runtime version')
param runtimeVersion string

@description('The kind of App Service')
param kind string = 'app,linux'

@description('Whether to use HTTPS only')
param httpsOnly bool = true

@description('Application settings')
param appSettings object = {}

@description('Health check path')
param healthCheckPath string = ''

@description('Minimum TLS version')
@allowed([
  '1.0'
  '1.1'
  '1.2'
])
param minTlsVersion string = '1.2'

@description('FTP state')
@allowed([
  'AllAllowed'
  'FtpsOnly'
  'Disabled'
])
param ftpsState string = 'Disabled'

@description('Enable managed identity')
param managedIdentity bool = false

@description('Container Registry name for RBAC assignment')
param containerRegistryName string = ''

// Convert appSettings object to array format required by the API
var appSettingsArray = [for setting in items(appSettings): {
  name: setting.key
  value: setting.value
}]

resource appService 'Microsoft.Web/sites@2022-09-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  identity: managedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: httpsOnly
    siteConfig: {
      linuxFxVersion: '${runtimeName}|${runtimeVersion}'
      alwaysOn: true
      ftpsState: ftpsState
      minTlsVersion: minTlsVersion
      appSettings: appSettingsArray
      healthCheckPath: !empty(healthCheckPath) ? healthCheckPath : null
      acrUseManagedIdentityCreds: managedIdentity
    }
  }
}

output principalId string = managedIdentity ? appService.identity.principalId : ''
// Grant the App Service managed identity AcrPull permissions on the Container Registry
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (managedIdentity && !empty(containerRegistryName)) {
  name: guid(resourceGroup().id, appService.id, 'AcrPull')
  scope: resourceGroup()
  properties: {
    principalId: appService.identity.principalId
    principalType: 'ServicePrincipal'
    // AcrPull role definition ID
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

output id string = appService.id
output name string = appService.name
output uri string = 'https://${appService.properties.defaultHostName}'
output defaultHostName string = appService.properties.defaultHostName
