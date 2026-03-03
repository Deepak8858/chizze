"""Check status of delivery_type attribute in Appwrite orders collection."""
import os, sys, paramiko, json

def _env(key: str) -> str:
    val = os.environ.get(key)
    if not val:
        sys.exit(f"ERROR: environment variable {key} is not set")
    return val

HOST = _env("DEPLOY_HOST")
USER = _env("DEPLOY_USER")
PASSWORD = _env("DEPLOY_PASSWORD")
AW_KEY = _env("APPWRITE_KEY")
AW_PROJECT = _env("APPWRITE_PROJECT")
AW_ENDPOINT = os.environ.get("APPWRITE_ENDPOINT", "https://sgp.cloud.appwrite.io/v1")
DATABASE_ID = os.environ.get("APPWRITE_DATABASE_ID", "chizze_db")

ssh = paramiko.SSHClient()
ssh.load_system_host_keys()
ssh.set_missing_host_key_policy(paramiko.WarningPolicy())
ssh.connect(HOST, username=USER, password=PASSWORD, timeout=15)

all_attrs = []
for offset in [0, 25]:
    cmd = (
        f"curl -s '{AW_ENDPOINT}/databases/{DATABASE_ID}/collections/orders/attributes?offset={offset}' "
        f"-H 'X-Appwrite-Project: {AW_PROJECT}' "
        f"-H 'X-Appwrite-Key: {AW_KEY}'"
    )
    _, stdout, _ = ssh.exec_command(cmd, timeout=60)
    raw = stdout.read().decode()
    data = json.loads(raw)
    all_attrs.extend(data.get("attributes", []))

ssh.close()

for a in all_attrs:
    print(f"  {a['key']:30s} {a['status']}")

print(f"\nTotal listed: {len(all_attrs)}")
target = [a for a in all_attrs if a["key"] == "delivery_type"]
if target:
    print(f"\ndelivery_type status: {target[0]['status']}")
else:
    print("\ndelivery_type NOT FOUND!")
