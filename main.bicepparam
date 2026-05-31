using './main.bicep'

param location = 'uksouth'
param resourceGroupName = 'rg-sentinel-lab'
param workspaceName = 'law-sentinel-lab'

// Cost guardrails for a lab.
param retentionInDays = 90
param dailyQuotaGb = 1

// Connectors to turn on.
param enableAzureActivity = true
param enableDefenderForCloud = true
param enableEntraId = false // requires tenant diag settings + Global Admin; see README

// Workbooks.
param enableWorkbooks = true

// Content Hub solutions (packaged connectors + workbook/rule templates).
param installContentHubSolutions = true
param contentHubSolutionPackageIds = [
  'azuresentinel.azure-sentinel-solution-azureactivity'
  'azuresentinel.azure-sentinel-solution-azureactivedirectory'
  'azuresentinel.azure-sentinel-solution-microsoftdefenderforcloud'
]

param tags = {
  environment: 'lab'
  workload: 'sentinel'
  managedBy: 'bicep'
}
