// Action group for POC operational alerts.
// Email receivers only - SMS / voice / ITSM not used for POC.

@description('Action group name.')
param name string

@description('Short name (max 12 chars) used in notifications.')
@maxLength(12)
param shortName string

@description('Tags to apply.')
param tags object

@description('Email addresses that receive notifications.')
param emailReceivers array

// Action groups are global (location: global), not regional.
resource actionGroup 'Microsoft.Insights/actionGroups@2023-09-01-preview' = {
  name: name
  location: 'global'
  tags: tags
  properties: {
    groupShortName: shortName
    enabled: true
    emailReceivers: [for (email, idx) in emailReceivers: {
      name: 'email-${idx}'
      emailAddress: email
      useCommonAlertSchema: true
    }]
  }
}

output actionGroupId string = actionGroup.id
output name string = actionGroup.name
