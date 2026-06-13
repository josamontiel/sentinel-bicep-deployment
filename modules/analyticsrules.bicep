// =============================================================================
//  analyticsrules.bicep
//  The detection layer the base repo left as a TODO. Two custom scheduled rules
//  over the SecurityLabEvents_CL table, plus an optional rule instantiated from
//  a Content Hub template. Sentinel rules are extension resources on the
//  workspace, so everything is scoped to `ws`. RG scope.
// =============================================================================

@description('Name of the existing Log Analytics workspace Sentinel is onboarded to.')
param workspaceName string

@description('Watchlist alias used by the watchlist-join detection.')
param watchlistAlias string = 'HighValueAssets'

@description('Instantiate an analytics rule from an installed Content Hub rule template.')
param enableTemplateRule bool = false

@description('GUID name of the Content Hub rule template. Required when enableTemplateRule = true.')
param alertRuleTemplateName string = ''

@description('Template version, e.g. 1.0.4. Required when enableTemplateRule = true.')
param alertRuleTemplateVersion string = ''

@description('Severity for the template-instantiated rule.')
@allowed([ 'Informational', 'Low', 'Medium', 'High' ])
param templateRuleSeverity string = 'Medium'

resource ws 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// --- Detection 1: repeated sign-in failures (possible brute force) -----------
resource bruteForce 'Microsoft.SecurityInsights/alertRules@2024-09-01' = {
  scope: ws
  name: guid(ws.id, 'lab-brute-force')
  kind: 'Scheduled'
  properties: {
    displayName: 'Lab — Repeated sign-in failures (possible brute force)'
    description: 'Five or more failed sign-in events from the same source IP and user within 10 minutes.'
    severity: 'Medium'
    enabled: true
    query: '''
SecurityLabEvents_CL
| where EventType == "SignInFailed"
| summarize FailedAttempts = count(), Countries = make_set(Country) by UserPrincipalName, SourceIP, bin(TimeGenerated, 10m)
| where FailedAttempts >= 5
'''
    queryFrequency: 'PT10M'
    queryPeriod: 'PT10M'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: [ 'CredentialAccess' ]
    techniques: [ 'T1110' ]
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: 'PT5H'
        matchingMethod: 'Selected'
        groupByEntities: [ 'Account', 'IP' ]
        groupByAlertDetails: []
        groupByCustomDetails: []
      }
    }
    entityMappings: [
      {
        entityType: 'Account'
        fieldMappings: [ { identifier: 'FullName', columnName: 'UserPrincipalName' } ]
      }
      {
        entityType: 'IP'
        fieldMappings: [ { identifier: 'Address', columnName: 'SourceIP' } ]
      }
    ]
  }
}

// --- Detection 2: activity touching a high-value asset (watchlist join) ------
// Multi-line strings can't interpolate, so build the query with format().
var watchlistQuery = format('let hva = _GetWatchlist("{0}") | project SearchKey = tostring(SearchKey);\nSecurityLabEvents_CL\n| where EventType in ("SignInFailed", "SignInSuccess")\n| where SourceIP in (hva)\n| project TimeGenerated, EventType, UserPrincipalName, SourceIP, Country, Result', watchlistAlias)

resource watchlistHit 'Microsoft.SecurityInsights/alertRules@2024-09-01' = {
  scope: ws
  name: guid(ws.id, 'lab-watchlist-hit')
  kind: 'Scheduled'
  properties: {
    displayName: 'Lab — Suspicious activity involving a high-value asset'
    description: 'Any sign-in event whose source IP matches an entry on the HighValueAssets watchlist.'
    severity: 'High'
    enabled: true
    query: watchlistQuery
    queryFrequency: 'PT10M'
    queryPeriod: 'PT10M'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: [ 'InitialAccess' ]
    techniques: [ 'T1078' ]
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: false
        reopenClosedIncident: false
        lookbackDuration: 'PT5H'
        matchingMethod: 'AllEntities'
        groupByEntities: []
        groupByAlertDetails: []
        groupByCustomDetails: []
      }
    }
    entityMappings: [
      {
        entityType: 'Account'
        fieldMappings: [ { identifier: 'FullName', columnName: 'UserPrincipalName' } ]
      }
      {
        entityType: 'IP'
        fieldMappings: [ { identifier: 'Address', columnName: 'SourceIP' } ]
      }
    ]
  }
}

// --- Detection 3 (optional): instantiate a Content Hub rule template ---------
// The base repo installs solutions but never turns a template into a live rule.
// This does exactly that. Off by default — set enableTemplateRule and supply the
// template name/version (find them via Content hub > solution > "Download a
// template for automation", or the alertRuleTemplates REST API).
resource templateRule 'Microsoft.SecurityInsights/alertRules@2024-09-01' = if (enableTemplateRule) {
  scope: ws
  name: guid(ws.id, 'lab-template-rule')
  kind: 'Scheduled'
  properties: {
    displayName: 'Lab — Instantiated from Content Hub template'
    enabled: true
    alertRuleTemplateName: alertRuleTemplateName
    templateVersion: alertRuleTemplateVersion
    // These fields are still required by the API even when linking a template.
    // Replace with the template's real values; the placeholders below let you
    // smoke-test the wiring without an alert storm.
    severity: templateRuleSeverity
    query: 'SecurityLabEvents_CL | take 0'
    queryFrequency: 'PT1H'
    queryPeriod: 'PT1H'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
  }
}

output bruteForceRuleId string = bruteForce.id
output watchlistHitRuleId string = watchlistHit.id
