const express = require('express');
const config = require('../config');
const { isFirebaseConfigured } = require('../middleware/auth');
const { isEmergencyLookupConfigured } = require('../services/emergencyContextService');
const { isElevenLabsConfigured } = require('../services/elevenLabsService');
const { isTimescaleConfigured } = require('../services/timescaleDbService');

const router = express.Router();

/**
 * GET /api/health
 * Reports operational readiness states without exposing secrets, paths, or credentials.
 * Distinguishes process health from dependency configuration.
 */
router.get('/health', (req, res) => {
  const firebaseAuthConfigured = isFirebaseConfigured();
  const emergencyLookupConfigured = isEmergencyLookupConfigured();
  const geminiModelConfigured = Boolean(config.geminiApiKey);
  const elevenLabsConfigured = isElevenLabsConfigured();
  const timescaleDbConfigured = isTimescaleConfigured();

  res.status(200).json({
    status: 'ok',
    service: 'vita-resq-ai-backend',
    version: '1.0.0',
    model: config.geminiModel,
    readiness: {
      processRunning: true,
      firebaseAuthConfigured,
      emergencyLookupConfigured,
      geminiModelConfigured,
      elevenLabsConfigured,
      timescaleDbConfigured,
    },
    voice: {
      sttModel: config.elevenLabsSttModel,
      ttsModel: config.elevenLabsTtsModel,
      rateLimitWindowMs: config.voiceRateLimitWindowMs,
      rateLimitMaxRequests: config.voiceRateLimitMaxRequests,
      maxAudioSizeBytes: config.voiceMaxAudioSizeBytes,
      maxTextLength: config.voiceMaxTextLength,
    },
    rateLimitWindowMs: config.rateLimitWindowMs,
    rateLimitMaxRequests: config.rateLimitMaxRequests,
    timestamp: new Date().toISOString(),
  });
});

module.exports = router;
