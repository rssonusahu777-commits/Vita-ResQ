const express = require('express');
const { authenticateToken } = require('../middleware/auth');
const { rateLimiter } = require('../middleware/rateLimit');
const {
  loadAuthoritativeEmergency,
  validateEmergencyAccess,
  sanitizeAuthoritativeEmergencyContext,
} = require('../services/emergencyContextService');
const {
  generateAssistantResponse,
  generateEmergencyBrief,
} = require('../services/geminiService');

const router = express.Router();

// Apply auth and rate limiting to all AI endpoints
router.use(authenticateToken);
router.use(rateLimiter);

/**
 * POST /api/ai/assistant
 * Answers read-only situational questions based strictly on authoritative Firestore facts.
 * Client-supplied emergency status or responder data is completely ignored.
 */
router.post('/assistant', async (req, res) => {
  try {
    const { emergencyId, query, language = 'en', clientMetrics } = req.body;

    // Validate query length
    if (query && typeof query === 'string' && query.length > 500) {
      return res.status(400).json({
        success: false,
        error: 'QUERY_TOO_LONG',
        message: 'Question exceeds maximum allowed length of 500 characters.',
      });
    }

    // Validate supported languages
    const sanitizedLang = language === 'hi' ? 'hi' : 'en';

    let sanitizedContext = null;

    if (emergencyId) {
      // 1. Authoritatively load emergency from trusted server-side Firestore
      const authoritativeRecord = await loadAuthoritativeEmergency(emergencyId);

      // 2. Authorize access: compare verified UID from token against the authoritative record
      const isAuthorized = validateEmergencyAccess(req.user.uid, authoritativeRecord);
      if (!isAuthorized) {
        return res.status(403).json({
          success: false,
          error: 'FORBIDDEN',
          message: 'You are not authorized to access or query this emergency session.',
        });
      }

      // 3. Build minimal sanitized context without coordinates or personal data
      sanitizedContext = sanitizeAuthoritativeEmergencyContext(
        authoritativeRecord,
        req.user.uid,
        clientMetrics
      );
    } else {
      // General inquiry without specific active emergency session
      sanitizedContext = {
        emergencyType: 'GENERAL_INQUIRY',
        status: 'IDLE',
        callerPerspective: 'CITIZEN',
        elapsedMinutes: 0,
        responderCount: 0,
        hasAssignedResponder: false,
        assignedResponderRole: 'NONE',
        coarseDistance: 'N/A',
        roadRouteAvailable: false,
        etaText: 'N/A',
      };
    }

    const result = await generateAssistantResponse({
      sanitizedContext,
      userQuery: query,
      language: sanitizedLang,
    });

    return res.status(200).json(result);
  } catch (err) {
    const status = err.statusCode || 500;
    return res.status(status).json({
      success: false,
      error: err.code || 'AI_ERROR',
      message: err.message || 'An unexpected error occurred while communicating with the AI service.',
    });
  }
});

/**
 * POST /api/ai/emergency-brief
 * Generates a concise, calming situation brief based strictly on authoritative Firestore facts.
 */
router.post('/emergency-brief', async (req, res) => {
  try {
    const { emergencyId, language = 'en', clientMetrics } = req.body;

    if (!emergencyId || typeof emergencyId !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'MISSING_EMERGENCY_ID',
        message: 'Valid emergency ID is required to generate a situation brief.',
      });
    }

    // 1. Authoritatively load emergency from trusted server-side Firestore
    const authoritativeRecord = await loadAuthoritativeEmergency(emergencyId);

    // 2. Authorize access: compare verified UID from token against the authoritative record
    const isAuthorized = validateEmergencyAccess(req.user.uid, authoritativeRecord);
    if (!isAuthorized) {
      return res.status(403).json({
        success: false,
        error: 'FORBIDDEN',
        message: 'You are not authorized to access or brief this emergency session.',
      });
    }

    const sanitizedLang = language === 'hi' ? 'hi' : 'en';

    // 3. Build minimal sanitized context without coordinates or personal data
    const sanitizedContext = sanitizeAuthoritativeEmergencyContext(
      authoritativeRecord,
      req.user.uid,
      clientMetrics
    );

    const result = await generateEmergencyBrief({
      sanitizedContext,
      language: sanitizedLang,
    });

    return res.status(200).json(result);
  } catch (err) {
    const status = err.statusCode || 500;
    return res.status(status).json({
      success: false,
      error: err.code || 'AI_ERROR',
      message: err.message || 'An unexpected error occurred while generating the situation brief.',
    });
  }
});

module.exports = router;
