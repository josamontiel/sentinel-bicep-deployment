// =============================================================================
//  main.extension.bicep  —  WIRING REFERENCE (not a standalone deployment)
//
//  Paste these param + module declarations into your existing subscription-scoped
//  main.bicep. They assume your main.bicep already has, by these (or similar)
//  symbolic names:
//
//    targetScope = 'subscription'
//    param location string
//    param workspaceName string                 // name of the LA workspace
//    resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = { ... }
//    module sentinel 'modules/sentinel.bicep' = { ... }   // onboarding module
//
//  Rename `rg` / `sentinel` below to match your file. All new modules deploy
//  into the resource group (scope: rg) and reference the workspace by name, so
//  they don't depend on how your base modules shape their outputs.
// =============================================================================

@description('Incoming webhook (Teams/Slack/...) the response playbook POSTs to.')
param notificationWebhookUrl string

@description('Object ID of the Azure Security Insights SP — run scripts/get-sentinel-sp.sh.')
param sentinelAutomationPrincipalObjectId string = ''

@description('Object ID of the identity that will POST synthetic events to the lab table.')
param ingestionPrincipalObjectId string = ''

@allowed([ 'User', 'ServicePrincipal' ])
param ingestionPrincipalType string = 'User'

// --- Synthetic data path: custom table + DCE + DCR ---------------------------
module ingest 'modules/ingest.bicep' = {
  name: 'lab-ingest'
  scope: rg
  params: {
    location: location
    workspaceName: workspaceName
    ingestionPrincipalObjectId: ingestionPrincipalObjectId
    ingestionPrincipalType: ingestionPrincipalType
  }
}

// --- Watchlist of high-value assets ------------------------------------------
module watchlists 'modules/watchlists.bicep' = {
  name: 'lab-watchlists'
  scope: rg
  params: {
    workspaceName: workspaceName
    watchlistAlias: 'HighValueAssets'
    watchlistCsv: loadTextContent('watchlists/high-value-assets.csv')
  }
  dependsOn: [ sentinel ]
}

// --- Response playbook (Logic App) -------------------------------------------
module playbook 'modules/playbook.bicep' = {
  name: 'lab-playbook'
  scope: rg
  params: {
    location: location
    workspaceName: workspaceName
    notificationWebhookUrl: notificationWebhookUrl
    sentinelAutomationPrincipalObjectId: sentinelAutomationPrincipalObjectId
  }
  dependsOn: [ sentinel ]
}

// --- Analytics rules (detections) --------------------------------------------
module analyticsRules 'modules/analyticsrules.bicep' = {
  name: 'lab-analytics-rules'
  scope: rg
  params: {
    workspaceName: workspaceName
    watchlistAlias: 'HighValueAssets'
    // enableTemplateRule: true
    // alertRuleTemplateName: '<template-guid>'
    // alertRuleTemplateVersion: '1.0.0'
  }
  dependsOn: [ sentinel, ingest, watchlists ]
}

// --- Automation rule (triage + run playbook) ---------------------------------
module automationRules 'modules/automationrules.bicep' = {
  name: 'lab-automation-rules'
  scope: rg
  params: {
    workspaceName: workspaceName
    playbookResourceId: playbook.outputs.playbookResourceId
  }
  dependsOn: [ sentinel, analyticsRules ]
}
