// =============================================================================
//  ingest.bicep
//  Synthetic-data path for the lab. Creates a custom Log Analytics table plus a
//  Data Collection Endpoint (DCE) and Data Collection Rule (DCR) so you can POST
//  fake security events with scripts/simulate-attack.sh and watch the analytics
//  rules fire. Deployed at resource-group scope.
// =============================================================================

@description('Name of the existing Log Analytics workspace Sentinel is onboarded to.')
param workspaceName string

@description('Location for the DCE / DCR. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Custom table name. Must end in _CL for custom-log ingestion.')
param customTableName string = 'SecurityLabEvents_CL'

@description('Data Collection Endpoint name.')
param dceName string = 'dce-sentinel-lab'

@description('Data Collection Rule name.')
param dcrName string = 'dcr-sentinel-lab'

@description('Object ID of the identity (you, or an app) that will POST events. Granted Monitoring Metrics Publisher on the DCR. Leave empty to assign the role manually later.')
param ingestionPrincipalObjectId string = ''

@description('Principal type for the ingestion identity.')
@allowed([ 'User', 'ServicePrincipal' ])
param ingestionPrincipalType string = 'User'

resource ws 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

var streamName = 'Custom-${customTableName}'

// Schema shared by the table and the DCR stream. Keep them identical.
var columns = [
  { name: 'TimeGenerated', type: 'datetime' }
  { name: 'EventType', type: 'string' }
  { name: 'SourceIP', type: 'string' }
  { name: 'UserPrincipalName', type: 'string' }
  { name: 'Result', type: 'string' }
  { name: 'Country', type: 'string' }
]

resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: ws
  name: customTableName
  properties: {
    schema: {
      name: customTableName
      columns: columns
    }
    retentionInDays: 30
    totalRetentionInDays: 30
  }
}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: dceName
  location: location
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      '${streamName}': {
        columns: columns
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: ws.id
          name: 'labWorkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ streamName ]
        destinations: [ 'labWorkspace' ]
        transformKql: 'source'
        outputStream: streamName
      }
    ]
  }
  dependsOn: [
    customTable
  ]
}

// Monitoring Metrics Publisher — required to POST to the Logs Ingestion API.
resource metricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(ingestionPrincipalObjectId)) {
  scope: dcr
  name: guid(dcr.id, ingestionPrincipalObjectId, 'metrics-publisher')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
    principalId: ingestionPrincipalObjectId
    principalType: ingestionPrincipalType
  }
}

@description('Logs Ingestion endpoint to POST events to (pass to simulate-attack.sh).')
output dceLogsIngestionEndpoint string = dce.properties.logsIngestion.endpoint

@description('DCR immutable ID used in the ingestion URL.')
output dcrImmutableId string = dcr.properties.immutableId

@description('Stream name used in the ingestion URL.')
output streamName string = streamName

output customTableName string = customTableName
