const express = require('express');
const config = require('../config');
const { authenticateToken } = require('../middleware/auth');
const { loadAuthoritativeEmergency, validateEmergencyAccess } = require('../services/emergencyContextService');
const { ingestEventBatch, isTimescaleConfigured } = require('../services/timescaleDbService');
const { getOperationalSummary } = require('../services/analyticsSummaryService');
const { generateAnalyticsInsights } = require('../services/geminiService');

const router = express.Router();

// In-memory per-user rate limiting store for analytics operations
const analyticsRateLimits = new Map();

/**
 * Middleware: Enforces per-user rate limits on analytics endpoints.
 */
function analyticsRateLimiter(req, res, next) {
  const userKey = (req.user && req.user.uid) || req.ip || 'anonymous';
  const now = Date.now();
  const windowMs = config.analyticsRateLimitWindowMs || 60000;
  const maxRequests = config.analyticsRateLimitMaxRequests || 20;

  let record = analyticsRateLimits.get(userKey);
  if (!record || now - record.windowStart >= windowMs) {
    record = { windowStart: now, count: 0 };
  }

  record.count += 1;
  analyticsRateLimits.set(userKey, record);

  if (record.count > maxRequests) {
    const retryAfter = Math.ceil((record.windowStart + windowMs - now) / 1000);
    res.setHeader('Retry-After', retryAfter.toString());
    return res.status(429).json({
      success: false,
      error: 'ANALYTICS_RATE_LIMITED',
      message: 'Too many analytics requests. Please back off before retrying.',
      retryAfterSeconds: retryAfter,
    });
  }

  next();
}

/**
 * Middleware: Requires administrator privileges (Firebase custom claim or admin UID).
 */
function requireAdminAuth(req, res, next) {
  if (!req.user || !req.user.uid) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      message: 'Authentication required.',
    });
  }

  const isAdminClaim = req.user.admin === true || req.user.role === 'admin';
  const isAdminUid = config.adminUids.includes(req.user.uid);

  if (!isAdminClaim && !isAdminUid) {
    return res.status(403).json({
      success: false,
      error: 'FORBIDDEN_NOT_ADMIN',
      message: 'Administrator privileges are required to access aggregate operational analytics.',
    });
  }

  next();
}

// Forbidden fields that violate privacy constraints
const FORBIDDEN_PRIVACY_KEYS = [
  'name', 'victimname', 'respondername', 'phone', 'phonenumber',
  'lat', 'latitude', 'lng', 'long', 'longitude', 'coords', 'coordinates',
  'address', 'email', 'token', 'medicalnotes', 'macaddress',
];

/**
 * Validates that an event payload contains no sensitive PII or forbidden fields.
 */
function containsPrivacyViolations(obj) {
  if (!obj || typeof obj !== 'object') return false;
  for (const key of Object.keys(obj)) {
    const lowerKey = key.toLowerCase();
    if (FORBIDDEN_PRIVACY_KEYS.includes(lowerKey)) {
      return true;
    }
    if (typeof obj[key] === 'object' && obj[key] !== null) {
      if (containsPrivacyViolations(obj[key])) return true;
    }
  }
  return false;
}

/**
 * POST /api/analytics/events/batch
 * Ingests an authenticated batch of operational events into TimescaleDB.
 */
router.post('/events/batch', authenticateToken, analyticsRateLimiter, async (req, res, next) => {
  try {
    const { events } = req.body;

    if (!Array.isArray(events) || events.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'INVALID_BATCH',
        message: 'Request body must contain a non-empty "events" array.',
      });
    }

    const maxBatch = config.analyticsMaxBatchSize || 50;
    if (events.length > maxBatch) {
      return res.status(400).json({
        success: false,
        error: 'BATCH_SIZE_EXCEEDED',
        message: `Maximum batch size of ${maxBatch} events exceeded. Received ${events.length}.`,
      });
    }

    // Check database configuration early
    if (!isTimescaleConfigured()) {
      return res.status(503).json({
        success: false,
        error: 'ANALYTICS_DB_UNAVAILABLE',
        message: 'TimescaleDB / Tiger Data Analytics service is unconfigured or unavailable. Retrying later.',
      });
    }

    const now = Date.now();
    const maxFutureSkewMs = 60000; // 60 seconds clock skew tolerance
    const maxHistoricalAgeMs = 7 * 24 * 60 * 60 * 1000; // 7 days historical tolerance for offline sync

    const checkedEmergencies = new Map();

    for (let i = 0; i < events.length; i++) {
      const event = events[i];

      // 1. Validate required fields
      if (!event.eventId || typeof event.eventId !== 'string' || event.eventId.length > 64) {
        return res.status(400).json({
          success: false,
          error: 'INVALID_EVENT_ID',
          message: `Event at index ${i} has an invalid or missing 'eventId'.`,
        });
      }

      if (!event.emergencyId || typeof event.emergencyId !== 'string' || event.emergencyId.length > 64) {
        return res.status(400).json({
          success: false,
          error: 'INVALID_EMERGENCY_ID',
          message: `Event at index ${i} has an invalid or missing 'emergencyId'.`,
        });
      }

      // 2. Validate timestamp
      if (!event.timestamp || typeof event.timestamp !== 'string') {
        return res.status(400).json({
          success: false,
          error: 'INVALID_TIMESTAMP',
          message: `Event '${event.eventId}' has a missing or invalid ISO timestamp.`,
        });
      }

      const eventTime = new Date(event.timestamp).getTime();
      if (isNaN(eventTime)) {
        return res.status(400).json({
          success: false,
          error: 'INVALID_TIMESTAMP',
          message: `Event '${event.eventId}' has an unparseable timestamp: ${event.timestamp}`,
        });
      }

      if (eventTime > now + maxFutureSkewMs) {
        return res.status(400).json({
          success: false,
          error: 'FUTURE_TIMESTAMP_REJECTED',
          message: `Event '${event.eventId}' has a future timestamp (${event.timestamp}).`,
        });
      }

      if (eventTime < now - maxHistoricalAgeMs) {
        return res.status(400).json({
          success: false,
          error: 'EXPIRED_TIMESTAMP',
          message: `Event '${event.eventId}' timestamp exceeds maximum 7-day retention window.`,
        });
      }

      // 3. Strict privacy validation
      if (containsPrivacyViolations(event)) {
        return res.status(400).json({
          success: false,
          error: 'PRIVACY_VIOLATION',
          message: `Event '${event.eventId}' contains forbidden personal or exact coordinate fields.`,
        });
      }

      // 4. Participant verification against authoritative Firestore emergency record
      if (!checkedEmergencies.has(event.emergencyId)) {
        const emergency = await loadAuthoritativeEmergency(event.emergencyId);
        const isAuthorized = validateEmergencyAccess(req.user.uid, emergency);
        if (!isAuthorized) {
          return res.status(403).json({
            success: false,
            error: 'FORBIDDEN',
            message: `User '${req.user.uid}' is not an authorized participant in emergency '${event.emergencyId}'.`,
          });
        }
        checkedEmergencies.set(event.emergencyId, true);
      }
    }

    // 5. Ingest events atomically in TimescaleDB
    const result = await ingestEventBatch(events);

    res.status(200).json({
      success: true,
      accepted: result.accepted,
      duplicates: result.duplicates,
      conflicts: result.conflicts,
      acceptedCount: result.accepted.length,
      duplicateCount: result.duplicates.length,
    });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/analytics/summary
 * Returns aggregate operational performance metrics for authorized administrators.
 */
router.get('/summary', authenticateToken, requireAdminAuth, analyticsRateLimiter, async (req, res, next) => {
  try {
    if (!isTimescaleConfigured()) {
      return res.status(503).json({
        success: false,
        error: 'ANALYTICS_DB_UNAVAILABLE',
        message: 'TimescaleDB / Tiger Data Analytics service is unconfigured or unavailable.',
      });
    }

    const { from, to, emergencyType } = req.query;
    const summary = await getOperationalSummary({
      fromTime: from,
      toTime: to,
      emergencyType,
    });

    res.status(200).json({
      success: true,
      summary,
    });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/analytics/insights
 * Generates an objective, AI-assisted operational interpretation of verified aggregate metrics for administrators.
 *
 * Strict Rules:
 * - Requires administrator authorization.
 * - Passes only verified aggregate statistics to Gemini (no PII, no coordinates, no SQL access).
 * - Never mutates database or changes dispatch configuration.
 * - Rate limited.
 */
router.post('/insights', authenticateToken, requireAdminAuth, analyticsRateLimiter, async (req, res, next) => {
  try {
    if (!isTimescaleConfigured()) {
      return res.status(503).json({
        success: false,
        error: 'ANALYTICS_DB_UNAVAILABLE',
        message: 'TimescaleDB / Tiger Data Analytics service is unconfigured or unavailable.',
      });
    }

    const { from, to, emergencyType, focusArea, language } = req.body || {};
    const summary = await getOperationalSummary({
      fromTime: from,
      toTime: to,
      emergencyType,
    });

    if (!summary.sufficientData) {
      return res.status(200).json({
        success: true,
        available: false,
        reason: 'INSUFFICIENT_DATA',
        message: 'Insufficient historical analytics data recorded to date to generate reliable AI insights.',
        insights: null,
      });
    }

    const result = await generateAnalyticsInsights({
      sanitizedSummary: summary,
      focusArea: focusArea || 'general',
      language: language || 'en',
    });

    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
