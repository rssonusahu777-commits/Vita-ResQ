const config = require('../config');

/**
 * ElevenLabs Service for Speech-to-Text (STT) and Text-to-Speech (TTS).
 * 
 * Official APIs:
 * - STT: POST https://api.elevenlabs.io/v1/speech-to-text
 *   Model: scribe_v2 (official standard model)
 * - TTS: POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}
 *   Model: eleven_flash_v2_5 (ultra-low latency ~75ms)
 * 
 * Safety & Privacy:
 * - In-memory audio handling only: raw recordings are never persisted to disk or DB.
 * - API keys and credentials are kept strictly on the backend.
 * - Deterministic test injection via setMockElevenLabsClient (forbidden in production).
 */

let mockElevenLabsClient = null;

/**
 * Injects a mock ElevenLabs client for automated unit and integration testing.
 * Strictly forbidden in production environments.
 */
function setMockElevenLabsClient(client) {
  if (config.nodeEnv === 'production') {
    throw new Error('Test ElevenLabs client cannot be set in production mode.');
  }
  mockElevenLabsClient = client;
}

/**
 * Reports whether ElevenLabs service configuration or active test mock is present.
 */
function isElevenLabsConfigured() {
  if (config.nodeEnv !== 'production' && mockElevenLabsClient) {
    return true;
  }
  return Boolean(config.elevenLabsApiKey && config.elevenLabsApiKey.trim());
}

/**
 * Translates provider HTTP responses to safe application errors.
 */
async function handleProviderHttpError(response, serviceName) {
  let errorDetail = '';
  try {
    const errorJson = await response.json();
    errorDetail = errorJson.detail?.message || errorJson.message || JSON.stringify(errorJson);
  } catch {
    errorDetail = response.statusText;
  }

  if (response.status === 401 || response.status === 403) {
    const err = new Error(`${serviceName} authentication failed with ElevenLabs provider.`);
    err.statusCode = 503;
    err.code = 'ELEVENLABS_AUTH_ERROR';
    throw err;
  }

  if (response.status === 429) {
    const err = new Error('ElevenLabs API quota exceeded or rate-limited. Please retry shortly.');
    err.statusCode = 429;
    err.code = 'ELEVENLABS_RATE_LIMITED';
    throw err;
  }

  if (response.status === 400) {
    const err = new Error(`Invalid request to ElevenLabs ${serviceName}: ${errorDetail}`);
    err.statusCode = 400;
    err.code = 'ELEVENLABS_BAD_REQUEST';
    throw err;
  }

  const err = new Error(`ElevenLabs ${serviceName} provider returned status ${response.status}: ${errorDetail}`);
  err.statusCode = 502;
  err.code = 'VOICE_PROVIDER_ERROR';
  throw err;
}

/**
 * Transcribes audio buffer using ElevenLabs Scribe STT.
 * Does not write any audio to disk.
 */
async function transcribeAudio({ audioBuffer, mimeType = 'audio/m4a', language = 'en' }) {
  if (!audioBuffer || !Buffer.isBuffer(audioBuffer) || audioBuffer.length === 0) {
    const err = new Error('Missing or empty audio data.');
    err.statusCode = 400;
    err.code = 'MISSING_AUDIO';
    throw err;
  }

  if (audioBuffer.length > config.voiceMaxAudioSizeBytes) {
    const err = new Error(`Audio upload exceeds maximum allowed size of ${Math.round(config.voiceMaxAudioSizeBytes / 1024 / 1024)} MB.`);
    err.statusCode = 400;
    err.code = 'AUDIO_TOO_LARGE';
    throw err;
  }

  // 1. Injected test provider
  if (mockElevenLabsClient) {
    if (typeof mockElevenLabsClient.transcribe === 'function') {
      return await mockElevenLabsClient.transcribe({ audioBuffer, mimeType, language });
    }
    throw new Error('Mock ElevenLabs client does not implement transcribe().');
  }

  // 2. Real provider verification
  if (!config.elevenLabsApiKey) {
    const err = new Error('ElevenLabs API key is not configured. Please set ELEVENLABS_API_KEY in backend/.env');
    err.statusCode = 503;
    err.code = 'ELEVENLABS_KEY_MISSING';
    throw err;
  }

  const modelId = config.elevenLabsSttModel || 'scribe_v2';
  const timeoutMs = config.voiceRequestTimeoutMs;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const formData = new FormData();
    const extension = mimeType.includes('wav') ? 'wav' : (mimeType.includes('mp3') || mimeType.includes('mpeg')) ? 'mp3' : 'm4a';
    const audioBlob = new Blob([audioBuffer], { type: mimeType });
    formData.append('file', audioBlob, `audio.${extension}`);
    formData.append('model_id', modelId);
    if (language) {
      formData.append('language_code', language);
    }

    const response = await fetch('https://api.elevenlabs.io/v1/speech-to-text', {
      method: 'POST',
      headers: {
        'xi-api-key': config.elevenLabsApiKey,
      },
      body: formData,
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      return await handleProviderHttpError(response, 'Speech-to-text');
    }

    const data = await response.json();
    const rawTranscript = (data.text || '').trim();
    if (!rawTranscript) {
      const emptyErr = new Error('No speech could be detected in the provided audio.');
      emptyErr.statusCode = 400;
      emptyErr.code = 'NO_SPEECH_DETECTED';
      throw emptyErr;
    }

    return {
      success: true,
      transcript: rawTranscript,
      language: data.language_code || language,
      model: modelId,
    };
  } catch (err) {
    clearTimeout(timeoutId);
    if (err.name === 'AbortError' || err.code === 20) {
      const timeoutErr = new Error(`ElevenLabs STT request timed out after ${timeoutMs}ms.`);
      timeoutErr.statusCode = 504;
      timeoutErr.code = 'VOICE_TIMEOUT';
      throw timeoutErr;
    }
    if (err.statusCode) throw err;

    const wrapErr = new Error(`ElevenLabs speech-to-text failed: ${err.message}`);
    wrapErr.statusCode = 502;
    wrapErr.code = 'VOICE_PROVIDER_ERROR';
    throw wrapErr;
  }
}

/**
 * Synthesizes short text into spoken audio using ElevenLabs TTS.
 * Does not write any audio to disk.
 */
async function synthesizeSpeech({ text, voiceId, language = 'en' }) {
  if (!text || typeof text !== 'string' || !text.trim()) {
    const err = new Error('Text is required for speech synthesis.');
    err.statusCode = 400;
    err.code = 'MISSING_TEXT';
    throw err;
  }

  const trimmedText = text.trim();
  if (trimmedText.length > config.voiceMaxTextLength) {
    const err = new Error(`Text exceeds maximum allowed length of ${config.voiceMaxTextLength} characters.`);
    err.statusCode = 400;
    err.code = 'TEXT_TOO_LONG';
    throw err;
  }

  // 1. Injected test provider
  if (mockElevenLabsClient) {
    if (typeof mockElevenLabsClient.synthesize === 'function') {
      return await mockElevenLabsClient.synthesize({ text: trimmedText, voiceId, language });
    }
    throw new Error('Mock ElevenLabs client does not implement synthesize().');
  }

  // 2. Real provider verification
  if (!config.elevenLabsApiKey) {
    const err = new Error('ElevenLabs API key is not configured. Please set ELEVENLABS_API_KEY in backend/.env');
    err.statusCode = 503;
    err.code = 'ELEVENLABS_KEY_MISSING';
    throw err;
  }

  const targetVoiceId = voiceId || config.elevenLabsVoiceId || '21m00Tcm4TlvDq8ikWAM';
  const modelId = config.elevenLabsTtsModel || 'eleven_flash_v2_5';
  const timeoutMs = config.voiceRequestTimeoutMs;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const url = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(targetVoiceId)}?output_format=mp3_44100_128`;
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'xi-api-key': config.elevenLabsApiKey,
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg',
      },
      body: JSON.stringify({
        text: trimmedText,
        model_id: modelId,
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
        },
      }),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      return await handleProviderHttpError(response, 'Text-to-speech');
    }

    const arrayBuffer = await response.arrayBuffer();
    const audioBuffer = Buffer.from(arrayBuffer);

    if (audioBuffer.length === 0) {
      const err = new Error('Received empty audio from ElevenLabs TTS API.');
      err.statusCode = 502;
      err.code = 'VOICE_EMPTY_RESPONSE';
      throw err;
    }

    return {
      audioBuffer,
      contentType: 'audio/mpeg',
      model: modelId,
      voiceId: targetVoiceId,
    };
  } catch (err) {
    clearTimeout(timeoutId);
    if (err.name === 'AbortError' || err.code === 20) {
      const timeoutErr = new Error(`ElevenLabs TTS request timed out after ${timeoutMs}ms.`);
      timeoutErr.statusCode = 504;
      timeoutErr.code = 'VOICE_TIMEOUT';
      throw timeoutErr;
    }
    if (err.statusCode) throw err;

    const wrapErr = new Error(`ElevenLabs text-to-speech failed: ${err.message}`);
    wrapErr.statusCode = 502;
    wrapErr.code = 'VOICE_PROVIDER_ERROR';
    throw wrapErr;
  }
}

module.exports = {
  transcribeAudio,
  synthesizeSpeech,
  setMockElevenLabsClient,
  isElevenLabsConfigured,
};
