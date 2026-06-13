// =============================================================================
//  playbook.bicep
//  The SOAR layer. A Logic App triggered by Sentinel incident creation that
//  POSTs incident details to a webhook (Teams/Slack/etc.). Uses a managed-
//  identity-authenticated Sentinel connection so there is NO interactive OAuth
//  consent step to deploy. RG scope.
//
//  Two role assignments:
//   - Microsoft Sentinel Responder (on the workspace) -> the playbook's identity,
//     so it can read incidents and comment back.
//   - Microsoft Sentinel Automation Contributor (on this RG) -> the Azure
//     Security Insights service principal, so automation rules can RUN this
//     playbook. Supply its object ID (scripts/get-sentinel-sp.sh) or assign later.
// =============================================================================

@description('Location for the Logic App and connection. Defaults to RG location.')
param location string = resourceGroup().location

@description('Name of the existing Log Analytics workspace Sentinel is onboarded to.')
param workspaceName string

@description('Playbook (Logic App) name.')
param playbookName string = 'pb-lab-notify'

@description('Incoming webhook URL (Teams/Slack/etc.) the playbook POSTs incident details to.')
param notificationWebhookUrl string

@description('Object ID of the Azure Security Insights SP (run scripts/get-sentinel-sp.sh). Leave empty to assign the Automation Contributor role manually later.')
param sentinelAutomationPrincipalObjectId string = ''

resource ws 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

var sentinelApiId = subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')

resource sentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azuresentinel-lab'
  location: location
  properties: {
    displayName: 'azuresentinel-lab'
    api: {
      id: sentinelApiId
    }
    // 'Alternative' = authenticate with the Logic App's managed identity,
    // which avoids an interactive consent click after deployment.
    parameterValueType: 'Alternative'
  }
}

resource playbook 'Microsoft.Logic/workflows@2019-05-01' = {
  name: playbookName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          type: 'Object'
          defaultValue: {}
        }
      }
      triggers: {
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        Post_to_webhook: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: notificationWebhookUrl
            body: {
              text: '@{concat(\'Sentinel incident: \', triggerBody()?[\'object\']?[\'properties\']?[\'title\'], \' | Severity: \', triggerBody()?[\'object\']?[\'properties\']?[\'severity\'], \' | Number: \', triggerBody()?[\'object\']?[\'properties\']?[\'incidentNumber\'])}'
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: sentinelConnection.id
            connectionName: sentinelConnection.name
            id: sentinelApiId
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
    }
  }
}

// Let the playbook identity read incidents and comment back.
resource responderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: ws
  name: guid(ws.id, playbook.id, 'sentinel-responder')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3e150937-b8fe-4cfb-8069-0eaf05ecd056')
    principalId: playbook.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Let Sentinel automation rules invoke this playbook.
resource automationContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(sentinelAutomationPrincipalObjectId)) {
  scope: resourceGroup()
  name: guid(resourceGroup().id, 'sentinel-automation-contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f4c81013-99ee-4d62-a7ee-b3f1f648599a')
    principalId: sentinelAutomationPrincipalObjectId
    principalType: 'ServicePrincipal'
  }
}

@description('Resource ID of the playbook — pass to the automation rule module.')
output playbookResourceId string = playbook.id

output playbookPrincipalId string = playbook.identity.principalId
