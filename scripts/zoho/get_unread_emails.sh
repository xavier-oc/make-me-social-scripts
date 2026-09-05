#!/usr/bin/env bash
# Zoho Mail API - Get Unread Emails
#
# Usage: ./get_unread_emails.sh [--limit 10] [--folder FOLDER_ID] [--account ACCOUNT_ID] [--full]
#
# Options:
#   --limit     Number of emails to retrieve (default: 20, max: 200)
#   --folder    Folder ID (default: inbox - auto-detected)
#   --account   Account ID override (default: from ZOHO_ACCOUNT_ID env)
#   --full      Include full email content for each message

set -euo pipefail
source "$(dirname "$0")/auth.sh"

LIMIT=20
FOLDER_ID=""
ACCOUNT_ID="${ZOHO_ACCOUNT_ID:-}"
FULL_CONTENT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --limit) LIMIT="$2"; shift 2 ;;
    --folder) FOLDER_ID="$2"; shift 2 ;;
    --account) ACCOUNT_ID="$2"; shift 2 ;;
    --full) FULL_CONTENT=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ACCOUNT_ID" ]]; then
  echo "ERROR: ZOHO_ACCOUNT_ID not set. Ensure ZOHO_ACCOUNT_ID is set in the environment" >&2
  exit 1
fi

TOKEN=$(get_access_token)

# Build query params - folderId is optional (omitting returns all folders)
FOLDER_PARAM=""
if [[ -n "$FOLDER_ID" ]]; then
  FOLDER_PARAM="&folderId=${FOLDER_ID}"
fi

# Fetch unread emails (with timeout to prevent hangs)
RESPONSE=$(curl -s --max-time 20 -X GET \
  "${ZOHO_MAIL_API}/accounts/${ACCOUNT_ID}/messages/view?status=unread&limit=${LIMIT}&includeto=true${FOLDER_PARAM}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Zoho-oauthtoken ${TOKEN}")

STATUS_CODE=$(echo "$RESPONSE" | jq -r '.status.code // empty')
if [[ "$STATUS_CODE" != "200" ]]; then
  echo "ERROR: API returned status $STATUS_CODE" >&2
  echo "$RESPONSE" | jq . >&2
  exit 1
fi

MSG_COUNT=$(echo "$RESPONSE" | jq '.data | length')
echo "Found $MSG_COUNT unread email(s)"
echo "---"

if [[ "$FULL_CONTENT" == true ]]; then
  # Fetch full content for each message using process substitution (avoids subshell data loss)
  # Build array then output once at end — avoids O(n) jq invocations in loop
  mapfile -t MSGS < <(echo "$RESPONSE" | jq -c '.data[]' 2>/dev/null || echo "")
  RESULTS_FILE=$(mktemp)

  for msg in "${MSGS[@]}"; do
    [[ -z "$msg" || "$msg" == "null" ]] && continue

    MSG_ID=$(echo "$msg" | jq -r '.messageId // empty')
    SUBJECT=$(echo "$msg" | jq -r '.subject // empty')
    FROM=$(echo "$msg" | jq -r '.fromAddress // empty')
    DATE=$(echo "$msg" | jq -r '.receivedTime // empty')
    MSG_FOLDER_ID=$(echo "$msg" | jq -r '.folderId // empty')

    # Get full content (with timeout)
    CONTENT_RESPONSE=$(curl -s --max-time 20 -X GET \
      "${ZOHO_MAIL_API}/accounts/${ACCOUNT_ID}/folders/${MSG_FOLDER_ID}/messages/${MSG_ID}/content?includeBlockContent=true" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -H "Authorization: Zoho-oauthtoken ${TOKEN}")

    CONTENT=$(echo "$CONTENT_RESPONSE" | jq -r '.data.content // "Unable to fetch content"')

    jq -n \
      --arg id "$MSG_ID" \
      --arg subject "$SUBJECT" \
      --arg from "$FROM" \
      --arg date "$DATE" \
      --arg folderId "$MSG_FOLDER_ID" \
      --arg content "$CONTENT" \
      '{messageId: $id, subject: $subject, from: $from, receivedTime: $date, folderId: $folderId, content: $content}' \
      >> "$RESULTS_FILE"
  done

  if [[ -s "$RESULTS_FILE" ]]; then
    jq -s '.' "$RESULTS_FILE"
  else
    echo "[]"
  fi
  rm -f "$RESULTS_FILE"
else
  # Just return metadata
  echo "$RESPONSE" | jq '[.data[] | {
    messageId,
    subject,
    from: .fromAddress,
    sender,
    receivedTime,
    summary,
    folderId,
    threadId,
    hasAttachment
  }]'
fi
