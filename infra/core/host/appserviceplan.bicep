@description('The name of the App Service Plan')
param name string

@description('The location of the App Service Plan')
param location string = resourceGroup().location

@description('Tags for the App Service Plan')
param tags object = {}

@description('The SKU of the App Service Plan')
param sku object

@description('The kind of App Service Plan')
param kind string = ''

@description('Whether the App Service Plan is reserved (Linux)')
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
