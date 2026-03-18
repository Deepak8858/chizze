#!/bin/bash
# Grant admin role to a user by phone number
# Uses Appwrite REST API with credentials from backend .env

set -euo pipefail

PHONE="+917607185834"
ROLE="admin"
ENV_FILE="$HOME/chizze/backend/.env"

# Read Appwrite credentials from .env
ENDPOINT=$(grep '^APPWRITE_ENDPOINT=' "$ENV_FILE" | cut -d= -f2-)
PROJECT_ID=$(grep '^APPWRITE_PROJECT_ID=' "$ENV_FILE" | cut -d= -f2-)
API_KEY=$(grep '^APPWRITE_API_KEY=' "$ENV_FILE" | cut -d= -f2-)
DATABASE_ID=$(grep '^APPWRITE_DATABASE_ID=' "$ENV_FILE" | cut -d= -f2-)
COLLECTION_ID="users"

echo "Searching for user with phone: $PHONE"

# Search for user by phone
RESULT=$(curl -s -X GET \
  "$ENDPOINT/databases/$DATABASE_ID/collections/$COLLECTION_ID/documents" \
  -H "X-Appwrite-Project: $PROJECT_ID" \
  -H "X-Appwrite-Key: $API_KEY" \
  -G --data-urlencode "queries[]=[\"equal(\"phone\",[\"$PHONE\"])\"]" \
  --data-urlencode "queries[]=[\"limit(1)\"]")

TOTAL=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "0")

if [ "$TOTAL" -gt 0 ]; then
  DOC_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['documents'][0]['\$id'])")
  CURRENT_ROLE=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['documents'][0].get('role','unknown'))")
  echo "Found user: $DOC_ID (current role: $CURRENT_ROLE)"

  # Update role to admin
  UPDATE=$(curl -s -X PATCH \
    "$ENDPOINT/databases/$DATABASE_ID/collections/$COLLECTION_ID/documents/$DOC_ID" \
    -H "X-Appwrite-Project: $PROJECT_ID" \
    -H "X-Appwrite-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"data\":{\"role\":\"$ROLE\"}}")

  NEW_ROLE=$(echo "$UPDATE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('role','ERROR'))" 2>/dev/null || echo "ERROR")
  echo "Updated role: $CURRENT_ROLE → $NEW_ROLE"
else
  echo "No existing user found with phone $PHONE"
  echo "The user needs to log in at least once first (via the app) to create their account."
  echo "After first login, re-run this script to grant admin access."
fi
