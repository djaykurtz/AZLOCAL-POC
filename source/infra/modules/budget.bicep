// Resource-group-scoped monthly budget with threshold alerts.
// Wires alerts to both an action group and direct email contacts.

@description('Budget name.')
param name string

@description('Monthly budget amount in USD.')
@minValue(50)
param monthlyAmountUsd int

@description('Threshold percentages that fire an alert (e.g. [50, 80, 100]).')
param thresholdsPct array

@description('Start date in YYYY-MM-01 format. Budget recurs monthly from this date.')
param startDate string

@description('Action group resource ID to notify on threshold breach.')
param actionGroupId string

@description('Email addresses to notify directly (in addition to the action group).')
param contactEmails array

// Microsoft.Consumption/budgets is an extension resource - it lives at the
// scope it is deployed to (here, the resource group).
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: name
  properties: {
    category: 'Cost'
    amount: monthlyAmountUsd
    timeGrain: 'Monthly'
    timePeriod: {
      // Budgets require an explicit start date. End date is optional but
      // we leave it open so the budget rolls month over month.
      startDate: startDate
    }
    notifications: {
      actual_50: {
        enabled: contains(thresholdsPct, 50)
        operator: 'GreaterThan'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: contactEmails
        contactGroups: [
          actionGroupId
        ]
      }
      actual_80: {
        enabled: contains(thresholdsPct, 80)
        operator: 'GreaterThan'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: contactEmails
        contactGroups: [
          actionGroupId
        ]
      }
      forecasted_100: {
        enabled: contains(thresholdsPct, 100)
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: contactEmails
        contactGroups: [
          actionGroupId
        ]
      }
    }
  }
}

output budgetId string = budget.id
output name string = budget.name
