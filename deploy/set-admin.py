#!/usr/bin/env python3
"""Grant admin role to a user by phone number via Appwrite REST API."""
import json, os, sys, urllib.request, urllib.parse, urllib.error

PHONE = "+917607185834"
ROLE = "admin"
ENV_FILE = os.path.expanduser("~/chizze/backend/.env")

# Read .env
env = {}
with open(ENV_FILE) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k] = v

ENDPOINT = env.get("APPWRITE_ENDPOINT", "")
PROJECT = env.get("APPWRITE_PROJECT_ID", "")
API_KEY = env.get("APPWRITE_API_KEY", "")
DB_ID = env.get("APPWRITE_DATABASE_ID", "chizze_db")

print(f"Endpoint: {ENDPOINT}")
print(f"Database: {DB_ID}")
print(f"Searching for phone: {PHONE}")

headers = {
    "X-Appwrite-Project": PROJECT,
    "X-Appwrite-Key": API_KEY,
    "Content-Type": "application/json",
}

# Search for user by phone (Appwrite 1.8+ JSON query format)
q1 = json.dumps({"method": "equal", "attribute": "phone", "values": [PHONE]})
q2 = json.dumps({"method": "limit", "values": [1]})
qs = urllib.parse.urlencode([("queries[]", q1), ("queries[]", q2)])
url = f"{ENDPOINT}/databases/{DB_ID}/collections/users/documents?{qs}"
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
except urllib.error.HTTPError as e:
    print(f"Error {e.code}: {e.read().decode()}")
    sys.exit(1)

total = data.get("total", 0)
print(f"Found {total} user(s)")

if total == 0:
    print(f"\nNo user found with phone {PHONE}")
    print("The user must log in via the app first to create their account.")
    print("After first login, re-run this script.")
    sys.exit(0)

doc = data["documents"][0]
doc_id = doc["$id"]
current_role = doc.get("role", "unknown")
name = doc.get("name", "")
print(f"User: {doc_id} | Name: {name} | Current role: {current_role}")

if current_role == ROLE:
    print(f"Already has role '{ROLE}'. No changes needed.")
    sys.exit(0)

# Update role
update_url = f"{ENDPOINT}/databases/{DB_ID}/collections/users/documents/{doc_id}"
update_data = json.dumps({"data": {"role": ROLE}}).encode()
req = urllib.request.Request(update_url, data=update_data, headers=headers, method="PATCH")
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())
    new_role = result.get("role", "ERROR")
    print(f"\n✔ Role updated: {current_role} → {new_role}")
    print(f"User {PHONE} can now log in to the admin panel.")
except urllib.error.HTTPError as e:
    print(f"Update failed ({e.code}): {e.read().decode()}")
    sys.exit(1)
