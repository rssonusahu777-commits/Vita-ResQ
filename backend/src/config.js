const path = require('path');
const dotenv = require('dotenv');

// Load environment variables from backend/.env if present
dotenv.config({ path: path.resolve(__dirname, '../.env') });

const config = {
  port: parseInt(process.env.PORT, 10) || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',
  geminiApiKey: process.env.GEMINI_API_KEY || '',
  geminiModel: process.env.GEMINI_MODEL || 'gemini-3.8-flash',
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || 'vita-resq',
  googleApplicationCredentials: process.env.GOOGLE_APPLICATION_CREDENTIALS || '',
  rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS, 10) || 60000,
  rateLimitMaxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS, 10) || 10,
  aiRequestTimeoutMs: parseInt(process.env.AI_REQUEST_TIMEOUT_MS, 10) || 10000,

  // ElevenLabs Voice Assistant configuration
  elevenLabsApiKey: process.env.ELEVENLABS_API_KEY || '',
  elevenLabsVoiceId: process.env.ELEVENLABS_VOICE_ID || '21m00Tcm4TlvDq8ikWAM',
  elevenLabsSttModel: process.env.ELEVENLABS_STT_MODEL || 'scribe_v2',
  elevenLabsTtsModel: process.env.ELEVENLABS_TTS_MODEL || 'eleven_flash_v2_5',
  voiceRateLimitWindowMs: parseInt(process.env.VOICE_RATE_LIMIT_WINDOW_MS, 10) || 60000,
  voiceRateLimitMaxRequests: parseInt(process.env.VOICE_RATE_LIMIT_MAX_REQUESTS, 10) || 5,
  voiceRequestTimeoutMs: parseInt(process.env.VOICE_REQUEST_TIMEOUT_MS, 10) || 15000,
  voiceMaxAudioSizeBytes: parseInt(process.env.VOICE_MAX_AUDIO_SIZE_BYTES, 10) || 2 * 1024 * 1024,
  voiceMaxTextLength: parseInt(process.env.VOICE_MAX_TEXT_LENGTH, 10) || 500,

  // TimescaleDB / Tiger Data Analytics configuration
  timescaleDatabaseUrl: process.env.TIMESCALE_DATABASE_URL || '',
  analyticsMaxBatchSize: parseInt(process.env.ANALYTICS_MAX_BATCH_SIZE, 10) || 50,
  analyticsRateLimitWindowMs: parseInt(process.env.ANALYTICS_RATE_LIMIT_WINDOW_MS, 10) || 60000,
  analyticsRateLimitMaxRequests: parseInt(process.env.ANALYTICS_RATE_LIMIT_MAX_REQUESTS, 10) || 20,
  adminUids: (process.env.ADMIN_UIDS || '').split(',').map((s) => s.trim()).filter(Boolean),
};

module.exports = config;
