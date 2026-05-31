// Onboards an existing Log Analytics workspace to Microsoft Sentinel and wires
// up data connectors. Connectors are declared as extension resources scoped to
// the workspace, and each depends on the onboarding state existing first.

@description('Name of the existing Log Analytics workspace to onboard.')
param workspaceName string

@description('Enable the Microsoft Defender for Cloud connector.')
param enableDefenderForCloud bool = true

@description('Enable the Microsoft Entra ID connector (see README for the extra tenant-level requirements).')
param enableEntraId bool = false

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// Turn the workspace into a Microsoft Sentinel workspace.
resource onboarding 'Microsoft.SecurityInsights/onboardingStates@2024-09-01' = {
  scope: workspace
  name: 'default'
  properties: {}
}

// ---- Microsoft Defender for Cloud (formerly Azure Security Center) ----------
resource defenderForCloud 'Microsoft.SecurityInsights/dataConnectors@2024-03-01' = if (enableDefenderForCloud) {
  scope: workspace
  name: guid(workspace.id, 'AzureSecurityCenter')
  kind: 'AzureSecurityCenter'
  properties: {
    subscriptionId: subscription().subscriptionId
    dataTypes: {
      alerts: {
        state: 'enabled'
      }
    }
  }
  dependsOn: [
    onboarding
  ]
}

// ---- Microsoft Entra ID (optional) ------------------------------------------
// The connector resource flips the toggle, but sign-in/audit logs only flow
// once a tenant-level diagnostic setting is configured by a Global Admin.
resource entraId 'Microsoft.SecurityInsights/dataConnectors@2024-03-01' = if (enableEntraId) {
  scope: workspace
  name: guid(workspace.id, 'AzureActiveDirectory')
  kind: 'AzureActiveDirectory'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      alerts: {
        state: 'enabled'
      }
    }
  }
  dependsOn: [
    onboarding
  ]
}
