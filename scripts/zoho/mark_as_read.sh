#!/usr/bin/env bash
# Zoho Mail API - Mark Emails as Read
#
# Usage: ./mark_as_read.sh --message-ids "ID1,ID2,ID3"
#    or: ./mark_as_read.sh --thread-ids "TID1,TID2"
#
# Options:
#   --message-ids  Comma-separated list of message IDs to mark as read
#   --thread-ids   Comma-separated list of thread IDs to mark as read
#   --account      Account ID override (default: from ZOHO_ACCOUNT_ID env)
#
# At least one of --message-ids or --thread-ids is required.

set -euo pipefail
source "$(dirname "$0")/auth.sh"

MESSAGE_IDS=""
THREAD_IDS=""
ACCOUNT_ID="${ZOHO_ACCOUNT_ID:-}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --message-ids) MESSAGE_IDS="$2"; shift 2 ;;
    --thread-ids) THREAD_IDS="$2"; shift 2 ;;
    --account) ACCOUNT_ID="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MESSAGE_IDS" && -z "$THREAD_IDS" ]]; then
  echo "ERROR: At least one of --message-ids or --thread-ids is required" >&2
  echo "Usage: $0 --message-ids \"ID1,ID2,ID3\"" >&2
  exit 1
fi

if [[ -z "$ACCOUNT_ID" ]]; then
  echo "ERROR: ZOHO_ACCOUNT_ID not set. Ensure ZOHO_ACCOUNT_ID is set in the environment" >&2
  exit 1
fi

TOKEN=$(get_access_token)

# Build JSON payload
# Convert comma-separated IDs to JSON arrays
build_id_array() {
  echo "$1" | tr ',' '\n' | jq -R '.' | jq -s '.'
}

PAYLOAD='{"mode": "markAsRead"'

if [[ -n "$MESSAGE_IDS" ]]; then
  MSG_ARRAY=$(build_id_array "$MESSAGE_IDS")
  PAYLOAD="$PAYLOAD, \"messageId\": $MSG_ARRAY"
fi

if [[ -n "$THREAD_IDS" ]]; then
  THR_ARRAY=$(build_id_array "$THREAD_IDS")
  PAYLOAD="$PAYLOAD, \"threadId\": $THR_ARRAY"
fi

PAYLOAD="$PAYLOAD}"

RESPONSE=$(curl -s --max-time 15 -X PUT "${ZOHO_MAIL_API}/accounts/${ACCOUNT_ID}/updatemessage" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Zoho-oauthtoken ${TOKEN}" \
  -d "$PAYLOAD")

STATUS_CODE=$(echo "$RESPONSE" | jq -r '.status.code // empty')
if [[ "$STATUS_CODE" == "200" ]]; then
  echo "Emails marked as read successfully"
  echo "$RESPONSE" | jq '.status'
else
  echo "ERROR: Failed to mark emails as read" >&2
  echo "$RESPONSE" | jq . >&2
  exit 1
fi
