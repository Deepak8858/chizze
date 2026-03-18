#!/bin/bash
set -euo pipefail

PHONE="+917607185834"
ROLE="admin"
ENV_FILE="$HOME/chizze/backend/.env"

ENDPOINT=$(grep '^APPWRITE_ENDPOINT=' "$ENV_FILE" | cut -d= -f2-)
PROJECT_ID=$(grep '^APPWRITE_PROJECT_ID=' "$ENV_FILE" | cut -d= -f2-)
API_KEY=$(grep '^APPWRITE_API_KEY=' "$ENV_FILE" | cut -d= -f2-)
DATABASE_ID=$(grep '^APPWRITE_DATABASE_ID=' "$ENV_FILE" | cut -d= -f2-)

echo "Config: endpoint=$ENDPOINT project=$PROJECT_ID db=$DATABASE_ID"
echo "Searching for phone: $PHONE"

# List all users and filter by phone using Appwrite query
RESULT=$(curl -sf -X GET \
  "${ENDPOINT}/databases/${DATABASE_ID}/collections/users/documents?queries\[\]=equal%28%22phone%22%2C%5B%22%2B917607185834%22%5D%29&queries\[\]=limit%281%29" \
  -H "X-Appwrite-Project: ${PROJECT_ID}" \
  -H "X-Appwrite-Key: ${API_KEY}" \
  -H "Content-Type: application/json")

echo "Search result:"
echo "$RESULT" | python3 -m json.tool 2>/dev/null || echo "$RESULT"
