"""Add missing delivery_type attribute to Appwrite orders collection."""
import sys
import paramiko
import json

HOST = "165.232.177.81"
USER = "root"
PASSWORD = "dreaM$8858J"

APPWRITE_ENDPOINT = "https://sgp.cloud.appwrite.io/v1"
APPWRITE_PROJECT = "6993347c0006ead7404d"
APPWRITE_KEY = "standard_bce5608cafe757835075f175595b32d446ad35dec4a7c81db5a78867ac41b52b07fc87145107dd68151c7b9e8083ae48d2dc241d1b649cebfdfc804928d410648dc475c77be9b3e35f94fda1b772b2d834a7e929b30eb83576af8bca77ed031bc5d50ae64e9c57ca613c5927dc0ada52488679d67de8b7205000ed5b79ae687d"
DATABASE_ID = "chizze_db"
COLLECTION_ID = "orders"

def run_ssh(cmd: str) -> str:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
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
