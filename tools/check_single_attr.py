"""Check delivery_type attribute directly."""
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

BASE = f"{AW_ENDPOINT}/databases/{DATABASE_ID}/collections/orders/attributes"

# Try direct attribute endpoint
cmd = (
    f"curl -s '{BASE}/delivery_type' "
    f"-H 'X-Appwrite-Project: {AW_PROJECT}' "
    f"-H 'X-Appwrite-Key: {AW_KEY}'"
)
_, stdout, _ = ssh.exec_command(cmd, timeout=60)
data = json.loads(stdout.read().decode())
print("Direct fetch:", json.dumps(data, indent=2))

# Also list with proper limit query
cmd2 = (
    f'curl -s -G "{BASE}" '
    f'--data-urlencode "queries[]={{\\"method\\":\\"limit\\",\\"values\\":[100]}}" '
    f"-H 'X-Appwrite-Project: {AW_PROJECT}' "
    f"-H 'X-Appwrite-Key: {AW_KEY}'"
)
_, stdout2, _ = ssh.exec_command(cmd2, timeout=60)
raw2 = stdout2.read().decode()
data2 = json.loads(raw2)
print(f"\nList total: {data2.get('total', '?')}, returned: {len(data2.get('attributes', []))}")
for a in data2.get("attributes", []):
    if a["key"] == "delivery_type":
        print(f"Found delivery_type in list! Status: {a['status']}")

ssh.close()
