"""Check status of delivery_type attribute in Appwrite orders collection."""
import paramiko
import json

HOST = "165.232.177.81"
USER = "root"
PASSWORD = "dreaM$8858J"
AW_KEY = "standard_bce5608cafe757835075f175595b32d446ad35dec4a7c81db5a78867ac41b52b07fc87145107dd68151c7b9e8083ae48d2dc241d1b649cebfdfc804928d410648dc475c77be9b3e35f94fda1b772b2d834a7e929b30eb83576af8bca77ed031bc5d50ae64e9c57ca613c5927dc0ada52488679d67de8b7205000ed5b79ae687d"

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, username=USER, password=PASSWORD, timeout=15)

all_attrs = []
for offset in [0, 25]:
    cmd = (
        f"curl -s 'https://sgp.cloud.appwrite.io/v1/databases/chizze_db/collections/orders/attributes?offset={offset}' "
        f"-H 'X-Appwrite-Project: 6993347c0006ead7404d' "
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
