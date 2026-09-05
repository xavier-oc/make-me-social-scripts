#!/usr/bin/env bash
# Zoho Mail API - Reply to an Email
#
# Usage: ./reply_to_email.sh --message-id "MSG_ID" --folder-id "FOLDER_ID" --to "recipient@example.com" --body "Reply body"
#
# Options:
#   --message-id  Message ID to reply to (required)
#   --to          Recipient email address (required)
#   --cc          CC address (optional)
#   --subject     Subject override (optional, defaults to "Re: <original subject>")
#   --body        Reply body content (required)
#   --format      "html" or "plaintext" (default: html)
#   --account     Account ID override (default: from ZOHO_ACCOUNT_ID env)
#   --folder-id   Folder ID of the original message (required for thread correctness)

set -euo pipefail
source "$(dirname "$0")/auth.sh"

MESSAGE_ID=""
TO_ADDRESS=""
CC_ADDRESS=""
SUBJECT=""
BODY=""
MAIL_FORMAT="html"
FOLDER_ID=""
ACCOUNT_ID="${ZOHO_ACCOUNT_ID:-}"
FROM_ADDRESS="${ZOHO_FROM_ADDRESS:-xavier@makemesocialapp.com}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --message-id) MESSAGE_ID="$2"; shift 2 ;;
    --to) TO_ADDRESS="$2"; shift 2 ;;
    --cc) CC_ADDRESS="$2"; shift 2 ;;
    --subject) SUBJECT="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --format) MAIL_FORMAT="$2"; shift 2 ;;
    --account) ACCOUNT_ID="$2"; shift 2 ;;
    --folder-id) FOLDER_ID="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MESSAGE_ID" || -z "$TO_ADDRESS" || -z "$BODY" ]]; then
  echo "ERROR: --message-id, --folder-id, --to, and --body are required" >&2
  echo "Usage: $0 --message-id \"MSG_ID\" --folder-id \"FOLDER_ID\" --to \"recipient@example.com\" --body \"Reply body\"" >&2
  exit 1
fi

if [[ -z "$ACCOUNT_ID" ]]; then
  echo "ERROR: ZOHO_ACCOUNT_ID not set. Ensure ZOHO_ACCOUNT_ID is set in the environment" >&2
  exit 1
fi

if [[ -z "$FOLDER_ID" ]]; then
  echo "ERROR: --folder-id is required for thread-correct replies" >&2
  exit 1
fi

TOKEN=$(get_access_token)

# Fetch original message to get threadId (needed for correct Zoho threading)
ORIG_RESP=$(curl -s --max-time 15 -X GET \
  "${ZOHO_MAIL_API}/accounts/${ACCOUNT_ID}/folders/${FOLDER_ID}/messages/${MESSAGE_ID}?includeBlockContent=true" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Zoho-oauthtoken ${TOKEN}")

THREAD_ID=$(echo "$ORIG_RESP" | jq -r '.data.threadId // empty')
ORIG_SUBJECT=$(echo "$ORIG_RESP" | jq -r '.data.subject // empty')

# Determine reply subject: use provided subject with "Re: " prefix, or use original subject with "Re: " prefix
if [[ -n "$SUBJECT" ]]; then
  REPLY_SUBJECT="Re: ${SUBJECT}"
else
  REPLY_SUBJECT="Re: ${ORIG_SUBJECT}"
fi

# Build In-Reply-To header: extract domain from FROM_ADDRESS
FROM_DOMAIN="${FROM_ADDRESS##*@}"
IN_REPLY_TO="<${MESSAGE_ID}@${FROM_DOMAIN}>"

# Build JSON payload — threadId ensures reply lands in the correct conversation thread
PAYLOAD=$(jq -n \
  --arg from "$FROM_ADDRESS" \
  --arg to "$TO_ADDRESS" \
  --arg subject "$REPLY_SUBJECT" \
  --arg content "$BODY" \
  --arg format "$MAIL_FORMAT" \
  --arg threadId "$THREAD_ID" \
  '{
    fromAddress: $from,
    toAddress: $to,
    subject: $subject,
    content: $content,
    mailFormat: $format,
    action: "reply",
    threadId: ($threadId | if . == "null" or . == "" then null else . end)
  }')

# Add CC if provided
if [[ -n "$CC_ADDRESS" ]]; then
  PAYLOAD=$(echo "$PAYLOAD" | jq --arg cc "$CC_ADDRESS" '. + {ccAddress: $cc}')
fi

RESPONSE=$(curl -s -X POST "${ZOHO_MAIL_API}/accounts/${ACCOUNT_ID}/messages/${MESSAGE_ID}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Zoho-oauthtoken ${TOKEN}" \
  -H "In-Reply-To: ${IN_REPLY_TO}" \
  -d "$PAYLOAD")

STATUS_CODE=$(echo "$RESPONSE" | jq -r '.status.code // empty')
if [[ "$STATUS_CODE" == "200" ]]; then
  echo "Reply sent successfully to $TO_ADDRESS (in reply to message $MESSAGE_ID)"
  echo "$RESPONSE" | jq '.data'
else
  echo "ERROR: Failed to send reply" >&2
  echo "$RESPONSE" | jq . >&2
  exit 1
fi
