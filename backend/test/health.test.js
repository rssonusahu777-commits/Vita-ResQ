const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const app = require('../src/app');

test('GET /api/health returns 200 with non-sensitive readiness metadata', async (t) => {
  const server = http.createServer(app);
  await new Promise(resolve => server.listen(0, resolve));
  const port = server.address().port;

  try {
    const res = await fetch(`http://localhost:${port}/api/health`);
    assert.strictEqual(res.status, 200);

    const body = await res.json();
    assert.strictEqual(body.status, 'ok');
    assert.strictEqual(body.service, 'vita-resq-ai-backend');
    assert.strictEqual(body.version, '1.0.0');
    assert.strictEqual(body.model, 'gemini-3.8-flash');
    assert.ok(body.readiness);
    assert.strictEqual(body.readiness.processRunning, true);
    assert.ok(typeof body.readiness.firebaseAuthConfigured === 'boolean');
    assert.ok(typeof body.readiness.emergencyLookupConfigured === 'boolean');
    assert.ok(typeof body.readiness.geminiModelConfigured === 'boolean');
    assert.ok(typeof body.readiness.elevenLabsConfigured === 'boolean');
    assert.ok(body.voice);
    assert.strictEqual(body.voice.sttModel, 'scribe_v2');
    assert.strictEqual(body.voice.ttsModel, 'eleven_flash_v2_5');
    assert.ok(typeof body.timestamp === 'string');

    // Verify secrets are NOT exposed
    assert.strictEqual(body.apiKey, undefined);
    assert.strictEqual(body.geminiApiKey, undefined);
    assert.strictEqual(body.elevenLabsApiKey, undefined);
    assert.strictEqual(body.googleApplicationCredentials, undefined);
    assert.strictEqual(body.privateKey, undefined);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
