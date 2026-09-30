// Parameter values for the Azure Local POC deployment.
// Keep this aligned with the POC plan. ASCII only.

using 'main.bicep'

param location = 'westus3'

param tags = {
  BusinessCriticality: 'Non-Critical'
  BusinessUnit: 'Lab'
  DataClassification: 'General'
  DeploymentDate: '2026-05-22'
  ProjectName: 'AzureLocalPOC'
  ProjectEndDate: '2026-08-21'
  Owner: 'platform'
  RequestorAlias: 'labadmin'
  WorkloadName: 'AzureLocal'
  CostCenter: 'PENDING'
}

param logAnalyticsWorkspaceName = 'azloc-law-001'
param logAnalyticsDailyQuotaGb = 5
param logAnalyticsRetentionDays = 30

param actionGroupName = 'azloc-ag-001'
param actionGroupShortName = 'azlocPOC'
param actionGroupEmailReceivers = [
  'labadmin@example.com'
]

param budgetName = 'azloc-budget-001'
param budgetMonthlyUsd = 500
param budgetThresholdsPct = [
  50
  80
  100
]
param budgetStartDate = '2026-05-01'
