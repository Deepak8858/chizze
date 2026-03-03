"""Add missing delivery_type attribute to Appwrite orders collection."""
import sys
import os
import paramiko
import json

def _env(key: str) -> str:
    val = os.environ.get(key)
    if not val:
        sys.exit(f"ERROR: environment variable {key} is not set")
    return val

HOST = _env("DEPLOY_HOST")
USER = _env("DEPLOY_USER")
PASSWORD = _env("DEPLOY_PASSWORD")

APPWRITE_ENDPOINT = _env("APPWRITE_ENDPOINT")
APPWRITE_PROJECT = _env("APPWRITE_PROJECT")
APPWRITE_KEY = _env("APPWRITE_KEY")
DATABASE_ID = os.environ.get("APPWRITE_DATABASE_ID", "chizze_db")
COLLECTION_ID = os.environ.get("APPWRITE_COLLECTION_ID", "orders")

def run_ssh(cmd: str) -> str:
    ssh = paramiko.SSHClient()
    ssh.load_system_host_keys()
    ssh.set_missing_host_key_policy(paramiko.WarningPolicy())
    ssh.connect(HOST, username=USER, password=PASSWORD, timeout=15)
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=300)
    out = stdout.read().decode()
    err = stderr.read().decode()
    ssh.close()
    return out + err

def add_attribute(attr_type: str, payload: dict):
    """Add an attribute via the Appwrite REST API."""
    url = f"{APPWRITE_ENDPOINT}/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/attributes/{attr_type}"
    payload_json = json.dumps(payload)

    # Write payload to a temp file on the server, then curl from that file
    write_cmd = f"cat << 'ENDJSON' > /tmp/aw_payload.json\n{payload_json}\nENDJSON"
    run_ssh(write_cmd)

    curl_cmd = (
        f"curl -s -X POST '{url}' "
        f"-H 'Content-Type: application/json' "
        f"-H 'X-Appwrite-Response-Format: 1.6.0' "
        f"-H 'X-Appwrite-Project: {APPWRITE_PROJECT}' "
        f"-H 'X-Appwrite-Key: {APPWRITE_KEY}' "
        f"-d @/tmp/aw_payload.json"
    )
    result = run_ssh(curl_cmd)
    print(f"  {attr_type} ({payload.get('key', '?')}): {result.strip()}")
    return result

def main():
    print("Adding missing attributes to orders collection...\n")

    # 1. delivery_type (enum: standard, eco)
    print("1. delivery_type")
    add_attribute("enum", {
        "key": "delivery_type",
        "elements": ["standard", "eco"],
        "required": False,
        "default": "standard"
    })

    # 2. restaurant_latitude (float)
    print("2. restaurant_latitude")
    add_attribute("float", {
        "key": "restaurant_latitude",
        "required": False,
    })

    # 3. restaurant_longitude (float)
    print("3. restaurant_longitude")
    add_attribute("float", {
        "key": "restaurant_longitude",
        "required": False,
    })

    # 4. delivery_address (string)
    print("4. delivery_address")
    add_attribute("string", {
        "key": "delivery_address",
        "size": 500,
        "required": False,
    })

    # 5. delivery_landmark (string)
    print("5. delivery_landmark")
    add_attribute("string", {
        "key": "delivery_landmark",
        "size": 200,
        "required": False,
    })

    # 6. delivery_latitude (float)
    print("6. delivery_latitude")
    add_attribute("float", {
        "key": "delivery_latitude",
        "required": False,
    })

    # 7. delivery_longitude (float)
    print("7. delivery_longitude")
    add_attribute("float", {
        "key": "delivery_longitude",
        "required": False,
    })

    print("\nDone! Waiting a few seconds for attributes to be created...")
    import time
    time.sleep(5)

    # Verify by listing attributes
    print("\nVerifying attributes...")
    url = f"{APPWRITE_ENDPOINT}/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/attributes"
    curl_cmd = (
        f"curl -s '{url}' "
        f"-H 'Content-Type: application/json' "
        f"-H 'X-Appwrite-Project: {APPWRITE_PROJECT}' "
        f"-H 'X-Appwrite-Key: {APPWRITE_KEY}'"
    )
    result = run_ssh(curl_cmd)
    try:
        data = json.loads(result)
        attrs = [a.get("key") for a in data.get("attributes", [])]
        missing = []
        for needed in ["delivery_type", "restaurant_latitude", "restaurant_longitude",
                        "delivery_address", "delivery_landmark", "delivery_latitude", "delivery_longitude"]:
            if needed in attrs:
                print(f"  ✓ {needed}")
            else:
                print(f"  ✗ {needed} MISSING")
                missing.append(needed)
        if not missing:
            print("\nAll attributes present!")
        else:
            print(f"\nWARNING: Still missing: {missing}")
    except json.JSONDecodeError:
        print(f"Could not parse response: {result[:200]}")

if __name__ == "__main__":
    main()
