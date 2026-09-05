#!/usr/bin/env bash
# Zoho Mail API - Shared Auth Module
# Uses injected environment variables and manages access token refresh.
#
# Usage: source this file from other scripts.
#   source "$(dirname "$0")/auth.sh"
#   TOKEN=$(get_access_token)
#
# Required env vars: ZOHO_CLIENT_ID, ZOHO_CLIENT_SECRET, ZOHO_REFRESH_TOKEN

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_CACHE="$SCRIPT_DIR/.zoho_token_cache"

# Validate required vars
for var in ZOHO_CLIENT_ID ZOHO_CLIENT_SECRET ZOHO_REFRESH_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var environment variable is not set" >&2
    exit 1
  fi
done

get_access_token() {
  # Check cache (tokens last ~3600s, we refresh at 3000s to be safe)
  if [[ -f "$TOKEN_CACHE" ]]; then
    local cached_token cached_time now
    cached_token=$(jq -r '.access_token' "$TOKEN_CACHE" 2>/dev/null || echo "")
    cached_time=$(jq -r '.timestamp' "$TOKEN_CACHE" 2>/dev/null || echo "0")
    now=$(date +%s)
    if [[ -n "$cached_token" && "$cached_token" != "null" ]] && (( now - cached_time < 3000 )); then
      echo "$cached_token"
      return 0
    fi
  fi

  # Refresh the token
  local response
  response=$(curl -s --max-time 15 -X POST "https://accounts.zoho.com/oauth/v2/token" \
    -d "refresh_token=${ZOHO_REFRESH_TOKEN}" \
    -d "client_id=${ZOHO_CLIENT_ID}" \
    -d "client_secret=${ZOHO_CLIENT_SECRET}" \
    -d "grant_type=refresh_token")

  local token
  token=$(echo "$response" | jq -r '.access_token // empty')

  if [[ -z "$token" ]]; then
    echo "ERROR: Failed to refresh access token. Response: $response" >&2
    return 1
  fi

  # Cache it
  jq -n --arg token "$token" --arg ts "$(date +%s)" \
    '{access_token: $token, timestamp: ($ts | tonumber)}' > "$TOKEN_CACHE"

  echo "$token"
}

# Account config
ZOHO_ACCOUNT_ID="${ZOHO_ACCOUNT_ID:-2873142000000008002}"
ZOHO_FROM_ADDRESS="${ZOHO_FROM_ADDRESS:-xavier@makemesocialapp.com}"
ZOHO_INBOX_FOLDER_ID="${ZOHO_INBOX_FOLDER_ID:-2873142000000009011}"

# Base URL for Zoho Mail API
ZOHO_MAIL_API="https://mail.zoho.com/api"
