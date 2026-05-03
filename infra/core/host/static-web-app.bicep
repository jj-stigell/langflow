@description('The name of the Static Web App')
param name string

@description('Location for the Static Web App (must be a supported SWA region)')
param location string = 'westus2'

param tags object = {}

@allowed(['Free', 'Standard'])
param sku string = 'Standard'

@description('Resource ID of the linked App Service backend (proxies /api/* requests)')
param linkedBackendId string = ''

@description('Region of the linked backend App Service')
param linkedBackendRegion string = ''

resource swa 'Microsoft.Web/staticSites@2022-09-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    publicNetworkAccess: 'Enabled'
  }
}

// Link the App Service backend so SWA proxies /api/* requests to it
resource linkedBackend 'Microsoft.Web/staticSites/linkedBackends@2022-09-01' = if (!empty(linkedBackendId)) {
  parent: swa
  name: 'linkedBackend'
  properties: {
    backendResourceId: linkedBackendId
    region: linkedBackendRegion
  }
}

output id string = swa.id
output name string = swa.name
output uri string = 'https://${swa.properties.defaultHostname}'
// Deployment token is fetched via `az staticwebapp secrets list` in deploy-azure.sh
