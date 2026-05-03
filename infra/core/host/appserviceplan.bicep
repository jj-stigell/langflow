@description('The name of the App Service Plan')
param name string

@description('The location')
param location string = resourceGroup().location

param tags object = {}

param sku object

param kind string = ''

param reserved bool = true

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: name
  location: location
  tags: tags
  sku: sku
  kind: kind
  properties: {
    reserved: reserved
  }
}

output id string = appServicePlan.id
output name string = appServicePlan.name
