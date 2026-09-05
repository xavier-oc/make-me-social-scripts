#!/usr/bin/env bash
# Zoho Mail API - Send Email
#
# Usage: ./send_email.sh --to "recipient@example.com" --subject "Subject" --body "Email body"
#
# Options:
#   --to        Recipient email address (required)
#   --cc        CC address (optional)
#   --bcc       BCC address (optional)
#   --subject   Email subject (required)
#   --body      Email body content (required)
#   --format    "html" or "plaintext" (default: html)
#   --account   Account ID override (default: from ZOHO_ACCOUNT_ID env)

set -euo pipefail
source "$(dirname "$0")/auth.sh"

# Defaults
TO_ADDRESS=""
CC_ADDRESS=""
BCC_ADDRESS=""
SUBJECT=""
BODY=""
MAIL_FORMAT="html"
ACCOUNT_ID="${ZOHO_ACCOUNT_ID:-}"
FROM_ADDRESS="${ZOHO_FROM_ADDRESS:-xavier@makemesocialapp.com}"

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --to) TO_ADDRESS="$2"; shift 2 ;;
    --cc) CC_ADDRESS="$2"; shift 2 ;;
    --bcc) BCC_ADDRESS="$2"; shift 2 ;;
    --subject) SUBJECT="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --format) MAIL_FORMAT="$2"; shift 2 ;;
    --account) ACCOUNT_ID="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validate required params
if [[ -z "$TO_ADDRESS" || -z "$SUBJECT" || -z "$BODY" ]]; then
  echo "ERROR: --to, --subject, and --body are required" >&2
  echo "Usage: $0 --to \"recipient@example.com\" --subject \"Subject\" --body \"Body\"" >&2
  exit 1
fi

if [[ -z "$ACCOUNT_ID" ]]; then
  echo "ERROR: ZOHO_ACCOUNT_ID not set. Ensure ZOHO_ACCOUNT_ID is set in the environment" >&2
  exit 1
fi

TOKEN=$(get_access_token)

# Build JSON payload
PAYLOAD=$(jq -n \
  --arg from "$FROM_ADDRESS" \
  --arg to "$TO_ADDRESS" \
  --arg cc "$CC_ADDRESS" \
  --arg bcc "$BCC_ADDRESS" \
  --arg subject "$SUBJECT" \
  --arg content "$BODY" \
  --arg format "$MAIL_FORMAT" \
  '{
    fromAddress: $from,
    toAddress: $to,
    subject: $subject,
    content: $content,
    mailFormat: $format
  }
  + (if $cc != "" then {ccAddress: $cc} else {} end)
  + (if $bcc != "" then {bccAddress: $bcc} else {} end)')

RESPONSE=$(curl -s --max-time 20 -X POST "${ZOHO_MAIL_API}/accounts/${ACCOUNT_ID}/messages" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Zoho-oauthtoken ${TOKEN}" \
  -d "$PAYLOAD")

STATUS_CODE=$(echo "$RESPONSE" | jq -r '.status.code // empty')
if [[ "$STATUS_CODE" == "200" ]]; then
  echo "Email sent successfully to $TO_ADDRESS"
  echo "$RESPONSE" | jq '.data'
else
  echo "ERROR: Failed to send email" >&2
  echo "$RESPONSE" | jq . >&2
  exit 1
fi
