@description('The name of the Container Registry')
param name string

@description('The location of the Container Registry')
param location string = resourceGroup().location

@description('Tags for the Container Registry')
param tags object = {}

@description('Enable admin user')
param adminUserEnabled bool = false

@description('SKU for the Container Registry')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    publicNetworkAccess: 'Enabled'
  }
}

output id string = containerRegistry.id
output name string = containerRegistry.name
output loginServer string = containerRegistry.properties.loginServer
