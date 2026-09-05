#!/usr/bin/env bash
# Zoho Mail API - Get Account ID
# Retrieves the Zoho Mail account ID and inbox folder ID for the configured sender.
#
# Usage: ./get_account_id.sh
# Output: JSON with accountId, email, and inboxFolderId

set -euo pipefail
source "$(dirname "$0")/auth.sh"

TOKEN=$(get_access_token)

# Get all accounts
RESPONSE=$(curl -s -X GET "${ZOHO_MAIL_API}/accounts" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Zoho-oauthtoken ${TOKEN}")

# Check for errors
STATUS_CODE=$(echo "$RESPONSE" | jq -r '.status.code // empty')
if [[ "$STATUS_CODE" != "200" ]]; then
  echo "ERROR: API returned status $STATUS_CODE" >&2
  echo "$RESPONSE" | jq . >&2
  exit 1
fi

# Extract account info
echo "$RESPONSE" | jq -r '.data[] | {accountId, primaryEmailAddress, accountDisplayName}'
