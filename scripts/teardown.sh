#!/usr/bin/env bash
# Tear down the lab by deleting its resource group.
# Usage: ./scripts/teardown.sh [resource-group-name]
set -euo pipefail

RG="${1:-rg-sentinel-lab}"

echo "This will permanently delete resource group '$RG' and everything in it."
read -r -p "Type the resource group name to confirm: " confirm
[[ "$confirm" == "$RG" ]] || { echo "Name mismatch. Aborted."; exit 1; }

az group delete --name "$RG" --yes --no-wait
echo "Deletion started for '$RG' (running asynchronously)."
echo "Note: the subscription-level Activity diagnostic setting is removed separately:"
echo "  az monitor diagnostic-settings subscription delete --name sentinel-activity-to-law"
