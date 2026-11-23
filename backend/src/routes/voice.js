const express = require('express');
const multer = require('multer');
const config = require('../config');
const { authenticateToken } = require('../middleware/auth');
const { voiceRateLimiter } = require('../middleware/rateLimit');
const {
  loadAuthoritativeEmergency,
  validateEmergencyAccess,
} = require('../services/emergencyContextService');
const {
  transcribeAudio,
  synthesizeSpeech,
} = require('../services/elevenLabsService');

const router = express.Router();

// Memory-only storage: audio files are NEVER written to disk
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: config.voiceMaxAudioSizeBytes, // 2 MB limit
  },
});

// Supported audio mime-types
const ALLOWED_MIME_PREFIXES = ['audio/'];
const ALLOWED_MIME_TYPES = ['application/octet-stream'];

function isSupportedAudioMime(mimeType) {
  if (!mimeType) return true; // Default fallback to audio/m4a
  if (ALLOWED_MIME_TYPES.includes(mimeType)) return true;
  return ALLOWED_MIME_PREFIXES.some(prefix => mimeType.startsWith(prefix));
}

// Protect all voice endpoints with authentication and strict rate limiting
router.use(authenticateToken);
router.use(voiceRateLimiter);

/**
 * POST /api/voice/transcribe
 * Accepts bounded audio upload and transcribes it via ElevenLabs STT.
 * Requires caller to be an active participant in the authoritative emergency record.
 * Raw audio is processed in memory and never persisted.
 */
router.post('/transcribe', (req, res, next) => {
  upload.single('audio')(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({
          success: false,
          error: 'AUDIO_TOO_LARGE',
          message: `Audio upload exceeds maximum allowed size of ${Math.round(config.voiceMaxAudioSizeBytes / 1024 / 1024)} MB.`,
        });
      }
      return res.status(400).json({
        success: false,
        error: 'INVALID_AUDIO_UPLOAD',
        message: err.message,
      });
    } else if (err) {
      return res.status(400).json({
        success: false,
        error: 'AUDIO_UPLOAD_ERROR',
        message: err.message,
      });
    }
    next();
  });
}, async (req, res) => {
  try {
    const { emergencyId, language = 'en' } = req.body;

    // 1. Validate emergencyId
    if (!emergencyId || typeof emergencyId !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'MISSING_EMERGENCY_ID',
        message: 'Valid emergency ID is required for emergency voice transcription.',
      });
    }

    // 2. Authoritatively verify emergency record and caller participation
    const authoritativeRecord = await loadAuthoritativeEmergency(emergencyId);
    const isAuthorized = validateEmergencyAccess(req.user.uid, authoritativeRecord);
    if (!isAuthorized) {
      return res.status(403).json({
        success: false,
        error: 'FORBIDDEN',
        message: 'You are not authorized to submit audio for this emergency session.',
      });
    }

    // 3. Validate audio file
    if (!req.file || !req.file.buffer || req.file.buffer.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'MISSING_AUDIO',
        message: 'Audio file is required in multipart field "audio".',
      });
    }

    if (!isSupportedAudioMime(req.file.mimetype)) {
      return res.status(400).json({
        success: false,
        error: 'UNSUPPORTED_AUDIO_FORMAT',
        message: `Unsupported audio format "${req.file.mimetype}". Expected an audio recording.`,
      });
    }

    // 4. Forward audio buffer through ElevenLabs STT
    const result = await transcribeAudio({
      audioBuffer: req.file.buffer,
      mimeType: req.file.mimetype,
      language,
    });

    // 5. Explicitly nullify buffer to guarantee memory reclamation
    req.file.buffer = null;

    return res.status(200).json({
      success: true,
      transcript: result.transcript,
      language: result.language,
      model: result.model,
    });
  } catch (err) {
    if (req.file) {
      req.file.buffer = null;
    }
    const status = err.statusCode || 500;
    return res.status(status).json({
      success: false,
      error: err.code || 'VOICE_ERROR',
      message: err.message || 'An unexpected error occurred during voice transcription.',
    });
  }
});

/**
 * POST /api/voice/speak
 * Synthesizes short emergency text to speech via ElevenLabs TTS.
 * Requires caller to be an active participant in the authoritative emergency record.
 * Returns binary audio/mpeg stream. Audio is never persisted.
 */
router.post('/speak', async (req, res) => {
  try {
    const { emergencyId, text, language = 'en', voiceId } = req.body;

    // 1. Validate emergencyId
    if (!emergencyId || typeof emergencyId !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'MISSING_EMERGENCY_ID',
        message: 'Valid emergency ID is required for emergency speech synthesis.',
      });
    }

    // 2. Authoritatively verify emergency record and caller participation
    const authoritativeRecord = await loadAuthoritativeEmergency(emergencyId);
    const isAuthorized = validateEmergencyAccess(req.user.uid, authoritativeRecord);
    if (!isAuthorized) {
      return res.status(403).json({
        success: false,
        error: 'FORBIDDEN',
        message: 'You are not authorized to synthesize speech for this emergency session.',
      });
    }

    // 3. Validate text length and content
    if (!text || typeof text !== 'string' || !text.trim()) {
      return res.status(400).json({
        success: false,
        error: 'MISSING_TEXT',
        message: 'Text is required for speech synthesis.',
      });
    }

    if (text.trim().length > config.voiceMaxTextLength) {
      return res.status(400).json({
        success: false,
        error: 'TEXT_TOO_LONG',
        message: `Text exceeds maximum allowed length of ${config.voiceMaxTextLength} characters.`,
      });
    }

    // 4. Synthesize speech via ElevenLabs TTS
    const result = await synthesizeSpeech({
      text,
      voiceId,
      language,
    });

    // 5. Send binary audio stream with appropriate headers
    res.set('Content-Type', result.contentType || 'audio/mpeg');
    res.set('Content-Length', String(result.audioBuffer.length));
    res.set('X-Voice-Model', result.model);
    return res.status(200).send(result.audioBuffer);
  } catch (err) {
    const status = err.statusCode || 500;
    return res.status(status).json({
      success: false,
      error: err.code || 'VOICE_ERROR',
      message: err.message || 'An unexpected error occurred during speech synthesis.',
    });
  }
});

module.exports = router;
