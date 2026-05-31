// Installs Microsoft Sentinel Content Hub *solutions*. A solution is a package
// that bundles content — data connector definitions, workbook templates,
// analytics-rule templates, hunting queries, playbooks — into one install.
//
// Pattern: read each package's live catalog entry (contentProductPackages, an
// existing/read-only resource) and install that exact version (contentPackages).
// Reading the catalog means the version is never hardcoded and never goes stale.
//
// NOTE: installing a solution makes its content *available* (e.g. rule
// templates, workbook templates, connector definitions). It does not, by
// itself, connect data sources or create active analytics rules — those are
// separate enablement steps. See the README.

@description('Name of the existing Sentinel-enabled Log Analytics workspace.')
param workspaceName string

@description('Content Hub solution package IDs to install (the offer-style id, e.g. azuresentinel.azure-sentinel-solution-azureactivity).')
param solutionPackageIds array

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// Read-only catalog entries — one per requested solution.
resource catalog 'Microsoft.SecurityInsights/contentProductPackages@2024-09-01' existing = [
  for id in solutionPackageIds: {
    scope: workspace
    name: id
  }
]

// Install each solution at the version currently published in the catalog.
resource install 'Microsoft.SecurityInsights/contentPackages@2024-09-01' = [
  for (id, i) in solutionPackageIds: {
    scope: workspace
    name: id
    properties: {
      contentId: catalog[i].properties.contentId
      contentKind: catalog[i].properties.contentKind
      contentProductId: catalog[i].properties.contentProductId
      displayName: catalog[i].properties.displayName
      version: catalog[i].properties.version
    }
  }
]
