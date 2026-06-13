# Microsoft Sentinel automation lab (Bicep) — detection & response edition

End-to-end infrastructure-as-code that stands up a self-contained Microsoft
Sentinel environment **and** the operational layer on top of it: custom
detections, incident-triage automation, a response playbook, a watchlist, a
Windows Security Events (AMA) connector, and a synthetic-data path so you can
trigger the whole pipeline on demand.

This extends the original
[`sentinel-bicep-deployment`](https://github.com/josamontiel/sentinel-bicep-deployment)
(workspace + Sentinel onboarding + connectors + Content Hub + workbooks) by
filling the gap its README flagged — turning installed *content* into running
*detections and responses*.

## The loop this builds

```
simulate-attack.sh ─► SecurityLabEvents_CL ─► analytics rule ─► incident
                                                                    │
                                                automation rule ◄───┘
                                                (severity, tag, run playbook)
                                                                    │
                                                              playbook (Logic App)
                                                              ─► webhook notification
```

The detections also read a `HighValueAssets` watchlist, and a separate Windows
Security Events (AMA) connector can feed the real `SecurityEvent` table in
parallel.

## What gets deployed

| Resource | Type | Source |
| --- | --- | --- |
| Resource group | `Microsoft.Resources/resourceGroups` | base |
| Log Analytics workspace | `Microsoft.OperationalInsights/workspaces` | base |
| Sentinel onboarding | `Microsoft.SecurityInsights/onboardingStates` | base (gated) |
| Azure Activity → workspace | `Microsoft.Insights/diagnosticSettings` (sub scope) | base |
| Data connectors (optional) | `Microsoft.SecurityInsights/dataConnectors` | base (gated, off by default) |
| Content Hub solutions (optional) | `Microsoft.SecurityInsights/contentPackages` | base |
| Workbooks ×2 | `Microsoft.Insights/workbooks` | base |
| Security Events via AMA | `Microsoft.Insights/dataCollectionRules` (+ AMA, associations) | extension |
| Custom table + DCE + DCR | `…/tables`, `dataCollectionEndpoints`, `dataCollectionRules` | extension |
| Watchlist | `Microsoft.SecurityInsights/watchlists` | extension |
| Analytics rules ×2 (+optional template) | `Microsoft.SecurityInsights/alertRules` | extension |
| Automation rule | `Microsoft.SecurityInsights/automationRules` | extension |
| Playbook (Logic App) + connection | `Microsoft.Logic/workflows`, `Microsoft.Web/connections` | extension |
| Role assignments | `Microsoft.Authorization/roleAssignments` | extension |

## Repository structure

```
sentinel-automation/
├── main.bicep                      # subscription-scoped orchestrator
├── main.bicepparam                 # your values
├── README.md                       # this file
├── modules/
│   ├── loganalytics.bicep          # workspace
│   ├── sentinel.bicep              # onboarding + connectors (both gated)
│   ├── contenthub.bicep            # Content Hub solution installs
│   ├── workbooks.bicep             # workbook loader
│   ├── securityevents-ama.bicep    # Windows Security Events via AMA (DCR)
│   ├── ingest.bicep                # custom table + DCE + DCR (synthetic data)
│   ├── watchlists.bicep            # HighValueAssets watchlist
│   ├── analyticsrules.bicep        # 2 detections (+ optional template rule)
│   ├── automationrules.bicep       # incident triage automation
│   └── playbook.bicep              # Logic App + connection + role assignments
├── workbooks/
│   ├── activity-overview.json
│   └── sentinel-health.json
├── watchlists/
│   └── high-value-assets.csv
└── scripts/
    ├── deploy.sh                   # validate → what-if → deploy
    ├── teardown.sh                 # delete RG + sub diag setting
    ├── simulate-attack.sh          # POST synthetic events
    └── get-sentinel-sp.sh          # resolve the Sentinel SP object ID
```

## Prerequisites

- Azure CLI 2.50+ (`az version`); run `az bicep upgrade` to get current.
- An Azure subscription you can deploy to.
- RBAC: because the extension creates role assignments, `Owner`, or
  `Contributor` + `User Access Administrator` at the subscription, is simplest.
- For the response playbook: a Teams or Slack incoming webhook URL.

## Important: Defender-portal-managed ("unified SecOps") workspaces

If your workspace is onboarded to the Microsoft Defender portal (unified
security operations), Microsoft **blocks connector writes through ARM/Bicep**.
You'll see:

> The workspace is enabled through the Microsoft Threat Protection Portal.
> Changes to the connector in Microsoft Sentinel are disabled.

This is a platform rule, not a template bug. The lab is configured to coexist
with it:

- **`Microsoft.SecurityInsights/dataConnectors` are gated off** in
  `sentinel.bicep` (`deployDataConnectors = false`). Manage those connectors
  from the Defender portal instead.
- **Security Events via AMA still works in code**, because it's a Data
  Collection Rule (an Azure Monitor resource), not a `dataConnectors` write — so
  it isn't subject to the block. That's why this lab does Security Events as a
  DCR.
- **Sentinel onboarding** is also gated (`onboardSentinel`). On a workspace
  already onboarded via the Defender portal you can leave it `true` (the PUT is
  idempotent and succeeds) or set it `false` if a re-PUT is rejected.

### Recommended parameter values for a Defender-managed workspace

```bicep
param onboardSentinel = true            // (in the sentinel module call)
param deployDataConnectors = false      // connectors managed in the Defender portal
param enableAzureActivity = true        // sub diagnostic setting — always works
param enableSecurityEventsAma = true    // DCR — works in code
param installContentHubSolutions = false // see Content Hub note below
```

## Configure

Edit `main.bicepparam`. Key parameters:

| Parameter | Default | Notes |
| --- | --- | --- |
| `location` | `eastus` | Region for everything. AMA VM associations must match this. |
| `workspaceName` | `law-sentinel-lab` | Existing or new workspace name. |
| `dailyQuotaGb` | `1` | Lab spend guard. `-1` = unlimited. |
| `enableAzureActivity` | `true` | Subscription Activity log → workspace. |
| `deployDataConnectors` | `false` | Keep false on Defender-managed workspaces. |
| `enableSecurityEventsAma` | `true` | Deploys the Security Events DCR. |
| `securityEventsTier` | `All` | `All` / `Common` / `Minimal` / `Custom`. |
| `securityEventsVmNames` | `[]` | Existing Windows VM names to onboard with AMA. |
| `installContentHubSolutions` | `false` | See note below. |
| `notificationWebhookUrl` | — | Teams/Slack webhook for the playbook (required). |
| `sentinelAutomationPrincipalObjectId` | `''` | Run `scripts/get-sentinel-sp.sh`. |
| `ingestionPrincipalObjectId` | `''` | Your object ID for posting synthetic events. |

Helper lookups:

```bash
./scripts/get-sentinel-sp.sh                          # automation SP object ID
az ad signed-in-user show --query id -o tsv           # your object ID
```

## Deploy

```bash
az account set --subscription "<your-sub-id>"

# Always preview first
az deployment sub what-if \
  --name sentinel-lab \
  --location eastus \
  --template-file ./main.bicep \
  --parameters ./main.bicepparam

# Then deploy
./scripts/deploy.sh eastus
# …or directly:
az deployment sub create \
  --name sentinel-lab \
  --location eastus \
  --template-file ./main.bicep \
  --parameters ./main.bicepparam
```

If `deploy.sh` references `main.json`, regenerate it after any Bicep edit
(`az bicep build --file ./main.bicep`) or deploy `main.bicep` directly — a stale
`main.json` will silently ignore your changes.

## Verify

1. **Sentinel → your workspace** is listed.
2. Activity data lands within minutes: `AzureActivity | take 50`.
3. Security Events (once a VM is associated): `SecurityEvent | take 50`.
4. Workbooks appear under **Workbooks → My workbooks** ("Lab —").

## Run the detection loop

Grab the ingestion outputs, then fire synthetic events:

```bash
az deployment sub show -n sentinel-lab --query "properties.outputs" -o json
# Use dceLogsIngestionEndpoint + dcrImmutableId from the lab-ingest module.

./scripts/simulate-attack.sh "<dceLogsIngestionEndpoint>" "<dcrImmutableId>"
```

The payload trips two rules: **Repeated sign-in failures** (5 failures from one
IP) and **Suspicious activity involving a high-value asset** (an event from
`10.0.0.10`, which is on the `HighValueAssets` watchlist). Within ~5–15 minutes
you should see `Lab —` incidents in **Sentinel → Incidents**, auto-bumped to
High and tagged `lab`, with the playbook posting to your webhook.

## Security Events via AMA

`modules/securityevents-ama.bicep` is the connector, expressed as a Data
Collection Rule routing `Microsoft-SecurityEvent` into the workspace. The DCR is
the connector; data only flows once it's associated with a Windows machine
running the Azure Monitor Agent.

- **DCR only** (`securityEventsVmNames = []`): connector shows configured, but
  `SecurityEvent` stays empty.
- **With VMs**: list existing Windows VM names (same RG, same region as
  `location`). The module installs AMA and creates the association, and data
  begins flowing.

Switch `securityEventsTier` to `Common` to cut volume. The `Common`/`Minimal`
xPath lists in the module are compact high-signal subsets, not the verbatim
official catalog lists.

## Content Hub solutions

`installContentHubSolutions` defaults to **off**. On Defender-managed workspaces
the module's "read the catalog entry to get the latest version"
(`contentProductPackages`) step can return **404** even though the portal shows
the solutions connected — the portal state comes from the Defender side, which
isn't the same object the ARM read targets.

Options:

- **Recommended:** leave it `false` and install/manage solutions from the
  Defender portal's Content hub. The lab's detections don't depend on them.
- **In code:** rewrite `contenthub.bicep` to install `contentPackages` with an
  explicit pinned `version` per package, dropping the `contentProductPackages`
  read that 404s. Confirm what's installed first:

```bash
az rest --method get \
  --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/rg-sentinel-lab/providers/Microsoft.OperationalInsights/workspaces/law-sentinel-lab/providers/Microsoft.SecurityInsights/contentPackages?api-version=2024-09-01"
```

## Data connectors

On a Defender-managed workspace, enable Defender for Cloud / Entra ID connectors
from the **Defender portal**, not Bicep. Content Hub solutions also bundle
connector definitions, so connectors can appear "connected" after a solution
install or a portal refresh without any `dataConnectors` ARM resource. "Connected"
in the UI is not the same as data flowing — verify with a table query.

To keep connectors in code, deploy the lab against a **separate, non-Defender-
managed workspace**; the ARM block applies only to the primary workspace, so
`deployDataConnectors = true` succeeds there.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `BadRequest` — "enabled through the Microsoft Threat Protection Portal" on `deploy-sentinel` | ARM connector/onboarding write on a Defender-managed workspace | `deployDataConnectors = false`; if it's the onboarding op, `onboardSentinel = false` |
| `404` on `contentProductPackages` (`deploy-contenthub`) | Catalog-version read not resolvable on this workspace | `installContentHubSolutions = false`, or pin versions (see above) |
| `BCP037` "property X is not allowed on objects of type params" | Module call passes a param the module file doesn't declare | The edited module file wasn't saved over the repo file — overwrite it |
| Edits "don't take" between deploys | Deploying a stale compiled `main.json` | Deploy `main.bicep`, or rebuild `main.json` |
| `SecurityEvent` empty after AMA deploy | No VM associated, or VM region ≠ DCR region | Add `securityEventsVmNames`; match `location` |

To see exactly which resource failed inside a module:

```bash
az deployment operation group list -g rg-sentinel-lab -n <module-deployment-name> \
  --query "[?properties.provisioningState=='Failed'].{type:properties.targetResource.resourceType, name:properties.targetResource.resourceName, msg:properties.statusMessage}" \
  -o jsonc
```

## Cost guardrails

The workspace ships with `dailyQuotaGb = 1` and Sentinel's 90-day free
retention. AMA `All`-tier Security Events and any associated VM are the main
cost drivers — use `Common`, stop/deallocate lab VMs when idle, and raise the
quota only when you understand the ingestion cost.

## Tear down

```bash
./scripts/teardown.sh rg-sentinel-lab
# Then remove the subscription-level diagnostic setting:
az monitor diagnostic-settings subscription delete --name sentinel-activity-to-law
```

Deleting the resource group removes everything deployed into it (workspace,
Sentinel content, rules, automation, playbook, DCRs, watchlist, and the
RG-scoped role assignments). Connectors and solutions you enabled in the Defender
portal are managed there and may need separate cleanup.
