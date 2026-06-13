// =============================================================================
//  automationrules.bicep
//  No-code triage. On creation of any "Lab —" incident: bump severity, set
//  Active, tag it, and (if a playbook ID is supplied) run the response playbook.
//  automationRules names must be GUIDs. RG scope.
// =============================================================================

@description('Name of the existing Log Analytics workspace Sentinel is onboarded to.')
param workspaceName string

@description('Resource ID of the playbook to run on incident creation. Empty = skip the RunPlaybook action.')
param playbookResourceId string = ''

@description('Tenant ID for the RunPlaybook action.')
param tenantId string = tenant().tenantId

resource ws 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

var runPlaybookAction = empty(playbookResourceId) ? [] : [
  {
    order: 2
    actionType: 'RunPlaybook'
    actionConfiguration: {
      logicAppResourceId: playbookResourceId
      tenantId: tenantId
    }
  }
]

resource triage 'Microsoft.SecurityInsights/automationRules@2024-09-01' = {
  scope: ws
  name: guid(ws.id, 'lab-triage-automation')
  properties: {
    displayName: 'Lab — Triage incoming lab incidents'
    order: 1
    triggeringLogic: {
      isEnabled: true
      triggersOn: 'Incidents'
      triggersWhen: 'Created'
      conditions: [
        {
          conditionType: 'Property'
          conditionProperties: {
            propertyName: 'IncidentTitle'
            operator: 'Contains'
            propertyValues: [ 'Lab —' ]
          }
        }
      ]
    }
    actions: concat([
      {
        order: 1
        actionType: 'ModifyProperties'
        actionConfiguration: {
          severity: 'High'
          status: 'Active'
          labels: [
            {
              labelName: 'lab'
            }
          ]
        }
      }
    ], runPlaybookAction)
  }
}
