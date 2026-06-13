# Extension: "Close the loop" — detection & response pipeline

This extends [`sentinel-bicep-deployment`](https://github.com/josamontiel/sentinel-bicep-deployment)
from a SIEM that has content *available* into one that actually **detects and
responds** — and lets you trigger it on demand with synthetic data.

The base repo stands up the workspace, onboards Sentinel, wires connectors, and
installs Content Hub solutions. Its README explicitly leaves the `alertRules`
example as a TODO. This fills that gap and adds the layers above it:

```
synthetic event  ─►  custom table  ─►  analytics rule  ─►  incident
                                                              │
                                          automation rule ◄───┘
                                          (triage: severity, tag, run playbook)
                                                              │
                                                        playbook (Logic App)
                                                        ─► webhook notification
```

## What this adds

| File | Purpose |
| --- | --- |
| `modules/ingest.bicep` | Custom table `SecurityLabEvents_CL` + Data Collection Endpoint + Data Collection Rule, so you can POST fake events. |
| `modules/watchlists.bicep` | `HighValueAssets` watchlist seeded from a CSV. |
| `modules/analyticsrules.bicep` | Two custom scheduled detections (brute force; watchlist join) + an optional rule instantiated from a Content Hub template. |
| `modules/automationrules.bicep` | Triage automation: bump severity, set Active, tag, run the playbook. |
| `modules/playbook.bicep` | Logic App triggered by incident creation; POSTs to a webhook. MSI-auth connection (no interactive consent) + the two needed role assignments. |
| `watchlists/high-value-assets.csv` | Watchlist seed data (`SearchKey` = IP). |
| `scripts/simulate-attack.sh` | POSTs synthetic events that trip the detections. |
| `scripts/get-sentinel-sp.sh` | Resolves the Azure Security Insights SP object ID. |
| `main.extension.bicep` | Wiring reference to merge into your `main.bicep`. |
| `main.bicepparam.additions` | New params to append to `main.bicepparam`. |

## Install

1. Copy `modules/*.bicep`, `watchlists/`, and `scripts/` into the repo (alongside
   the existing folders of the same name).
2. Merge `main.extension.bicep` into your `main.bicep`. It assumes your file
   already has `param location`, `param workspaceName`, a `resource rg`, and a
   `module sentinel`. Rename `rg` / `sentinel` to match your symbols.
3. Append `main.bicepparam.additions` to `main.bicepparam` and fill in:
   - `notificationWebhookUrl` — a Teams or Slack incoming webhook (required).
   - `sentinelAutomationPrincipalObjectId` — run `./scripts/get-sentinel-sp.sh`.
   - `ingestionPrincipalObjectId` — your object ID:
     `az ad signed-in-user show --query id -o tsv`.
4. `chmod +x scripts/*.sh` (the exec bit may not survive copying).

Then validate and deploy as the base repo already does:

```bash
az bicep build --file ./main.bicep        # syntax check
./scripts/deploy.sh eastus                 # validate -> what-if -> deploy
```

## Run the loop

After deployment, grab the ingestion outputs:

```bash
az deployment sub show -n sentinel-lab --query "properties.outputs" -o json
# or inspect the 'lab-ingest' module deployment for:
#   dceLogsIngestionEndpoint, dcrImmutableId, streamName
```

Fire synthetic events:

```bash
./scripts/simulate-attack.sh \
  "<dceLogsIngestionEndpoint>" \
  "<dcrImmutableId>"
```

The payload sends five failed sign-ins from one IP (trips **Repeated sign-in
failures**, Medium) and one event from `10.0.0.10` — an entry on the
`HighValueAssets` watchlist (trips **Suspicious activity involving a high-value
asset**, High). Within ~5–15 minutes:

1. Data appears: `SecurityLabEvents_CL | take 50`.
2. **Sentinel → Incidents** shows `Lab —` incidents.
3. The automation rule has bumped them to High, set Active, and tagged `lab`.
4. The playbook posts to your webhook (and, with the Responder role, can comment
   back on the incident).

## RBAC notes

This needs a bit more than the base repo. The deploying principal needs to create
role assignments, so `Owner`, or `Contributor` + `User Access Administrator`, at
the subscription is simplest. The three assignments created:

- **Monitoring Metrics Publisher** on the DCR → your ingestion identity (so the
  script can POST). Skipped if `ingestionPrincipalObjectId` is empty — assign it
  later in the portal.
- **Microsoft Sentinel Responder** on the workspace → the playbook's managed
  identity (read incidents, comment back).
- **Microsoft Sentinel Automation Contributor** on the RG → the Azure Security
  Insights SP (so automation rules can run the playbook). Skipped if
  `sentinelAutomationPrincipalObjectId` is empty.

If you leave the two optional IDs empty, everything still deploys — you just
assign those roles by hand before the script / playbook-run will work.

## Why MSI on the playbook connection

The Sentinel API connection uses `parameterValueType: 'Alternative'` so it
authenticates with the Logic App's managed identity. That avoids the usual
post-deploy "authorize the connection" OAuth click, keeping the lab fully
hands-off after `deploy.sh`. The only external input is the webhook URL.

## Optional: instantiate a Content Hub rule template

The base repo installs solutions but never turns a rule template into a live
rule. `analyticsrules.bicep` can do that — set in the `analyticsRules` module:

```bicep
enableTemplateRule: true
alertRuleTemplateName: '<template-guid>'
alertRuleTemplateVersion: '1.0.0'
```

Find the GUID/version via **Content hub → solution → Download a template for
automation**, or the `alertRuleTemplates` REST API. Copy the template's real
`query`/`severity`/scheduling values into the resource (the placeholders there
just let you smoke-test the wiring).

## Tear down

The base repo's `teardown.sh` deletes the RG, which removes everything here too
(table, DCE, DCR, watchlist, rules, automation rule, playbook, and the
RG-scoped role assignment). The subscription-level Activity diagnostic setting is
still removed separately, as documented in the base repo.

## Not compile-tested in this bundle

These files were authored against the documented API versions but not built in
this environment. Run `az bicep build --file ./main.bicep` and an
`az deployment sub what-if` first; fix any drift in API versions for your
tenant if Bicep flags it.
