const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const app = require('../src/app');
const config = require('../src/config');
const { setTokenVerifierForTesting } = require('../src/middleware/auth');
const { setMockGeminiClient } = require('../src/services/geminiService');
const { resetRateLimiterForTesting } = require('../src/middleware/rateLimit');

test('Per-User Rate Limiting Tests', async (t) => {
  let server;
  let baseUrl;

  t.beforeEach(async () => {
    resetRateLimiterForTesting();
    server = http.createServer(app);
    await new Promise(resolve => server.listen(0, resolve));
    baseUrl = `http://localhost:${server.address().port}`;

    setTokenVerifierForTesting(async () => ({ uid: 'rate_limited_user_1' }));
    setMockGeminiClient({
      getGenerativeModel: () => ({
        generateContent: async () => ({
          response: { text: () => 'All systems normal.' },
        }),
      }),
    });
  });

  t.afterEach(async () => {
    setTokenVerifierForTesting(null);
    setMockGeminiClient(null);
    resetRateLimiterForTesting();
    await new Promise(resolve => server.close(resolve));
  });

  await t.test('Enforces maximum request limit and returns 429 with Retry-After header', async () => {
    const limit = config.rateLimitMaxRequests; // e.g. 10

    // Send requests up to limit
    for (let i = 0; i < limit; i++) {
      const res = await fetch(`${baseUrl}/api/ai/assistant`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer valid_token',
        },
        body: JSON.stringify({ query: `Request #${i}` }),
      });
      assert.strictEqual(res.status, 200, `Request ${i} should succeed`);
    }

    // Next request must be rate limited
    const throttledRes = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_token',
      },
      body: JSON.stringify({ query: 'Throttled request' }),
    });

    assert.strictEqual(throttledRes.status, 429);
    assert.ok(throttledRes.headers.get('retry-after') !== null);

    const body = await throttledRes.json();
    assert.strictEqual(body.error, 'RATE_LIMIT_EXCEEDED');
    assert.ok(typeof body.retryAfterSeconds === 'number');
    assert.ok(body.retryAfterSeconds > 0);
  });
});
