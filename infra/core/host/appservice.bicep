@description('The name of the App Service')
param name string

param location string = resourceGroup().location
param tags object = {}
param appServicePlanId string
param runtimeName string
param runtimeVersion string
param kind string = 'app,linux'
param httpsOnly bool = true
param appSettings object = {}
param healthCheckPath string = ''
param managedIdentity bool = false
param containerRegistryName string = ''

@allowed(['1.0', '1.1', '1.2'])
param minTlsVersion string = '1.2'

@allowed(['AllAllowed', 'FtpsOnly', 'Disabled'])
param ftpsState string = 'Disabled'

var appSettingsArray = [for setting in items(appSettings): {
  name: setting.key
  value: setting.value
}]

resource appService 'Microsoft.Web/sites@2022-09-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  identity: managedIdentity ? { type: 'SystemAssigned' } : null
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

// AcrPull role for the App Service managed identity
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (managedIdentity && !empty(containerRegistryName)) {
  name: guid(resourceGroup().id, appService.id, 'AcrPull')
  scope: resourceGroup()
  properties: {
    principalId: appService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

output id string = appService.id
output name string = appService.name
output uri string = 'https://${appService.properties.defaultHostName}'
output defaultHostName string = appService.properties.defaultHostName
output principalId string = managedIdentity ? appService.identity.principalId : ''
