"""Check delivery_type attribute directly."""
import paramiko, json

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("165.232.177.81", username="root", password="dreaM$8858J", timeout=15)

AW_KEY = "standard_bce5608cafe757835075f175595b32d446ad35dec4a7c81db5a78867ac41b52b07fc87145107dd68151c7b9e8083ae48d2dc241d1b649cebfdfc804928d410648dc475c77be9b3e35f94fda1b772b2d834a7e929b30eb83576af8bca77ed031bc5d50ae64e9c57ca613c5927dc0ada52488679d67de8b7205000ed5b79ae687d"
BASE = "https://sgp.cloud.appwrite.io/v1/databases/chizze_db/collections/orders/attributes"

# Try direct attribute endpoint
cmd = (
    f"curl -s '{BASE}/delivery_type' "
    f"-H 'X-Appwrite-Project: 6993347c0006ead7404d' "
    f"-H 'X-Appwrite-Key: {AW_KEY}'"
)
_, stdout, _ = ssh.exec_command(cmd, timeout=60)
data = json.loads(stdout.read().decode())
print("Direct fetch:", json.dumps(data, indent=2))

# Also list with proper limit query
cmd2 = (
    f'curl -s -G "{BASE}" '
    f'--data-urlencode "queries[]={{\\"method\\":\\"limit\\",\\"values\\":[100]}}" '
    f"-H 'X-Appwrite-Project: 6993347c0006ead7404d' "
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
