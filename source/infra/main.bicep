// Azure Local POC infrastructure - main orchestration file.
//
// Deploys the POC-scoped observability and cost-guardrail resources into
// rg-azlocal-poc-001 (already created out-of-band). Deploy with:
//
//   az deployment group create `
//     --resource-group rg-azlocal-poc-001 `
//     --template-file infra/main.bicep `
//     --parameters infra/main.bicepparam
//
// Or preview with `what-if` instead of `create` first.
//
// Scope is the resource group; main.bicepparam holds environment-specific
// values. The cluster, key vault, and witness storage account are not in
// this file - they land later, after directory admins grants the role assignments.

targetScope = 'resourceGroup'

// === parameters ==============================================================

@description('Azure region for all resources. Must match the RG region.')
param location string = resourceGroup().location

@description('Tag schema applied to every resource. Keep in sync with the POC plan poc_tags block.')
param tags object

@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string

@description('Daily ingestion cap in GB. Workspace stops ingesting (and notifies) past this number.')
@minValue(1)
@maxValue(50)
param logAnalyticsDailyQuotaGb int = 5

@description('Workspace data retention in days.')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Action group name (operational alerts for the POC).')
param actionGroupName string

@description('Short name for the action group (max 12 chars, shown in SMS/notifications).')
@maxLength(12)
param actionGroupShortName string = 'azlocPOC'

@description('Email addresses that receive action group notifications.')
param actionGroupEmailReceivers array

@description('Budget name (RG-scoped).')
param budgetName string

@description('Monthly budget amount in USD.')
@minValue(50)
param budgetMonthlyUsd int = 500

@description('Budget threshold percentages that trigger an alert.')
param budgetThresholdsPct array = [
  50
  80
  100
]

@description('First day of the budget. Use YYYY-MM-01 format. Budget recurs monthly from this date.')
param budgetStartDate string

// === modules =================================================================

module law 'modules/logAnalytics.bicep' = {
  name: 'deploy-law'
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    tags: tags
    dailyQuotaGb: logAnalyticsDailyQuotaGb
    retentionInDays: logAnalyticsRetentionDays
  }
}

module ag 'modules/actionGroup.bicep' = {
  name: 'deploy-ag'
  params: {
    name: actionGroupName
    shortName: actionGroupShortName
    tags: tags
    emailReceivers: actionGroupEmailReceivers
  }
}

module budget 'modules/budget.bicep' = {
  name: 'deploy-budget'
  params: {
    name: budgetName
    monthlyAmountUsd: budgetMonthlyUsd
    thresholdsPct: budgetThresholdsPct
    startDate: budgetStartDate
    actionGroupId: ag.outputs.actionGroupId
    contactEmails: actionGroupEmailReceivers
  }
}

// === outputs =================================================================

output logAnalyticsWorkspaceId string = law.outputs.workspaceId
output logAnalyticsCustomerId string = law.outputs.customerId
output actionGroupId string = ag.outputs.actionGroupId
