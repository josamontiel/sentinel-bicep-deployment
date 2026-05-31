# Microsoft Sentinel automation lab (Bicep)

End-to-end infrastructure-as-code that stands up a self-contained Microsoft
Sentinel environment for testing and learning. One `az deployment sub create`
gives you a resource group, a Log Analytics workspace, Sentinel onboarded on
top of it, a couple of basic data connectors switched on, and two starter
workbooks.

## What gets deployed

| Resource | Type | API version |
|---|---|---|
| Resource group | `Microsoft.Resources/resourceGroups` | 2024-03-01 |
| Log Analytics workspace | `Microsoft.OperationalInsights/workspaces` | 2023-09-01 |
| Sentinel onboarding | `Microsoft.SecurityInsights/onboardingStates` | 2024-09-01 |
| Defender for Cloud connector | `Microsoft.SecurityInsights/dataConnectors` (`AzureSecurityCenter`) | 2024-03-01 |
| Entra ID connector (optional) | `Microsoft.SecurityInsights/dataConnectors` (`AzureActiveDirectory`) | 2024-03-01 |
| Azure Activity → workspace | `Microsoft.Insights/diagnosticSettings` (subscription scope) | 2021-05-01-preview |
| Content Hub solutions | `Microsoft.SecurityInsights/contentPackages` (+ `contentProductPackages` read) | 2024-09-01 |
| Workbooks ×2 | `Microsoft.Insights/workbooks` | 2023-06-01 |

```
sentinel-lab/
├── main.bicep              # subscription-scoped orchestrator
├── main.bicepparam         # edit your values here
├── modules/
│   ├── loganalytics.bicep  # workspace
│   ├── sentinel.bicep      # onboarding + connectors
│   ├── contenthub.bicep    # Content Hub solution installs
│   └── workbooks.bicep      # loads the JSON definitions below
├── workbooks/
│   ├── activity-overview.json
│   └── sentinel-health.json
└── scripts/
    ├── deploy.sh           # validate → what-if → deploy
    └── teardown.sh         # delete the RG + subscription diag setting
```

## Why subscription scope

`main.bicep` uses `targetScope = 'subscription'` for two reasons: it creates the
resource group itself, and the modern Azure Activity connector is a
**subscription-level diagnostic setting** that routes the Activity log into the
workspace. Everything else is deployed into the resource group via modules.

## Prerequisites

- Azure CLI 2.50+ (`az version`). Bicep is bundled; run `az bicep upgrade` to be current.
- An Azure subscription you can deploy to.
- **RBAC to run the deployment:** `Owner` or `Contributor` + `User Access
  Administrator` at the subscription is the simplest. At minimum you need rights
  to create resource groups, write the workspace, write
  `Microsoft.SecurityInsights/*`, and write subscription diagnostic settings
  (`Monitoring Contributor`).

## Deploy

```bash
# 1. Pick your subscription
az account set --subscription "<your-sub-id>"

# 2. Edit main.bicepparam (names, region, which connectors)

# 3. Deploy (validates, shows a what-if, then prompts)
./scripts/deploy.sh eastus

# …or run it directly:
az deployment sub create \
  --name sentinel-lab \
  --location eastus \
  --template-file ./main.bicep \
  --parameters ./main.bicepparam
```

## Verify

1. Portal → **Microsoft Sentinel** → your workspace should be listed.
2. **Data connectors** → *Microsoft Defender for Cloud* shows Connected.
3. **Workbooks** → *My workbooks* → the two "Lab —" workbooks appear.
4. Activity data takes a few minutes to land. Check with:
   ```kusto
   AzureActivity | take 50
   ```

## Content Hub solutions

`modules/contenthub.bicep` installs Content Hub *solutions* — the modern,
packaged way to get Sentinel content. Each solution bundles a data connector
definition, workbook templates, analytics-rule templates, and hunting queries
into a single install. The defaults match the connectors this lab enables:

| Package ID | Solution |
|---|---|
| `azuresentinel.azure-sentinel-solution-azureactivity` | Azure Activity |
| `azuresentinel.azure-sentinel-solution-azureactivedirectory` | Microsoft Entra ID |
| `azuresentinel.azure-sentinel-solution-microsoftdefenderforcloud` | Microsoft Defender for Cloud |

Edit `contentHubSolutionPackageIds` in `main.bicepparam` to install more. Find
package IDs in the portal (**Content hub** → pick a solution → **View details** →
*Download a template for automation*, where the `name` of the
`contentPackages`/`contentProductPackages` resource is the ID), or browse the
[content hub catalog](https://learn.microsoft.com/azure/sentinel/sentinel-solutions-catalog).

**How the version stays current:** instead of hardcoding a solution version, the
module reads each package's live catalog entry (`contentProductPackages`, a
read-only resource) and installs exactly that version. Re-running the deployment
picks up newer published versions.

**What "install" does and doesn't do — important:** installing a solution makes
its content *available*. It does **not** automatically connect data sources or
turn rule templates into running rules. So the pieces relate like this:

- *Solution install* (this module) → puts the connector definition, workbook
  templates, and rule templates into your workspace.
- *Connector enablement* (`modules/sentinel.bicep` + the Azure Activity
  diagnostic setting) → actually starts the data flowing.
- *Analytics rules* → after install, go to **Analytics → Rule templates**, pick a
  template the solution added, and **Create rule** to make it active. (Want this
  automated too? Ask and I'll add a `Microsoft.SecurityInsights/alertRules`
  example that instantiates a template.)

There's intentional overlap with the standalone connectors: the solution gives
you the *content*, the connector resources give you the *data*. They coexist
cleanly — no conflict from running both.



- **Azure Activity** (`enableAzureActivity`, on by default) — fully functional
  from this template. The subscription diagnostic setting starts populating the
  `AzureActivity` table within minutes, no extra steps.
- **Defender for Cloud** (`enableDefenderForCloud`, on by default) — deploys
  cleanly. To actually receive alerts you also need Defender for Cloud enabled on
  the subscription; the connector just wires Sentinel to consume them.
- **Microsoft Entra ID** (`enableEntraId`, **off by default**) — the connector
  resource only flips the Sentinel-side toggle. Sign-in and audit logs flow only
  after a **tenant-level** diagnostic setting (`microsoft.aadiam/diagnosticSettings`)
  is created, which requires **Global Administrator** or **Security Administrator**
  and is a tenant-scoped operation outside this subscription-scoped template. It's
  left off so the lab deploys cleanly for anyone; enable it once you've handled the
  tenant side. Deploying the connector without the right tenant permissions can
  fail validation.

Many other connectors (Office 365, AWS, threat intel, etc.) have moved to the
Content Hub solution model and are best installed from there rather than as raw
`dataConnectors` resources.

## Cost guardrails

This is a lab, so the workspace ships with `dailyQuotaGb = 1` and
`immediatePurgeDataOn30Days = true`. Sentinel includes 90 days of free retention.
Raise `dailyQuotaGb` to `-1` (unlimited) only when you understand the ingestion
cost. The *Sentinel Ingestion & Alert Health* workbook helps you watch volume.

## Tear down

```bash
./scripts/teardown.sh rg-sentinel-lab
# Then remove the subscription-level diagnostic setting:
az monitor diagnostic-settings subscription delete --name sentinel-activity-to-law
```

## Customising

- **Add a connector:** add a `Microsoft.SecurityInsights/dataConnectors@2024-03-01`
  resource in `modules/sentinel.bicep`, scoped to the workspace, with a
  `dependsOn: [onboarding]`.
- **Add a workbook:** drop a new `*.json` into `workbooks/` and add a resource in
  `modules/workbooks.bicep` using `loadTextContent('../workbooks/<file>.json')`.
- The workbook JSON is the standard Azure Workbooks serialized format; you can
  build one in the portal, click *Edit → Advanced Editor → Gallery Template*, and
  paste it into a file here.
