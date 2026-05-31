#!/usr/bin/env bash
# Deploy the Sentinel lab at subscription scope.
# Usage: ./scripts/deploy.sh [location]
set -euo pipefail

LOCATION="${1:-eastus}"
DEPLOY_NAME="sentinel-lab-$(date +%Y%m%d-%H%M%S)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Validating template..."
az deployment sub validate \
  --name "$DEPLOY_NAME" \
  --location "$LOCATION" \
  --template-file "$ROOT_DIR/main.bicep" \
  --parameters "$ROOT_DIR/main.bicepparam" \
  >/dev/null

echo "Previewing changes (what-if)..."
az deployment sub what-if \
  --name "$DEPLOY_NAME" \
  --location "$LOCATION" \
  --template-file "$ROOT_DIR/main.bicep" \
  --parameters "$ROOT_DIR/main.bicepparam"

read -r -p "Proceed with deployment? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo "Deploying..."
az deployment sub create \
  --name "$DEPLOY_NAME" \
  --location "$LOCATION" \
  --template-file "$ROOT_DIR/main.bicep" \
  --parameters "$ROOT_DIR/main.bicepparam"

echo "Done."
