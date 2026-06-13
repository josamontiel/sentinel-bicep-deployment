// =============================================================================
//  securityevents-ama.bicep
//  "Windows Security Events via AMA" connector, expressed the modern way: a
//  Data Collection Rule that routes the Microsoft-SecurityEvent stream into the
//  workspace, plus (optionally) the Azure Monitor Agent and a DCR association on
//  each Windows VM you name.
//
//  Why a DCR and not Microsoft.SecurityInsights/dataConnectors: AMA-based
//  Security Events collection IS the DCR. It's an Azure Monitor resource, so it
//  is NOT subject to the connector-write block that Defender-portal-managed
//  ("primary") workspaces enforce on SecurityInsights/dataConnectors. RG scope.
// =============================================================================

@description('Name of the existing Log Analytics workspace (the data destination).')
param workspaceName string

@description('Location for the DCR. MUST match the region of the VMs you associate.')
param location string = resourceGroup().location

@description('Name of the Security Events DCR.')
param dcrName string = 'dcr-securityevents-ama'

@description('Which Windows Security events to collect.')
@allowed([ 'All', 'Common', 'Minimal', 'Custom' ])
param eventCollectionTier string = 'All'

@description('Custom xPath queries — only used when eventCollectionTier = Custom.')
param customXPathQueries array = []

@description('Names of existing Windows VMs in THIS resource group to install AMA on and associate with the DCR. Leave empty to deploy just the DCR (no data until something is associated).')
param windowsVmNames array = []

resource ws 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// 'All' is exact (Security!*). 'Common'/'Minimal' are compact high-signal
// subsets — adjust to the official Sentinel catalog lists if you need parity.
var xPathByTier = {
  All: [
    'Security!*'
  ]
  Common: [
    'Security!*[System[(EventID=1102 or EventID=4624 or EventID=4625 or EventID=4634 or EventID=4647 or EventID=4648 or EventID=4672 or EventID=4688 or EventID=4720 or EventID=4722 or EventID=4724 or EventID=4728 or EventID=4732 or EventID=4738 or EventID=4740 or EventID=4756 or EventID=4767 or EventID=4799)]]'
  ]
  Minimal: [
    'Security!*[System[(EventID=1102 or EventID=4624 or EventID=4625 or EventID=4688 or EventID=4720 or EventID=4740)]]'
  ]
}

var selectedXPaths = eventCollectionTier == 'Custom' ? customXPathQueries : xPathByTier[eventCollectionTier]

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  properties: {
    dataSources: {
      windowsEventLogs: [
        {
          name: 'securityEvents'
          streams: [ 'Microsoft-SecurityEvent' ]
          xPathQueries: selectedXPaths
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: ws.id
          name: 'law'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Microsoft-SecurityEvent' ]
        destinations: [ 'law' ]
      }
    ]
  }
}

// Existing Windows VMs to onboard (must already exist in this RG).
resource vms 'Microsoft.Compute/virtualMachines@2023-09-01' existing = [for name in windowsVmNames: {
  name: name
}]

// Azure Monitor Agent on each VM.
resource ama 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for (name, i) in windowsVmNames: {
  parent: vms[i]
  name: 'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}]

// Associate each VM with the Security Events DCR (this is what starts the flow).
resource assoc 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = [for (name, i) in windowsVmNames: {
  name: 'securityevents-dcra'
  scope: vms[i]
  properties: {
    dataCollectionRuleId: dcr.id
  }
  dependsOn: [
    ama[i]
  ]
}]

output dcrId string = dcr.id
output dcrName string = dcr.name
