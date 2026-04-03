const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const envPath = path.join(__dirname, '..', 'remote.env');
const envText = fs.readFileSync(envPath, 'utf8');
const env = {};
for (const rawLine of envText.split(/\r?\n/)) {
  const line = rawLine.trim();
  if (!line || line.startsWith('#')) continue;
  const idx = line.indexOf('=');
  if (idx <= 0) continue;
  const key = line.slice(0, idx).trim();
  const value = line.slice(idx + 1).trim();
  env[key] = value;
}

const jwtSecret = env.JWT_SECRET;
if (!jwtSecret) {
  throw new Error('JWT_SECRET not found in remote.env');
}

const appwriteEndpoint = env.APPWRITE_ENDPOINT;
const appwriteProjectId = env.APPWRITE_PROJECT_ID;
const appwriteApiKey = env.APPWRITE_API_KEY;
const appwriteDatabaseId = env.APPWRITE_DATABASE_ID;

if (!appwriteEndpoint || !appwriteProjectId || !appwriteApiKey || !appwriteDatabaseId) {
  throw new Error('Missing Appwrite config in remote.env');
}

function signToken(userId, role, ttlSec = 3600) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const payload = {
    userId,
    role,
    iss: 'chizze-api',
    exp: Math.floor(Date.now() / 1000) + ttlSec,
  };

  const b64url = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const head = b64url(header);
  const body = b64url(payload);
  const sig = crypto
    .createHmac('sha256', jwtSecret)
    .update(`${head}.${body}`)
    .digest('base64url');

  return `${head}.${body}.${sig}`;
}

async function api(path, { method = 'GET', token, body } = {}) {
  const url = `https://api.devdeepak.me/api/v1${path}`;
  const headers = {
    'Content-Type': 'application/json',
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // ignore
  }

  return { ok: res.ok, status: res.status, json, text };
}

async function appwriteListUserDocs(limit = 200) {
  const url = `${appwriteEndpoint}/databases/${appwriteDatabaseId}/collections/users/documents`;

  const res = await fetch(url, {
    method: 'GET',
    headers: {
      'X-Appwrite-Project': appwriteProjectId,
      'X-Appwrite-Key': appwriteApiKey,
      'Content-Type': 'application/json',
    },
  });

  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // ignore
  }

  if (!res.ok) {
    throw new Error(`Failed Appwrite users collection read (${res.status}): ${text}`);
  }

  return json?.documents || [];
}

(async () => {
  let adminToken = process.env.ADMIN_TOKEN || '';

  // If no token provided, discover an admin/super_admin user from Appwrite
  // and generate a token for one that isn't blacklisted.
  if (!adminToken) {
    const users = await appwriteListUserDocs(500);
    const admins = users.filter((u) => ['admin', 'super_admin'].includes(u?.role));

    for (const admin of admins) {
      const candidate = signToken(admin.$id, admin.role || 'admin');
      const probe = await api('/admin/users?limit=1', { token: candidate });
      if (probe.ok) {
        adminToken = candidate;
        break;
      }
    }
  }

  if (!adminToken) {
    throw new Error('Could not find a valid admin token (all candidates appear revoked)');
  }

  const usersResp = await api('/admin/users?limit=50', { token: adminToken });
  if (!usersResp.ok) {
    console.error('FAILED: /admin/users', usersResp.status, usersResp.text);
    process.exit(1);
  }

  const users = usersResp.json?.data || [];
  const target = users.find((u) => u.role === 'customer') || users[0];
  if (!target) {
    console.error('FAILED: no users returned from /admin/users');
    process.exit(1);
  }

  const title = `FlowTest-${Date.now()}`;
  const body = 'Automated notification delivery verification';

  const sendResp = await api('/admin/notifications/broadcast', {
    method: 'POST',
    token: adminToken,
    body: {
      title,
      body,
      type: 'system',
      target_type: 'specific_user',
      target_id: target.$id,
    },
  });

  if (!sendResp.ok) {
    console.error('FAILED: /admin/notifications/broadcast', sendResp.status, sendResp.text);
    process.exit(1);
  }

  const userToken = signToken(target.$id, target.role);
  const notifResp = await api('/notifications', { token: userToken });

  if (!notifResp.ok) {
    console.error('FAILED: /notifications', notifResp.status, notifResp.text);
    process.exit(1);
  }

  const notifications = notifResp.json?.data || [];
  const found = notifications.find((n) => n.title === title);

  console.log(JSON.stringify({
    targetUserId: target.$id,
    targetRole: target.role,
    sendStatus: sendResp.status,
    listStatus: notifResp.status,
    notificationCount: notifications.length,
    foundSentNotification: Boolean(found),
    foundCreatedAt: found ? (found.created_at || found.$createdAt || null) : null,
  }, null, 2));

  if (!found) {
    process.exit(2);
  }
})();
