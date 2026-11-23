const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const app = require('../src/app');
const config = require('../src/config');
const { setTokenVerifierForTesting } = require('../src/middleware/auth');
const { setEmergencyLoaderForTesting } = require('../src/services/emergencyContextService');
const {
  setMockElevenLabsClient,
  isElevenLabsConfigured,
  transcribeAudio,
  synthesizeSpeech,
} = require('../src/services/elevenLabsService');
const { resetRateLimiterForTesting } = require('../src/middleware/rateLimit');

test('ElevenLabs Voice Emergency Assistant Backend Tests', async (t) => {
  let server;
  let baseUrl;

  const mockEmergency = {
    id: 'EM-VOICE-1',
    victimId: 'victim_user_1',
    type: 'CARDIAC',
    status: 'ASSIGNED',
    helperId: 'responder_user_1',
    createdAt: new Date(Date.now() - 60000).toISOString(),
    responders: {
      'responder_user_1': { role: 'PRIMARY', distanceToVictim: 300.0, etaText: '3 min', isRoadRoute: true },
      'responder_standby_2': { role: 'STANDBY', distanceToVictim: 1200.0, etaText: '9 min', isRoadRoute: true },
    },
  };

  t.beforeEach(async () => {
    resetRateLimiterForTesting();
    server = http.createServer(app);
    await new Promise(resolve => server.listen(0, resolve));
    baseUrl = `http://localhost:${server.address().port}`;

    setTokenVerifierForTesting(async (token) => {
      if (token === 'victim_token') return { uid: 'victim_user_1' };
      if (token === 'responder_token') return { uid: 'responder_user_1' };
      if (token === 'standby_token') return { uid: 'responder_standby_2' };
      if (token === 'unauthorized_token') return { uid: 'unauthorized_attacker_9' };
      throw new Error('Invalid token');
    });

    setEmergencyLoaderForTesting(async (id) => (id === 'EM-VOICE-1' ? mockEmergency : null));

    // Default mock client
    setMockElevenLabsClient({
      transcribe: async ({ audioBuffer, mimeType, language }) => ({
        success: true,
        transcript: 'Tell me the nearest hospital for this victim.',
        language: language || 'en',
        model: 'scribe_v2',
      }),
      synthesize: async ({ text, voiceId, language }) => ({
        audioBuffer: Buffer.from([0xFF, 0xFB, 0x90, 0x64]), // Mock MP3 sync frame
        contentType: 'audio/mpeg',
        model: 'eleven_flash_v2_5',
        voiceId: voiceId || '21m00Tcm4TlvDq8ikWAM',
      }),
    });
  });

  t.afterEach(async () => {
    setTokenVerifierForTesting(null);
    setEmergencyLoaderForTesting(null);
    setMockElevenLabsClient(null);
    resetRateLimiterForTesting();
    await new Promise(resolve => server.close(resolve));
  });

  // =========================================================================
  // 1. Authentication & Authorization Tests
  // =========================================================================
  await t.test('POST /api/voice/transcribe rejects requests without Authorization header with 401', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('dummy audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      body: formData,
    });

    assert.strictEqual(res.status, 401);
    const body = await res.json();
    assert.strictEqual(body.error, 'UNAUTHORIZED');
  });

  await t.test('POST /api/voice/speak rejects non-Bearer token with 401', async () => {
    const res = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Basic dXNlcjpwYXNz',
      },
      body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: 'Hello' }),
    });

    assert.strictEqual(res.status, 401);
    const body = await res.json();
    assert.strictEqual(body.error, 'UNAUTHORIZED');
  });

  await t.test('POST /api/voice/transcribe rejects invalid token with 401', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('dummy audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer bad_expired_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 401);
    const body = await res.json();
    assert.strictEqual(body.error, 'UNAUTHORIZED');
  });

  // =========================================================================
  // 2. Participant Authorization & Validation Tests
  // =========================================================================
  await t.test('Rejects voice transcription when emergencyId is missing with 400', async () => {
    const formData = new FormData();
    formData.append('audio', new Blob([Buffer.from('dummy audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'MISSING_EMERGENCY_ID');
  });

  await t.test('Rejects speech synthesis when emergencyId is missing with 400', async () => {
    const res = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer responder_token',
      },
      body: JSON.stringify({ text: 'Nearest hospital is 2 km away.' }),
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'MISSING_EMERGENCY_ID');
  });

  await t.test('Rejects voice requests for non-existent emergency with 404', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'NON-EXISTENT-EMERGENCY');
    formData.append('audio', new Blob([Buffer.from('dummy audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 404);
    const body = await res.json();
    assert.strictEqual(body.error, 'EMERGENCY_NOT_FOUND');
  });

  await t.test('Rejects unauthorized third-party user from voice endpoints with 403 Forbidden', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('dummy audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer unauthorized_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 403);
    const body = await res.json();
    assert.strictEqual(body.error, 'FORBIDDEN');

    // Also verify /speak
    const speakRes = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer unauthorized_token',
      },
      body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: 'Where is the hospital?' }),
    });

    assert.strictEqual(speakRes.status, 403);
    const speakBody = await speakRes.json();
    assert.strictEqual(speakBody.error, 'FORBIDDEN');
  });

  await t.test('Authorizes assigned primary responder to transcribe and speak', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('test audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.success, true);
    assert.strictEqual(body.transcript, 'Tell me the nearest hospital for this victim.');

    const speakRes = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer responder_token',
      },
      body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: 'Hospital is 1 kilometer away.' }),
    });

    assert.strictEqual(speakRes.status, 200);
    assert.strictEqual(speakRes.headers.get('content-type'), 'audio/mpeg');
  });

  await t.test('Authorizes standby responder to participate in voice assistance', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('standby test audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer standby_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.success, true);
  });

  // =========================================================================
  // 3. Audio Validation & Size Limits
  // =========================================================================
  await t.test('Rejects transcription when audio field is missing with 400', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'MISSING_AUDIO');
  });

  await t.test('Rejects transcription when audio buffer is 0 bytes with 400', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.alloc(0)], { type: 'audio/m4a' }), 'empty.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'MISSING_AUDIO');
  });

  await t.test('Rejects unsupported non-audio file types with 400 UNSUPPORTED_AUDIO_FORMAT', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('not an audio file')], { type: 'text/plain' }), 'notes.txt');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'UNSUPPORTED_AUDIO_FORMAT');
  });

  await t.test('Rejects audio upload exceeding 2 MB limit with 400 AUDIO_TOO_LARGE', async () => {
    const largeBuffer = Buffer.alloc(2.2 * 1024 * 1024); // 2.2 MB (exceeds 2 MB limit)
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([largeBuffer], { type: 'audio/m4a' }), 'large.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'AUDIO_TOO_LARGE');
  });

  // =========================================================================
  // 4. Successful Transcription & TTS Generation
  // =========================================================================
  await t.test('Transcribes audio in Hindi when language parameter is hi', async () => {
    setMockElevenLabsClient({
      transcribe: async ({ language }) => ({
        success: true,
        transcript: 'निकटतम अस्पताल की दूरी क्या है?',
        language,
        model: 'scribe_v2',
      }),
    });

    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('language', 'hi');
    formData.append('audio', new Blob([Buffer.from('hindi audio')], { type: 'audio/wav' }), 'audio.wav');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.success, true);
    assert.strictEqual(body.language, 'hi');
    assert.strictEqual(body.model, 'scribe_v2');
    assert.ok(body.transcript.includes('अस्पताल'));
  });

  await t.test('Synthesizes speech and returns binary audio/mpeg with correct headers', async () => {
    const mockAudio = Buffer.from([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00]); // ID3 header
    setMockElevenLabsClient({
      synthesize: async ({ text, voiceId, language }) => ({
        audioBuffer: mockAudio,
        contentType: 'audio/mpeg',
        model: 'eleven_flash_v2_5',
        voiceId: voiceId || '21m00Tcm4TlvDq8ikWAM',
      }),
    });

    const res = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer responder_token',
      },
      body: JSON.stringify({
        emergencyId: 'EM-VOICE-1',
        text: 'The nearest verified hospital is City Hospital, 1.2 kilometers away.',
      }),
    });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.headers.get('content-type'), 'audio/mpeg');
    assert.strictEqual(res.headers.get('content-length'), String(mockAudio.length));
    assert.strictEqual(res.headers.get('x-voice-model'), 'eleven_flash_v2_5');

    const arrayBuffer = await res.arrayBuffer();
    const receivedBuffer = Buffer.from(arrayBuffer);
    assert.deepStrictEqual(receivedBuffer, mockAudio);
  });

  await t.test('Rejects speech synthesis when text is missing or empty with 400', async () => {
    const res = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer responder_token',
      },
      body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: '   ' }),
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'MISSING_TEXT');
  });

  await t.test('Rejects speech synthesis when text exceeds 500 characters with 400 TEXT_TOO_LONG', async () => {
    const longText = 'Emergency instructions '.repeat(30); // > 500 chars

    const res = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer responder_token',
      },
      body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: longText }),
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'TEXT_TOO_LONG');
  });

  // =========================================================================
  // 5. Credential Missing & Readiness Tests
  // =========================================================================
  await t.test('Returns 503 when ElevenLabs API key is unconfigured and no mock client is active', async () => {
    setMockElevenLabsClient(null);
    const originalKey = config.elevenLabsApiKey;
    config.elevenLabsApiKey = '';

    try {
      assert.strictEqual(isElevenLabsConfigured(), false);

      const formData = new FormData();
      formData.append('emergencyId', 'EM-VOICE-1');
      formData.append('audio', new Blob([Buffer.from('dummy')], { type: 'audio/m4a' }), 'test.m4a');

      const transcribeRes = await fetch(`${baseUrl}/api/voice/transcribe`, {
        method: 'POST',
        headers: { 'Authorization': 'Bearer responder_token' },
        body: formData,
      });

      assert.strictEqual(transcribeRes.status, 503);
      const transcribeBody = await transcribeRes.json();
      assert.strictEqual(transcribeBody.error, 'ELEVENLABS_KEY_MISSING');

      const speakRes = await fetch(`${baseUrl}/api/voice/speak`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer responder_token',
        },
        body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: 'Testing unconfigured credentials.' }),
      });

      assert.strictEqual(speakRes.status, 503);
      const speakBody = await speakRes.json();
      assert.strictEqual(speakBody.error, 'ELEVENLABS_KEY_MISSING');
    } finally {
      config.elevenLabsApiKey = originalKey;
    }
  });

  await t.test('setMockElevenLabsClient throws when called in production mode', async () => {
    const originalEnv = config.nodeEnv;
    config.nodeEnv = 'production';

    try {
      assert.throws(
        () => setMockElevenLabsClient({}),
        /Test ElevenLabs client cannot be set in production mode/
      );
    } finally {
      config.nodeEnv = originalEnv;
    }
  });

  // =========================================================================
  // 6. Provider Error Handling (Timeout, Rate Limits, Empty Speech)
  // =========================================================================
  await t.test('Handles provider timeout with 504 VOICE_TIMEOUT', async () => {
    setMockElevenLabsClient({
      transcribe: async () => {
        const err = new Error('ElevenLabs STT request timed out after 15000ms.');
        err.statusCode = 504;
        err.code = 'VOICE_TIMEOUT';
        throw err;
      },
    });

    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('slow audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 504);
    const body = await res.json();
    assert.strictEqual(body.error, 'VOICE_TIMEOUT');
  });

  await t.test('Handles provider 429 quota exhaustion with 429 ELEVENLABS_RATE_LIMITED', async () => {
    setMockElevenLabsClient({
      transcribe: async () => {
        const err = new Error('ElevenLabs API quota exceeded or rate-limited. Please retry shortly.');
        err.statusCode = 429;
        err.code = 'ELEVENLABS_RATE_LIMITED';
        throw err;
      },
    });

    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('quota audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 429);
    const body = await res.json();
    assert.strictEqual(body.error, 'ELEVENLABS_RATE_LIMITED');
  });

  await t.test('Handles empty speech detection with 400 NO_SPEECH_DETECTED', async () => {
    setMockElevenLabsClient({
      transcribe: async () => {
        const err = new Error('No speech could be detected in the provided audio.');
        err.statusCode = 400;
        err.code = 'NO_SPEECH_DETECTED';
        throw err;
      },
    });

    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('silent audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.error, 'NO_SPEECH_DETECTED');
  });

  await t.test('Handles provider 500 failure with 502 VOICE_PROVIDER_ERROR', async () => {
    setMockElevenLabsClient({
      synthesize: async () => {
        const err = new Error('ElevenLabs text-to-speech failed: internal server error');
        err.statusCode = 502;
        err.code = 'VOICE_PROVIDER_ERROR';
        throw err;
      },
    });

    const res = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer responder_token',
      },
      body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: 'Error test' }),
    });

    assert.strictEqual(res.status, 502);
    const body = await res.json();
    assert.strictEqual(body.error, 'VOICE_PROVIDER_ERROR');
  });

  // =========================================================================
  // 7. Per-User Rate Limiting (5 requests per minute)
  // =========================================================================
  await t.test('Enforces voice per-user rate limit (5 requests / min) returning 429 with Retry-After', async () => {
    const limit = config.voiceRateLimitMaxRequests; // 5
    assert.strictEqual(limit, 5);

    // Send requests up to limit
    for (let i = 0; i < limit; i++) {
      const res = await fetch(`${baseUrl}/api/voice/speak`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer responder_token',
        },
        body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: `Message #${i}` }),
      });
      assert.strictEqual(res.status, 200, `Request ${i} should succeed under rate limit`);
    }

    // 6th request within window must be rejected with 429
    const throttledRes = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer responder_token',
      },
      body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: 'Throttled message' }),
    });

    assert.strictEqual(throttledRes.status, 429);
    assert.ok(throttledRes.headers.get('retry-after') !== null);

    const body = await throttledRes.json();
    assert.strictEqual(body.error, 'VOICE_RATE_LIMIT_EXCEEDED');
    assert.ok(body.retryAfterSeconds > 0);
  });

  // =========================================================================
  // 8. Privacy, Memory Only & Immutability Verification
  // =========================================================================
  await t.test('Verifies audio is processed in memory and no audio files are written to disk', async () => {
    const tempDirFilesBefore = fs.readdirSync(path.resolve(__dirname, '..'));

    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('transient audio data')], { type: 'audio/m4a' }), 'transient.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    assert.strictEqual(res.status, 200);

    const tempDirFilesAfter = fs.readdirSync(path.resolve(__dirname, '..'));
    // Confirm no new files or audio artifacts were written to backend directory
    assert.deepStrictEqual(tempDirFilesAfter, tempDirFilesBefore);
  });

  await t.test('Verifies voice endpoints never leak secrets, API keys, or private tokens', async () => {
    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('test audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const res = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });

    const body = await res.json();
    assert.strictEqual(body.apiKey, undefined);
    assert.strictEqual(body.elevenLabsApiKey, undefined);
    assert.strictEqual(body.token, undefined);
  });

  await t.test('Verifies emergency record remains strictly immutable across voice operations', async () => {
    const frozenRecord = Object.freeze(JSON.parse(JSON.stringify(mockEmergency)));
    setEmergencyLoaderForTesting(async () => frozenRecord);

    const formData = new FormData();
    formData.append('emergencyId', 'EM-VOICE-1');
    formData.append('audio', new Blob([Buffer.from('audio')], { type: 'audio/m4a' }), 'audio.m4a');

    const transcribeRes = await fetch(`${baseUrl}/api/voice/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer responder_token' },
      body: formData,
    });
    assert.strictEqual(transcribeRes.status, 200);

    const speakRes = await fetch(`${baseUrl}/api/voice/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer responder_token',
      },
      body: JSON.stringify({ emergencyId: 'EM-VOICE-1', text: 'Checking immutability' }),
    });
    assert.strictEqual(speakRes.status, 200);

    // Emergency record state must remain identical
    assert.deepStrictEqual(frozenRecord, mockEmergency);
  });
});
