const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const app = require('../src/app');
const config = require('../src/config');
const { setTokenVerifierForTesting } = require('../src/middleware/auth');
const { setEmergencyLoaderForTesting } = require('../src/services/emergencyContextService');
const { setMockGeminiClient } = require('../src/services/geminiService');
const { resetRateLimiterForTesting } = require('../src/middleware/rateLimit');

test('Gemini Assistant Endpoint Tests', async (t) => {
  let server;
  let baseUrl;

  const mockEmergency = {
    id: 'EM-1',
    victimId: 'test_user_100',
    type: 'MEDICAL',
    status: 'ASSIGNED',
    helperId: 'resp_1',
    createdAt: new Date(Date.now() - 120000).toISOString(),
    responders: {
      'resp_1': { role: 'PRIMARY', distanceToVictim: 450.0, etaText: '4 min', isRoadRoute: true },
    },
  };

  t.beforeEach(async () => {
    resetRateLimiterForTesting();
    server = http.createServer(app);
    await new Promise(resolve => server.listen(0, resolve));
    baseUrl = `http://localhost:${server.address().port}`;

    setTokenVerifierForTesting(async () => ({ uid: 'test_user_100' }));
    setEmergencyLoaderForTesting(async (id) => (id === 'EM-1' ? mockEmergency : null));
  });

  t.afterEach(async () => {
    setTokenVerifierForTesting(null);
    setEmergencyLoaderForTesting(null);
    setMockGeminiClient(null);
    resetRateLimiterForTesting();
    await new Promise(resolve => server.close(resolve));
  });

  await t.test('Answers valid English question based on authoritative context using @google/genai API', async () => {
    setMockGeminiClient({
      models: {
        generateContent: async ({ model, contents, config: genConfig }) => {
          assert.strictEqual(model, 'gemini-3.8-flash');
          assert.ok(contents.includes('Current Verified Emergency Status'));
          assert.ok(contents.includes('Approximately 450 meters'));
          assert.ok(genConfig.systemInstruction.includes('Vita ResQ'));
          assert.deepStrictEqual(genConfig.thinkingConfig, { thinkingLevel: 'low' });
          return {
            text: 'Your primary responder is approximately 450 meters away and arriving shortly. Please stay in a safe place.',
          };
        },
      },
    });

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_jwt',
      },
      body: JSON.stringify({
        emergencyId: 'EM-1',
        query: 'How far is my responder?',
        language: 'en',
      }),
    });

    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.success, true);
    assert.ok(body.answer.includes('450 meters'));
    assert.strictEqual(body.language, 'en');
    assert.strictEqual(body.model, 'gemini-3.8-flash');
    assert.ok(body.disclaimer.includes('Does not replace official 112'));
  });

  await t.test('Supports Hindi requests and returns Hindi disclaimer', async () => {
    setMockGeminiClient({
      models: {
        generateContent: async ({ model, contents, config: genConfig }) => {
          assert.ok(genConfig.systemInstruction.includes('वीटा रेस्क्यू'));
          return {
            text: 'आपका प्राथमिक प्रतिक्रियाकर्ता लगभग 500 मीटर की दूरी पर है। कृपया शांत रहें।',
          };
        },
      },
    });

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_jwt',
      },
      body: JSON.stringify({
        emergencyId: 'EM-1',
        query: 'मदद कितनी दूर है?',
        language: 'hi',
      }),
    });

    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.success, true);
    assert.strictEqual(body.language, 'hi');
    assert.ok(body.disclaimer.includes('AI द्वारा उत्पन्न विवरण'));
  });

  await t.test('Rejects queries exceeding maximum 500 character limit with 400', async () => {
    const longQuery = 'A'.repeat(501);

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_jwt',
      },
      body: JSON.stringify({ emergencyId: 'EM-1', query: longQuery }),
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'QUERY_TOO_LONG');
  });

  await t.test('Returns 503 when Gemini API key is missing', async () => {
    const originalKey = config.geminiApiKey;
    config.geminiApiKey = ''; // temporarily clear key
    setMockGeminiClient(null);

    try {
      const res = await fetch(`${baseUrl}/api/ai/assistant`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer valid_jwt',
        },
        body: JSON.stringify({ emergencyId: 'EM-1', query: 'Where is help?' }),
      });

      assert.strictEqual(res.status, 503);
      const body = await res.json();
      assert.strictEqual(body.error, 'GEMINI_KEY_MISSING');
      assert.ok(body.message.includes('GEMINI_API_KEY in backend/.env'));
    } finally {
      config.geminiApiKey = originalKey;
    }
  });

  await t.test('Handles provider timeout gracefully with 504', async () => {
    const originalTimeout = config.aiRequestTimeoutMs;
    config.aiRequestTimeoutMs = 50; // set short timeout for test

    setMockGeminiClient({
      models: {
        generateContent: () => new Promise(resolve => setTimeout(resolve, 200)), // slow promise
      },
    });

    try {
      const res = await fetch(`${baseUrl}/api/ai/assistant`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer valid_jwt',
        },
        body: JSON.stringify({ emergencyId: 'EM-1', query: 'Where is help?' }),
      });

      assert.strictEqual(res.status, 504);
      const body = await res.json();
      assert.strictEqual(body.error, 'AI_TIMEOUT');
    } finally {
      config.aiRequestTimeoutMs = originalTimeout;
    }
  });

  await t.test('Handles empty provider output with 502 Bad Gateway', async () => {
    setMockGeminiClient({
      models: {
        generateContent: async () => ({
          text: '', // empty text
        }),
      },
    });

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_jwt',
      },
      body: JSON.stringify({ emergencyId: 'EM-1', query: 'Status update' }),
    });

    assert.strictEqual(res.status, 502);
    const body = await res.json();
    assert.strictEqual(body.error, 'AI_EMPTY_RESPONSE');
  });

  await t.test('Handles Gemini HTTP 429 quota exhaustion gracefully', async () => {
    setMockGeminiClient({
      models: {
        generateContent: async () => {
          const quotaErr = new Error('Resource has been exhausted (e.g. check quota).');
          quotaErr.status = 429;
          throw quotaErr;
        },
      },
    });

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_jwt',
      },
      body: JSON.stringify({ emergencyId: 'EM-1', query: 'Status check' }),
    });

    assert.strictEqual(res.status, 429);
    const body = await res.json();
    assert.strictEqual(body.error, 'GEMINI_RATE_LIMITED');
  });

  await t.test('Verifies assistant operates read-only and never mutates authoritative record', async () => {
    const frozenRecord = Object.freeze(JSON.parse(JSON.stringify(mockEmergency)));
    setEmergencyLoaderForTesting(async () => frozenRecord);

    setMockGeminiClient({
      models: {
        generateContent: async () => ({
          text: 'Responder is en route.',
        }),
      },
    });

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_jwt',
      },
      body: JSON.stringify({
        emergencyId: 'EM-1',
        query: 'What is happening?',
      }),
    });

    assert.strictEqual(res.status, 200);
    // Verified frozenRecord remains intact and unmodified
    assert.deepStrictEqual(frozenRecord, mockEmergency);
  });

  await t.test('Verifies low thinking configuration is sent to Gemini models.generateContent', async () => {
    let receivedConfig = null;
    setMockGeminiClient({
      models: {
        generateContent: async ({ config: genConfig }) => {
          receivedConfig = genConfig;
          return { text: 'Everything is operational.' };
        },
      },
    });

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer valid_jwt',
      },
      body: JSON.stringify({
        emergencyId: 'EM-1',
        query: 'Status update',
      }),
    });

    assert.strictEqual(res.status, 200);
    assert.ok(receivedConfig);
    assert.deepStrictEqual(receivedConfig.thinkingConfig, { thinkingLevel: 'low' });
    assert.strictEqual(receivedConfig.temperature, 0.2);
    assert.strictEqual(receivedConfig.maxOutputTokens, 300);
  });
});
