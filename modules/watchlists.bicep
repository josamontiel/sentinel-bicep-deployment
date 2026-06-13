// =============================================================================
//  watchlists.bicep
//  A Sentinel watchlist seeded from a CSV. One analytics rule joins against this
//  via _GetWatchlist() so you can see watchlist-driven detection. RG scope.
// =============================================================================

@description('Name of the existing Log Analytics workspace Sentinel is onboarded to.')
param workspaceName string

@description('Watchlist alias — how KQL references it: _GetWatchlist("<alias>").')
param watchlistAlias string = 'HighValueAssets'

@description('Raw CSV content (first row = headers). Pass via loadTextContent().')
param watchlistCsv string

resource ws 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource watchlist 'Microsoft.SecurityInsights/watchlists@2024-09-01' = {
  scope: ws
  name: watchlistAlias
  properties: {
    displayName: 'Lab — High Value Assets'
    source: 'high-value-assets.csv'
    provider: 'SentinelLab'
    description: 'IPs of Tier 0/1 assets. Activity touching these escalates to High.'
    itemsSearchKey: 'SearchKey'
    contentType: 'text/csv'
    numberOfLinesToSkip: 0
    rawContent: watchlistCsv
  }
}

output watchlistAlias string = watchlistAlias
