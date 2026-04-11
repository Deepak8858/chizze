// Fetch users registered today and tomorrow from Appwrite
// Run: node tools/get_users_today_tomorrow.js

const APPWRITE_ENDPOINT = 'https://sgp.cloud.appwrite.io/v1';
const APPWRITE_PROJECT_ID = '6993347c0006ead7404d';
const APPWRITE_API_KEY = 'standard_bce5608cafe757835075f175595b32d446ad35dec4a7c81db5a78867ac41b52b07fc87145107dd68151c7b9e8083ae48d2dc241d1b649cebfdfc804928d410648dc475c77be9b3e35f94fda1b772b2d834a7e929b30eb83576af8bca77ed031bc5d50ae64e9c57ca613c5927dc0ada52488679d67de8b7205000ed5b79ae687d';

// IST offset = UTC+5:30
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

function toISTMidnight(date) {
  // Returns a Date at midnight IST for the given date
  const ist = new Date(date.getTime());
  // Get the IST date string
  const istStr = new Date(date.getTime() + IST_OFFSET_MS).toISOString().split('T')[0];
  // Midnight IST = istStr + T00:00:00 IST = subtract 5:30 for UTC
  return new Date(istStr + 'T00:00:00.000+05:30');
}

async function fetchUsers(cursorAfter = null) {
  const params = new URLSearchParams();
  params.append('queries[]', 'orderAsc("$createdAt")');
  params.append('limit', '100');
  if (cursorAfter) {
    params.append('queries[]', `cursorAfter("${cursorAfter}")`);
  }

  const url = `${APPWRITE_ENDPOINT}/users?${params.toString()}`;

  const res = await fetch(url, {
    headers: {
      'X-Appwrite-Project': APPWRITE_PROJECT_ID,
      'X-Appwrite-Key': APPWRITE_API_KEY,
      'Content-Type': 'application/json',
    },
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Appwrite error ${res.status}: ${err}`);
  }

  return res.json();
}

async function main() {
  const now = new Date(); // Current time (UTC)

  // Today in IST
  const todayStart = toISTMidnight(now);
  const tomorrowStart = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
  const dayAfterStart = new Date(tomorrowStart.getTime() + 24 * 60 * 60 * 1000);

  console.log(`\n🕐 Current UTC time: ${now.toISOString()}`);
  console.log(`📅 Today IST: ${todayStart.toISOString()} → ${tomorrowStart.toISOString()}`);
  console.log(`📅 Tomorrow IST: ${tomorrowStart.toISOString()} → ${dayAfterStart.toISOString()}`);
  console.log('\nFetching all users...\n');

  let allUsers = [];
  let cursor = null;
  let page = 1;

  while (true) {
    const data = await fetchUsers(cursor);
    const users = data.users || [];
    allUsers = allUsers.concat(users);
    console.log(`  Page ${page}: fetched ${users.length} users (total so far: ${allUsers.length})`);

    if (users.length < 100) break; // Last page
    cursor = users[users.length - 1].$id;
    page++;
  }

  console.log(`\nTotal users fetched: ${allUsers.length}`);

  // Filter by today and tomorrow (IST)
  const todayUsers = [];
  const tomorrowUsers = [];

  for (const user of allUsers) {
    const created = new Date(user.$createdAt);
    if (created >= todayStart && created < tomorrowStart) {
      todayUsers.push(user);
    } else if (created >= tomorrowStart && created < dayAfterStart) {
      tomorrowUsers.push(user);
    }
  }

  // Display today's users
  const todayDate = todayStart.toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'long', year: 'numeric' });
  const tomorrowDate = tomorrowStart.toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'long', year: 'numeric' });

  console.log('\n' + '═'.repeat(60));
  console.log(`📋 TODAY'S USERS (${todayDate}) — ${todayUsers.length} users`);
  console.log('═'.repeat(60));

  if (todayUsers.length === 0) {
    console.log('   No users registered today.');
  } else {
    console.log(` # | Name                          | Phone / Email`);
    console.log('---|-------------------------------|' + '-'.repeat(35));
    todayUsers.forEach((u, i) => {
      const name = u.name || '(no name)';
      const contact = u.phone || u.email || '(no contact)';
      const registeredAt = new Date(u.$createdAt).toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit' });
      console.log(` ${String(i + 1).padStart(2)} | ${name.padEnd(29)} | ${contact}  [${registeredAt}]`);
    });
  }

  console.log('\n' + '═'.repeat(60));
  console.log(`📋 TOMORROW'S USERS (${tomorrowDate}) — ${tomorrowUsers.length} users`);
  console.log('═'.repeat(60));

  if (tomorrowUsers.length === 0) {
    console.log('   No users registered tomorrow yet.');
  } else {
    console.log(` # | Name                          | Phone / Email`);
    console.log('---|-------------------------------|' + '-'.repeat(35));
    tomorrowUsers.forEach((u, i) => {
      const name = u.name || '(no name)';
      const contact = u.phone || u.email || '(no contact)';
      const registeredAt = new Date(u.$createdAt).toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit' });
      console.log(` ${String(i + 1).padStart(2)} | ${name.padEnd(29)} | ${contact}  [${registeredAt}]`);
    });
  }

  console.log('\n' + '═'.repeat(60));
  console.log(`Total: ${todayUsers.length} today + ${tomorrowUsers.length} tomorrow = ${todayUsers.length + tomorrowUsers.length} users`);
  console.log('═'.repeat(60) + '\n');
}

main().catch(err => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
