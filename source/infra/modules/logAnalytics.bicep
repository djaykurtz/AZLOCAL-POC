// Log Analytics workspace for the Azure Local POC.
// PerGB2018 (pay-per-GB) with a hard daily ingestion cap.

@description('Workspace name.')
param name string

@description('Azure region.')
param location string

@description('Tags to apply.')
param tags object

@description('Daily ingestion cap in GB. Hard stop, not soft.')
@minValue(1)
@maxValue(50)
param dailyQuotaGb int

@description('Data retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output workspaceId string = workspace.id
output customerId string = workspace.properties.customerId
output name string = workspace.name
