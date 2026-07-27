#!/usr/bin/env bash

set -euo pipefail

subscription_id="${AZURE_SUBSCRIPTION_ID:-}"
timeout_seconds=1800
poll_interval_seconds=15

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription-id)
      subscription_id="$2"
      shift 2
      ;;
    --timeout-seconds)
      timeout_seconds="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$subscription_id" ]]; then
  echo "A subscription ID is required." >&2
  exit 2
fi

az account set --subscription "$subscription_id"

feature_namespace='Microsoft.Network'
feature_name='AllowBringYourOwnPublicIpAddress'
deadline=$((SECONDS + timeout_seconds))

while true; do
  state=$(az feature show \
    --namespace "$feature_namespace" \
    --name "$feature_name" \
    --subscription "$subscription_id" \
    --query properties.state \
    --output tsv 2>/dev/null || true)

  if [[ "$state" == 'Registered' ]]; then
    break
  fi

  echo "Registering $feature_namespace/$feature_name (current state: ${state:-Unknown})"
  az feature register \
    --namespace "$feature_namespace" \
    --name "$feature_name" \
    --subscription "$subscription_id" \
    --only-show-errors >/dev/null || true

  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for $feature_namespace/$feature_name to register." >&2
    exit 1
  fi

  sleep "$poll_interval_seconds"
done

az provider register \
  --namespace Microsoft.Network \
  --subscription "$subscription_id" \
  --wait \
  --only-show-errors

echo "$feature_namespace/$feature_name is registered."