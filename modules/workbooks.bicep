// Deploys lab workbooks. The workbook definition lives in ./../workbooks/*.json
// and is loaded as a string into the required `serializedData` property.
// sourceId binds the workbook to the Sentinel workspace; category 'sentinel'
// surfaces it under Microsoft Sentinel > Workbooks.

@description('Azure region.')
param location string

@description('Resource ID of the Log Analytics / Sentinel workspace.')
param workspaceResourceId string

@description('Resource tags.')
param tags object = {}

resource activityWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(workspaceResourceId, 'activity-overview')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Lab — Azure Activity Overview'
    category: 'sentinel'
    sourceId: workspaceResourceId
    version: 'Notebook/1.0'
    serializedData: loadTextContent('../workbooks/activity-overview.json')
  }
}

resource healthWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(workspaceResourceId, 'sentinel-health')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Lab — Sentinel Ingestion & Alert Health'
    category: 'sentinel'
    sourceId: workspaceResourceId
    version: 'Notebook/1.0'
    serializedData: loadTextContent('../workbooks/sentinel-health.json')
  }
}

output activityWorkbookId string = activityWorkbook.id
output healthWorkbookId string = healthWorkbook.id
