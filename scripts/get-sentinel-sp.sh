#!/usr/bin/env bash
#
# get-sentinel-sp.sh — print the object ID of the "Azure Security Insights"
# first-party service principal. This is the identity Sentinel automation rules
# run as; it needs Microsoft Sentinel Automation Contributor on the playbook's
# resource group to invoke a playbook. Feed the output into
# sentinelAutomationPrincipalObjectId in main.bicepparam.
#
set -euo pipefail

# Well-known app ID of the Azure Security Insights first-party app.
APP_ID="98785600-1bb7-4fb9-b9fa-19afe2c8a360"

OBJ_ID="$(az ad sp show --id "${APP_ID}" --query id -o tsv 2>/dev/null || true)"

if [[ -z "${OBJ_ID}" ]]; then
  echo "Could not resolve the Azure Security Insights SP in this tenant." >&2
  echo "It is created the first time Sentinel is used. If you just onboarded," >&2
  echo "wait a few minutes, or create it explicitly with:" >&2
  echo "  az ad sp create --id ${APP_ID}" >&2
  exit 1
fi

echo "sentinelAutomationPrincipalObjectId = ${OBJ_ID}"
