#!/usr/bin/env bash
#
# simulate-attack.sh — POST synthetic events to SecurityLabEvents_CL so the lab
# detections fire. Requires the Monitoring Metrics Publisher role on the DCR
# (set ingestionPrincipalObjectId at deploy time, or assign it manually).
#
# Usage:
#   ./simulate-attack.sh <dce-logs-ingestion-endpoint> <dcr-immutable-id> [stream-name]
#
# Grab the first two args from the deployment outputs:
#   az deployment sub show -n sentinel-lab \
#     --query "properties.outputs" -o json
# (or read them from the 'lab-ingest' module deployment).
#
set -euo pipefail

DCE_ENDPOINT="${1:?DCE logs ingestion endpoint required (e.g. https://dce-...ingest.monitor.azure.com)}"
DCR_IMMUTABLE_ID="${2:?DCR immutable ID required (e.g. dcr-xxxxxxxx...)}"
STREAM="${3:-Custom-SecurityLabEvents_CL}"

TOKEN="$(az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv)"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 5 failures from one IP/user -> trips "Repeated sign-in failures".
# 1 event from 10.0.0.10 (on the HighValueAssets watchlist) -> trips the
# watchlist-join rule at High severity.
read -r -d '' PAYLOAD <<JSON || true
[
  {"TimeGenerated":"${NOW}","EventType":"SignInFailed","SourceIP":"45.83.12.7","UserPrincipalName":"alice@contoso.com","Result":"Failure","Country":"RU"},
  {"TimeGenerated":"${NOW}","EventType":"SignInFailed","SourceIP":"45.83.12.7","UserPrincipalName":"alice@contoso.com","Result":"Failure","Country":"RU"},
  {"TimeGenerated":"${NOW}","EventType":"SignInFailed","SourceIP":"45.83.12.7","UserPrincipalName":"alice@contoso.com","Result":"Failure","Country":"RU"},
  {"TimeGenerated":"${NOW}","EventType":"SignInFailed","SourceIP":"45.83.12.7","UserPrincipalName":"alice@contoso.com","Result":"Failure","Country":"RU"},
  {"TimeGenerated":"${NOW}","EventType":"SignInFailed","SourceIP":"45.83.12.7","UserPrincipalName":"alice@contoso.com","Result":"Failure","Country":"RU"},
  {"TimeGenerated":"${NOW}","EventType":"SignInFailed","SourceIP":"10.0.0.10","UserPrincipalName":"svc-backup@contoso.com","Result":"Failure","Country":"US"}
]
JSON

echo "Posting synthetic events to stream ${STREAM} ..."
HTTP_CODE="$(curl -sS -o /tmp/ingest_resp.txt -w '%{http_code}' -X POST \
  "${DCE_ENDPOINT}/dataCollectionRules/${DCR_IMMUTABLE_ID}/streams/${STREAM}?api-version=2023-01-01" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${PAYLOAD}")"

if [[ "${HTTP_CODE}" == "204" ]]; then
  echo "OK (HTTP 204). Events accepted."
  echo
  echo "Next:"
  echo "  - Data lands in SecurityLabEvents_CL in ~1-3 min."
  echo "  - Scheduled rules run every 10 min, so an incident appears within ~5-15 min."
  echo "  - Watch:  Sentinel > Incidents   (look for 'Lab —' titles, auto-bumped to High)"
  echo "  - Sanity-check ingestion in Logs:   SecurityLabEvents_CL | take 50"
else
  echo "Ingestion returned HTTP ${HTTP_CODE}:" >&2
  cat /tmp/ingest_resp.txt >&2
  echo >&2
  echo "Common causes: missing Monitoring Metrics Publisher role on the DCR," >&2
  echo "wrong DCE endpoint, or wrong DCR immutable ID." >&2
  exit 1
fi
