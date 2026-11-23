const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const app = require('../src/app');
const config = require('../src/config');
const {
  setTokenVerifierForTesting,
  setForceUnconfiguredForTesting,
  resetFirebaseAdminForTesting,
  initFirebaseAdmin,
} = require('../src/middleware/auth');
const { setEmergencyLoaderForTesting } = require('../src/services/emergencyContextService');
const { setMockGeminiClient } = require('../src/services/geminiService');
const { resetRateLimiterForTesting } = require('../src/middleware/rateLimit');

test('Authentication and Authorization Verification', async (t) => {
  let server;
  let baseUrl;

  // Authoritative emergency records in mock database
  const mockEmergencies = {
    'EM-101': {
      id: 'EM-101',
      victimId: 'victim_user_123',
      helperId: 'primary_helper_789',
      type: 'MEDICAL',
      status: 'ASSIGNED',
      createdAt: new Date().toISOString(),
      responders: {
        'primary_helper_789': { role: 'PRIMARY', distanceToVictim: 400.0, etaText: '3 min' },
        'standby_helper_456': { role: 'STANDBY' },
      },
    },
  };

  t.beforeEach(async () => {
    resetRateLimiterForTesting();
    server = http.createServer(app);
    await new Promise(resolve => server.listen(0, resolve));
    baseUrl = `http://localhost:${server.address().port}`;

    setEmergencyLoaderForTesting(async (id) => mockEmergencies[id] || null);
  });

  t.afterEach(async () => {
    setTokenVerifierForTesting(null);
    setForceUnconfiguredForTesting(false);
    setEmergencyLoaderForTesting(null);
    setMockGeminiClient(null);
    await new Promise(resolve => server.close(resolve));
  });

  await t.test('Rejects request without Authorization header with 401', async () => {
    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ emergencyId: 'EM-101', query: 'What is happening?' }),
    });

    assert.strictEqual(res.status, 401);
    const body = await res.json();
    assert.strictEqual(body.error, 'UNAUTHORIZED');
  });

  await t.test('Rejects request with non-Bearer token with 401', async () => {
    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Basic invalidtoken',
      },
      body: JSON.stringify({ emergencyId: 'EM-101', query: 'Status update' }),
    });

    assert.strictEqual(res.status, 401);
  });

  await t.test('Rejects invalid token when verified by auth middleware', async () => {
    setTokenVerifierForTesting(async () => null); // token fails

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer invalid_jwt_token',
      },
      body: JSON.stringify({ emergencyId: 'EM-101', query: 'Status update' }),
    });

    assert.strictEqual(res.status, 401);
  });

  await t.test('Fails closed with 503 if Firebase credentials are unconfigured and no test hook is active', async () => {
    // Force unconfigured credentials state in test isolation
    setTokenVerifierForTesting(null);
    setForceUnconfiguredForTesting(true);

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer live_user_token',
      },
      body: JSON.stringify({ emergencyId: 'EM-101', query: 'Status update' }),
    });

    // Must fail closed with 503 AUTH_SERVICE_UNCONFIGURED (never silently bypassed)
    assert.strictEqual(res.status, 503);
    const body = await res.json();
    assert.strictEqual(body.error, 'AUTH_SERVICE_UNCONFIGURED');
  });

  await t.test('Authorizes victim to access their emergency via authoritative lookup', async () => {
    setTokenVerifierForTesting(async (token) => {
      if (token === 'victim_token') return { uid: 'victim_user_123' };
      return null;
    });

    setMockGeminiClient({
      models: {
        generateContent: async () => ({
          text: 'The emergency has been assigned to a responder.',
        }),
      },
    });

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer victim_token',
      },
      body: JSON.stringify({
        emergencyId: 'EM-101',
        query: 'What is the status?',
      }),
    });

    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.success, true);
  });

  await t.test('Authorizes registered standby responder to access emergency', async () => {
    setTokenVerifierForTesting(async (token) => {
      if (token === 'standby_token') return { uid: 'standby_helper_456' };
      return null;
    });

    setMockGeminiClient({
      models: {
        generateContent: async () => ({
          text: 'You are on standby for this medical emergency.',
        }),
      },
    });

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer standby_token',
      },
      body: JSON.stringify({
        emergencyId: 'EM-101',
        query: 'What is my role?',
      }),
    });

    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.success, true);
  });

  await t.test('Rejects unrelated third-party with 403 Forbidden', async () => {
    setTokenVerifierForTesting(async () => ({ uid: 'intruder_user_999' }));

    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer intruder_token',
      },
      body: JSON.stringify({
        emergencyId: 'EM-101',
        query: 'Where is the victim?',
      }),
    });

    assert.strictEqual(res.status, 403);
    const body = await res.json();
    assert.strictEqual(body.error, 'FORBIDDEN');
  });

  await t.test('CRITICAL SECURITY: Attacker cannot access emergency by forging clientContext or victimId', async () => {
    // Attacker authenticated with uid: attacker_404
    setTokenVerifierForTesting(async () => ({ uid: 'attacker_404' }));

    // Attacker attempts to forge victimId or helperId in client payload
    const res = await fetch(`${baseUrl}/api/ai/assistant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer attacker_token',
      },
      body: JSON.stringify({
        emergencyId: 'EM-101', // Victim is victim_user_123 in authoritative record
        clientContext: {
          id: 'EM-101',
          victimId: 'attacker_404', // Forged victim identity
          helperId: 'attacker_404', // Forged helper identity
        },
        query: 'Give me victim details',
      }),
    });

    // Must be rejected with 403 Forbidden because server checks authoritative Firestore record
    assert.strictEqual(res.status, 403);
    const body = await res.json();
    assert.strictEqual(body.error, 'FORBIDDEN');
  });

  await t.test('setTokenVerifierForTesting throws when called in production mode', () => {
    const originalEnv = config.nodeEnv;
    config.nodeEnv = 'production';
    try {
      assert.throws(() => {
        setTokenVerifierForTesting(() => ({ uid: 'test' }));
      }, /Test token verifier cannot be set in production mode/);
    } finally {
      config.nodeEnv = originalEnv;
    }
  });

  await t.test('setForceUnconfiguredForTesting throws when called in production mode', () => {
    const originalEnv = config.nodeEnv;
    config.nodeEnv = 'production';
    try {
      assert.throws(() => {
        setForceUnconfiguredForTesting(true);
      }, /Test unconfigured override cannot be set in production mode/);
    } finally {
      config.nodeEnv = originalEnv;
    }
  });

  await t.test('resetFirebaseAdminForTesting throws when called in production mode', () => {
    const originalEnv = config.nodeEnv;
    config.nodeEnv = 'production';
    try {
      assert.throws(() => {
        resetFirebaseAdminForTesting();
      }, /Test Firebase reset cannot be called in production mode/);
    } finally {
      config.nodeEnv = originalEnv;
    }
  });

  await t.test('Emulator initialization fails closed in production mode', async () => {
    const originalEnv = config.nodeEnv;
    const originalCreds = config.googleApplicationCredentials;
    const origGac = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    const origAuth = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const origFs = process.env.FIRESTORE_EMULATOR_HOST;
    const origProj = process.env.FIREBASE_PROJECT_ID;

    try {
      await resetFirebaseAdminForTesting();
      config.nodeEnv = 'production';
      config.googleApplicationCredentials = '';
      delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
      process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
      process.env.FIREBASE_PROJECT_ID = 'demo-vita-resq-local';

      assert.strictEqual(initFirebaseAdmin(), false);
    } finally {
      config.nodeEnv = originalEnv;
      config.googleApplicationCredentials = originalCreds;
      if (origGac) process.env.GOOGLE_APPLICATION_CREDENTIALS = origGac; else delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      if (origAuth) process.env.FIREBASE_AUTH_EMULATOR_HOST = origAuth; else delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
      if (origFs) process.env.FIRESTORE_EMULATOR_HOST = origFs; else delete process.env.FIRESTORE_EMULATOR_HOST;
      if (origProj) process.env.FIREBASE_PROJECT_ID = origProj; else delete process.env.FIREBASE_PROJECT_ID;
      await resetFirebaseAdminForTesting();
    }
  });

  await t.test('Emulator initialization fails closed if project ID is not a demo- project', async () => {
    const originalCreds = config.googleApplicationCredentials;
    const origGac = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    const origAuth = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const origFs = process.env.FIRESTORE_EMULATOR_HOST;
    const origProj = process.env.FIREBASE_PROJECT_ID;

    try {
      await resetFirebaseAdminForTesting();
      config.googleApplicationCredentials = '';
      delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
      process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
      process.env.FIREBASE_PROJECT_ID = 'vita-resq'; // Not demo-

      assert.strictEqual(initFirebaseAdmin(), false);
    } finally {
      config.googleApplicationCredentials = originalCreds;
      if (origGac) process.env.GOOGLE_APPLICATION_CREDENTIALS = origGac; else delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      if (origAuth) process.env.FIREBASE_AUTH_EMULATOR_HOST = origAuth; else delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
      if (origFs) process.env.FIRESTORE_EMULATOR_HOST = origFs; else delete process.env.FIRESTORE_EMULATOR_HOST;
      if (origProj) process.env.FIREBASE_PROJECT_ID = origProj; else delete process.env.FIREBASE_PROJECT_ID;
      await resetFirebaseAdminForTesting();
    }
  });

  await t.test('Emulator initialization fails closed if host is non-loopback', async () => {
    const originalCreds = config.googleApplicationCredentials;
    const origGac = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    const origAuth = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const origFs = process.env.FIRESTORE_EMULATOR_HOST;
    const origProj = process.env.FIREBASE_PROJECT_ID;

    try {
      await resetFirebaseAdminForTesting();
      config.googleApplicationCredentials = '';
      delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      process.env.FIREBASE_AUTH_EMULATOR_HOST = '192.168.1.50:9099'; // Remote / non-loopback
      process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
      process.env.FIREBASE_PROJECT_ID = 'demo-vita-resq-local';

      assert.strictEqual(initFirebaseAdmin(), false);
    } finally {
      config.googleApplicationCredentials = originalCreds;
      if (origGac) process.env.GOOGLE_APPLICATION_CREDENTIALS = origGac; else delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      if (origAuth) process.env.FIREBASE_AUTH_EMULATOR_HOST = origAuth; else delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
      if (origFs) process.env.FIRESTORE_EMULATOR_HOST = origFs; else delete process.env.FIRESTORE_EMULATOR_HOST;
      if (origProj) process.env.FIREBASE_PROJECT_ID = origProj; else delete process.env.FIREBASE_PROJECT_ID;
      await resetFirebaseAdminForTesting();
    }
  });

  await t.test('Emulator initialization succeeds when all loopback demo conditions are met', async () => {
    const originalCreds = config.googleApplicationCredentials;
    const origGac = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    const origAuth = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const origFs = process.env.FIRESTORE_EMULATOR_HOST;
    const origProj = process.env.FIREBASE_PROJECT_ID;

    try {
      await resetFirebaseAdminForTesting();
      config.googleApplicationCredentials = '';
      delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
      process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
      process.env.FIREBASE_PROJECT_ID = 'demo-vita-resq-local';

      assert.strictEqual(initFirebaseAdmin(), true);
    } finally {
      config.googleApplicationCredentials = originalCreds;
      if (origGac) process.env.GOOGLE_APPLICATION_CREDENTIALS = origGac; else delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      if (origAuth) process.env.FIREBASE_AUTH_EMULATOR_HOST = origAuth; else delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
      if (origFs) process.env.FIRESTORE_EMULATOR_HOST = origFs; else delete process.env.FIRESTORE_EMULATOR_HOST;
      if (origProj) process.env.FIREBASE_PROJECT_ID = origProj; else delete process.env.FIREBASE_PROJECT_ID;
      await resetFirebaseAdminForTesting();
    }
  });
});
