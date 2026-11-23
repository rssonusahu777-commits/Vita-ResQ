const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const app = require('../src/app');
const { setTokenVerifierForTesting } = require('../src/middleware/auth');
const { setEmergencyLoaderForTesting } = require('../src/services/emergencyContextService');
const { setMockGeminiClient } = require('../src/services/geminiService');
const { resetRateLimiterForTesting } = require('../src/middleware/rateLimit');

test('Emergency Situation Brief Endpoint Tests', async (t) => {
  let server;
  let baseUrl;

  const mockEmergency = {
    id: 'EM-BRIEF-1',
    victimId: 'victim_user_brief',
    type: 'MEDICAL',
    status: 'ASSIGNED',
    helperId: 'responder_1',
    createdAt: new Date(Date.now() - 300000).toISOString(),
    responders: {
      'responder_1': { role: 'PRIMARY', distanceToVictim: 350.0, etaText: '3 min', isRoadRoute: true },
    },
  };

  t.beforeEach(async () => {
    resetRateLimiterForTesting();
    server = http.createServer(app);
    await new Promise(resolve => server.listen(0, resolve));
    baseUrl = `http://localhost:${server.address().port}`;

    setTokenVerifierForTesting(async () => ({ uid: 'victim_user_brief' }));
    setEmergencyLoaderForTesting(async (id) => (id === 'EM-BRIEF-1' ? mockEmergency : null));
  });

  t.afterEach(async () => {
    setTokenVerifierForTesting(null);
    setEmergencyLoaderForTesting(null);
    setMockGeminiClient(null);
    resetRateLimiterForTesting();
    await new Promise(resolve => server.close(resolve));
  });

  await t.test('Rejects emergency-brief request without emergencyId with 400', async () => {
    const res = await fetch(`${baseUrl}/api/ai/emergency-brief`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_jwt',
      },
      body: JSON.stringify({ language: 'en' }),
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'MISSING_EMERGENCY_ID');
  });

  await t.test('Rejects unauthorized caller trying to brief another user emergency with 403', async () => {
    setTokenVerifierForTesting(async () => ({ uid: 'unauthorized_stranger' }));

    const res = await fetch(`${baseUrl}/api/ai/emergency-brief`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer stranger_jwt',
      },
      body: JSON.stringify({
        emergencyId: 'EM-BRIEF-1',
        language: 'en',
      }),
    });

    assert.strictEqual(res.status, 403);
    const body = await res.json();
    assert.strictEqual(body.error, 'FORBIDDEN');
  });

  await t.test('Generates brief with authoritative emergency data for authorized victim', async () => {
    setMockGeminiClient({
      models: {
        generateContent: async ({ model, contents }) => {
          assert.strictEqual(model, 'gemini-3.8-flash');
          assert.ok(contents.includes('MEDICAL'));
          assert.ok(contents.includes('ASSIGNED'));
          return {
            text: 'A community responder has been assigned and is navigating toward your location. Please remain calm and keep your device accessible.',
          };
        },
      },
    });

    const res = await fetch(`${baseUrl}/api/ai/emergency-brief`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_jwt',
      },
      body: JSON.stringify({
        emergencyId: 'EM-BRIEF-1',
        language: 'en',
      }),
    });

    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.success, true);
    assert.strictEqual(body.model, 'gemini-3.8-flash');
    assert.ok(body.answer.includes('community responder'));
    assert.ok(body.disclaimer.includes('verified app data'));
  });
});
