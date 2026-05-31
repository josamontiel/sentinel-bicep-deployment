// =============================================================================
// Microsoft Sentinel automation lab — end-to-end deployment
// Scope: SUBSCRIPTION (creates the resource group + a subscription-level
//        Activity log diagnostic setting, then deploys workspace, Sentinel,
//        connectors, and workbooks into the resource group).
//
// Deploy:  az deployment sub create \
//            --name sentinel-lab \
//            --location eastus \
//            --template-file ./main.bicep \
//            --parameters ./main.bicepparam
// =============================================================================

targetScope = 'subscription'

@description('Azure region for the resource group and all resources.')
param location string = 'eastus'

@description('Name of the resource group to create for the lab.')
param resourceGroupName string = 'rg-sentinel-lab'

@description('Name of the Log Analytics workspace that backs Microsoft Sentinel.')
@minLength(4)
@maxLength(63)
param workspaceName string = 'law-sentinel-lab'

@description('Data retention in days. 90 days is included free when Sentinel is enabled.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Daily ingestion cap in GB to protect lab spend. Set to -1 for unlimited.')
param dailyQuotaGb int = 1

@description('Stream the subscription Activity log into the workspace (the Azure Activity connector).')
param enableAzureActivity bool = true

@description('Enable the Microsoft Defender for Cloud data connector.')
param enableDefenderForCloud bool = true

@description('Enable the Microsoft Entra ID connector. NOTE: actually flowing sign-in/audit logs also requires tenant-level diagnostic settings and Global Administrator rights — see README.')
param enableEntraId bool = false

@description('Deploy the lab workbooks.')
param enableWorkbooks bool = true

@description('Install Content Hub solutions (packaged connectors, workbook/rule templates, hunting queries).')
param installContentHubSolutions bool = true

@description('Content Hub solution package IDs to install. Defaults match the connectors enabled above.')
param contentHubSolutionPackageIds array = [
  'azuresentinel.azure-sentinel-solution-azureactivity'
  'azuresentinel.azure-sentinel-solution-azureactivedirectory'
  'azuresentinel.azure-sentinel-solution-microsoftdefenderforcloud'
]

@description('Tags applied to every resource.')
param tags object = {
  environment: 'lab'
  workload: 'sentinel'
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// Resource group
// ---------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ---------------------------------------------------------------------------
// Log Analytics workspace
// ---------------------------------------------------------------------------
module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'deploy-loganalytics'
  scope: rg
  params: {
    workspaceName: workspaceName
    location: location
    retentionInDays: retentionInDays
    dailyQuotaGb: dailyQuotaGb
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Microsoft Sentinel onboarding + data connectors
// ---------------------------------------------------------------------------
module sentinel 'modules/sentinel.bicep' = {
  name: 'deploy-sentinel'
  scope: rg
  params: {
    workspaceName: workspaceName
    enableDefenderForCloud: enableDefenderForCloud
    enableEntraId: enableEntraId
  }
  dependsOn: [
    logAnalytics
  ]
}

// ---------------------------------------------------------------------------
// Workbooks
// ---------------------------------------------------------------------------
module workbooks 'modules/workbooks.bicep' = if (enableWorkbooks) {
  name: 'deploy-workbooks'
  scope: rg
  params: {
    location: location
    workspaceResourceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
  dependsOn: [
    sentinel
  ]
}

// ---------------------------------------------------------------------------
// Content Hub solutions (modern packaged content)
// ---------------------------------------------------------------------------
module contentHub 'modules/contenthub.bicep' = if (installContentHubSolutions) {
  name: 'deploy-contenthub'
  scope: rg
  params: {
    workspaceName: workspaceName
    solutionPackageIds: contentHubSolutionPackageIds
  }
  dependsOn: [
    sentinel
  ]
}

// ---------------------------------------------------------------------------
// Azure Activity connector (modern model = subscription-scoped diagnostic
// setting that routes the Activity log into the workspace). Declared at the
// subscription scope, which is why main.bicep targets the subscription.
// ---------------------------------------------------------------------------
resource activityToSentinel 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableAzureActivity) {
  name: 'sentinel-activity-to-law'
  properties: {
    workspaceId: logAnalytics.outputs.workspaceId
    logs: [
      { category: 'Administrative', enabled: true }
      { category: 'Security', enabled: true }
      { category: 'ServiceHealth', enabled: true }
      { category: 'Alert', enabled: true }
      { category: 'Recommendation', enabled: true }
      { category: 'Policy', enabled: true }
      { category: 'Autoscale', enabled: true }
      { category: 'ResourceHealth', enabled: true }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output workspaceResourceId string = logAnalytics.outputs.workspaceId
output workspaceName string = logAnalytics.outputs.workspaceName
output resourceGroupName string = rg.name
