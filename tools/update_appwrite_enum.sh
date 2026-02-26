#!/bin/bash
# Update Appwrite enum attributes to include "online"

PROJECT="6993347c0006ead7404d"
API_KEY="standard_bce5608cafe757835075f175595b32d446ad35dec4a7c81db5a78867ac41b52b07fc87145107dd68151c7b9e8083ae48d2dc241d1b649cebfdfc804928d410648dc475c77be9b3e35f94fda1b772b2d834a7e929b30eb83576af8bca77ed031bc5d50ae64e9c57ca613c5927dc0ada52488679d67de8b7205000ed5b79ae687d"
ENDPOINT="https://sgp.cloud.appwrite.io/v1"
DB="chizze_db"

echo "=== Updating orders.payment_method enum ==="
curl -s -X PATCH "${ENDPOINT}/databases/${DB}/collections/orders/attributes/enum/payment_method" \
  -H "Content-Type: application/json" \
  -H "X-Appwrite-Project: ${PROJECT}" \
  -H "X-Appwrite-Key: ${API_KEY}" \
  -d '{"elements":["upi","card","cod","wallet","netbanking","online"],"required":true,"default":null}'

echo ""
echo "=== Updating payments.method enum ==="
curl -s -X PATCH "${ENDPOINT}/databases/${DB}/collections/payments/attributes/enum/method" \
  -H "Content-Type: application/json" \
  -H "X-Appwrite-Project: ${PROJECT}" \
  -H "X-Appwrite-Key: ${API_KEY}" \
  -d '{"elements":["upi","card","cod","wallet","netbanking","online"],"required":true,"default":null}'

echo ""
echo "=== Done ==="
