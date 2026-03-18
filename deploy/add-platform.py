#!/usr/bin/env python3
"""Add admin.devdeepak.me as a web platform in Appwrite project."""
import json, os, urllib.request, urllib.error

ENV_FILE = os.path.expanduser("~/chizze/backend/.env")

env = {}
with open(ENV_FILE) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k] = v

ENDPOINT = env["APPWRITE_ENDPOINT"]
PROJECT = env["APPWRITE_PROJECT_ID"]
API_KEY = env["APPWRITE_API_KEY"]

headers = {
    "X-Appwrite-Project": PROJECT,
    "X-Appwrite-Key": API_KEY,
    "Content-Type": "application/json",
}

# First list existing platforms
print("Listing existing platforms...")
req = urllib.request.Request(
    f"{ENDPOINT}/projects/{PROJECT}/platforms",
    headers=headers
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
    for p in data.get("platforms", []):
        print(f"  - {p.get('type')}: {p.get('hostname', p.get('name', ''))}")
except urllib.error.HTTPError as e:
    body = e.read().decode()
    print(f"List failed ({e.code}): {body}")
    # If listing fails, the API key might not have project-level access
    # This is expected for database-scoped keys
    print("\nAPI key may not have project management scope.")
    print("You need to add the platform manually in Appwrite Console:")
    print("  1. Go to https://cloud.appwrite.io")
    print(f"  2. Open project: {PROJECT}")
    print("  3. Go to Overview → Integrations → Platforms")
    print("  4. Add Platform → Web")
    print("  5. Name: Chizze Admin Panel")
    print("  6. Hostname: admin.devdeepak.me")
    print("\nAlternatively, add a wildcard: *.devdeepak.me")

    # Try to add anyway
    print("\nAttempting to add platform...")

body = json.dumps({
    "type": "web",
    "name": "Chizze Admin Panel",
    "hostname": "admin.devdeepak.me",
}).encode()

req = urllib.request.Request(
    f"{ENDPOINT}/projects/{PROJECT}/platforms",
    data=body,
    headers=headers,
    method="POST"
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())
    print(f"✔ Platform added: {result.get('hostname', 'admin.devdeepak.me')}")
except urllib.error.HTTPError as e:
    err = e.read().decode()
    print(f"Add failed ({e.code}): {err}")
    if "scope" in err.lower() or "authorization" in err.lower():
        print("\n═══════════════════════════════════════")
        print("  MANUAL STEP REQUIRED")
        print("═══════════════════════════════════════")
        print("Your API key doesn't have project management access.")
        print("Add the platform manually in Appwrite Console:")
        print("  1. https://cloud.appwrite.io")
        print(f"  2. Project: {PROJECT}")
        print("  3. Overview → Integrations → Platforms")
        print("  4. Add Platform → Web")
        print("  5. Hostname: admin.devdeepak.me")
