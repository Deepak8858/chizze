const crypto = require('crypto');
const { chromium } = require(process.cwd() + '/node_modules/@playwright/test');

const baseUrl = 'http://localhost:3000';
const secret = 'chizze-dev-secret-change-in-production';
const user = {
  id: 'deepak-smoke-test',
  name: 'Deepak Singh',
  phone: '+910000000000',
  role: 'super_admin',
  permission: 'super_admin',
};

function base64Url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function signJwt(userId, role) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'HS256', typ: 'JWT' };
  const payload = {
    userId,
    role,
    iss: 'chizze-api',
    sub: userId,
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const signature = crypto
    .createHmac('sha256', secret)
    .update(unsigned)
    .digest('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
  return `${unsigned}.${signature}`;
}

const token = signJwt(user.id, user.role);
const routes = [
  ['/login', 'Login'],
  ['/dashboard', 'Dashboard'],
  ['/live-map', 'Live Map'],
  ['/live-users', 'Live Users'],
  ['/live-orders', 'Live Orders'],
  ['/users', 'Users'],
  ['/restaurants', 'Restaurants'],
  ['/orders', 'Orders'],
  ['/delivery-partners', 'Delivery Partners'],
  ['/payouts', 'Payouts'],
  ['/approvals/restaurants', 'Restaurant Queue'],
  ['/approvals/delivery-partners', 'Rider Queue'],
  ['/disputes', 'Disputes'],
  ['/coupons', 'Coupons'],
  ['/gold', 'Gold'],
  ['/referrals', 'Referrals'],
  ['/notifications', 'Notifications'],
  ['/content', 'Content'],
  ['/sla', 'SLA Monitor'],
  ['/reports', 'Reports'],
  ['/analytics', 'Analytics'],
  ['/reviews', 'Reviews'],
  ['/zones', 'Zones'],
  ['/surge', 'Surge Pricing'],
  ['/flags', 'Feature Flags'],
  ['/audit-log', 'Audit Log'],
  ['/support', 'Support'],
  ['/settings', 'Settings'],
  ['/admin-accounts', 'Admin Accounts'],
  ['/', 'Root'],
];

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1600, height: 1200 } });
  await context.addInitScript(({ token, user }) => {
    localStorage.setItem('chizze_admin_token', token);
    localStorage.setItem('chizze_admin_user', JSON.stringify(user));
  }, { token, user });

  const page = await context.newPage();
  page.setDefaultNavigationTimeout(15000);
  page.setDefaultTimeout(10000);

  const issues = [];
  const routeSummaries = [];

  page.on('pageerror', (error) => {
    issues.push({ kind: 'pageerror', url: page.url(), message: error.message });
  });

  page.on('console', (message) => {
    if (message.type() === 'error') {
      issues.push({ kind: 'console', url: page.url(), message: message.text() });
    }
  });

  page.on('response', (response) => {
    const status = response.status();
    const request = response.request();
    if (request.resourceType() === 'fetch' && [401, 403, 500].includes(status)) {
      issues.push({ kind: 'http', url: page.url(), request: response.url(), status });
    }
  });

  for (const [route, label] of routes) {
    const before = issues.length;
    await page.goto(`${baseUrl}${route}`, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(route === '/live-map' ? 3500 : 1800);

    const heading = await page.locator('main h1, main h2').first().textContent().catch(() => null);
    const bodyText = await page.locator('main').textContent().catch(() => '');
    const routeIssues = issues.slice(before);

    let sidebarLinks = null;
    if (route === '/dashboard') {
      sidebarLinks = await page.locator('aside a').evaluateAll((elements) =>
        elements.map((element) => ({
          text: (element.textContent || '').trim(),
          href: element.getAttribute('href'),
        }))
      );
    }

    routeSummaries.push({
      route,
      label,
      finalUrl: page.url(),
      heading,
      bodyPreview: bodyText.replace(/\s+/g, ' ').trim().slice(0, 180),
      issueCount: routeIssues.length,
      issues: routeIssues,
      sidebarLinks,
    });
  }

  await browser.close();

  const issueCount = routeSummaries.reduce((sum, route) => sum + route.issueCount, 0);
  console.log(JSON.stringify(routeSummaries, null, 2));
  console.log(`ISSUE_COUNT ${issueCount}`);
  if (issueCount > 0) {
    process.exitCode = 1;
  }
})();
