const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const pino = require('pino');
const { createApp } = require('../src/app');

const silentLogger = pino({ level: 'silent' });

// Minimal stand-in for pg.Pool
const fakePool = ({ rows = [], fail = false } = {}) => ({
  query: async () => {
    if (fail) throw new Error('connect ECONNREFUSED 10.0.1.2:5432');
    return { rows };
  }
});

const QUOTE = { id: 1, quote: '<script>alert(1)</script> & "x"', author: "O'Brien", created_at: '2025-12-03T00:00:00Z' };

// Starts the app on a random port and returns a fetch helper bound to it
const serve = (options) => {
  const ctx = {};
  before(async () => {
    const app = createApp({ logger: silentLogger, ...options });
    ctx.server = await new Promise((resolve) => {
      const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    const base = `http://127.0.0.1:${ctx.server.address().port}`;
    ctx.get = (path, headers = {}) => fetch(base + path, { headers });
  });
  after(() => ctx.server.close());
  return ctx;
};

describe('without a Cloudflare secret', () => {
  const ctx = serve({ pool: fakePool({ rows: [QUOTE] }) });

  test('GET / renders the quote with HTML escaped', async () => {
    const res = await ctx.get('/');
    const html = await res.text();
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'public, max-age=300');
    assert.ok(html.includes('&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;x&quot;'));
    assert.ok(html.includes('O&#39;Brien'));
    assert.ok(!html.includes('<script>alert'));
  });

  test('GET / sends security headers and a request id', async () => {
    const res = await ctx.get('/');
    assert.match(res.headers.get('content-security-policy'), /default-src 'self'/);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('x-powered-by'), null);
    assert.ok(res.headers.get('x-request-id'));
  });

  test('GET /api/quote returns JSON', async () => {
    const res = await ctx.get('/api/quote');
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'public, max-age=300');
    assert.deepEqual(await res.json(), QUOTE);
  });

  test('GET /static/style.css is cached for an hour', async () => {
    const res = await ctx.get('/static/style.css');
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'public, max-age=3600');
  });

  test('GET /health reports a reachable database', async () => {
    const res = await ctx.get('/health');
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'no-cache');
    assert.equal((await res.json()).database, 'connected');
  });

  test('unknown paths return 404', async () => {
    const res = await ctx.get('/nope');
    assert.equal(res.status, 404);
  });
});

describe('when the database is down', () => {
  const ctx = serve({ pool: fakePool({ fail: true }) });

  test('GET /health returns 503 without leaking the error', async () => {
    const res = await ctx.get('/health');
    const body = await res.text();
    assert.equal(res.status, 503);
    assert.ok(!body.includes('ECONNREFUSED'));
    assert.ok(!body.includes('10.0.1.2'));
  });

  test('GET /livez still returns 200', async () => {
    const res = await ctx.get('/livez');
    assert.equal(res.status, 200);
  });

  test('GET /api/quote returns a generic 500', async () => {
    const res = await ctx.get('/api/quote');
    const body = await res.text();
    assert.equal(res.status, 500);
    assert.ok(!body.includes('ECONNREFUSED'));
  });
});

describe('with an empty quotes table', () => {
  const ctx = serve({ pool: fakePool({ rows: [] }) });

  test('GET /api/quote returns 404', async () => {
    const res = await ctx.get('/api/quote');
    assert.equal(res.status, 404);
  });
});

describe('with a Cloudflare secret', () => {
  const ctx = serve({ pool: fakePool({ rows: [QUOTE] }), cloudflareSecret: 's3cret-value' });

  test('rejects requests without the header', async () => {
    const res = await ctx.get('/api/quote');
    assert.equal(res.status, 403);
  });

  test('rejects requests with a wrong header', async () => {
    const res = await ctx.get('/', { 'X-Cloudflare-Secret': 'wrong' });
    assert.equal(res.status, 403);
  });

  test('accepts requests with the right header', async () => {
    const res = await ctx.get('/api/quote', { 'X-Cloudflare-Secret': 's3cret-value' });
    assert.equal(res.status, 200);
  });

  test('health endpoints do not need the header', async () => {
    assert.equal((await ctx.get('/health')).status, 200);
    assert.equal((await ctx.get('/livez')).status, 200);
  });
});
