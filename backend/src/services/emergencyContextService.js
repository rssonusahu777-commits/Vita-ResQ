const admin = require('firebase-admin');
const config = require('../config');
const { initFirebaseAdmin } = require('../middleware/auth');

/**
 * Service to load authoritative emergency records from Firestore,
 * verify participant authorization, and sanitize data into a minimal,
 * privacy-preserving context for the Gemini AI Assistant.
 *
 * Strict Privacy Rules:
 * - NEVER send real victim names, phone numbers, exact coordinates, addresses,
 *   authentication tokens, blood groups, or raw medical descriptions to Gemini.
 * - Exact coordinates are completely stripped.
 * - Distances are formatted into coarse, privacy-preserving buckets.
 */

let mockEmergencyLoader = null;

/**
 * Allows automated tests to inject an authoritative emergency loader.
 * Strictly forbidden in production.
 */
function setEmergencyLoaderForTesting(loader) {
  if (config.nodeEnv === 'production') {
    throw new Error('Test emergency loader cannot be set in production mode.');
  }
  mockEmergencyLoader = loader;
}

/**
 * Reports whether authoritative emergency lookup is configured.
 */
function isEmergencyLookupConfigured() {
  if (config.nodeEnv !== 'production' && mockEmergencyLoader) {
    return true;
  }
  return initFirebaseAdmin();
}

/**
 * Loads the authoritative emergency record from Firestore or injected test loader.
 * Fails closed if Firestore is unconfigured or document does not exist.
 */
async function loadAuthoritativeEmergency(emergencyId) {
  if (!emergencyId || typeof emergencyId !== 'string') {
    const err = new Error('Valid emergency ID is required.');
    err.statusCode = 400;
    err.code = 'INVALID_EMERGENCY_ID';
    throw err;
  }

  // 1. Check test loader in non-production environments
  if (config.nodeEnv !== 'production' && mockEmergencyLoader) {
    const record = await mockEmergencyLoader(emergencyId);
    if (!record) {
      const err = new Error(`Emergency '${emergencyId}' not found in authoritative records.`);
      err.statusCode = 404;
      err.code = 'EMERGENCY_NOT_FOUND';
      throw err;
    }
    return record;
  }

  // 2. Production or standard environment lookup from Firestore
  const isReady = initFirebaseAdmin();
  if (!isReady) {
    const err = new Error('Authoritative emergency database is unconfigured. Set GOOGLE_APPLICATION_CREDENTIALS to configure server-side Firestore.');
    err.statusCode = 503;
    err.code = 'FIRESTORE_UNCONFIGURED';
    throw err;
  }

  try {
    const docSnap = await admin.firestore().collection('emergencies').doc(emergencyId).get();
    if (!docSnap.exists) {
      const err = new Error(`Emergency '${emergencyId}' not found.`);
      err.statusCode = 404;
      err.code = 'EMERGENCY_NOT_FOUND';
      throw err;
    }
    return { id: docSnap.id, ...docSnap.data() };
  } catch (err) {
    if (err.statusCode) throw err;
    const dbErr = new Error('Failed to query authoritative emergency record: ' + err.message);
    dbErr.statusCode = 503;
    dbErr.code = 'FIRESTORE_ERROR';
    throw dbErr;
  }
}

/**
 * Validates whether the authenticated caller is authorized to access the emergency context.
 * Compares verified caller UID against the actual authoritative record.
 */
function validateEmergencyAccess(userUid, emergency) {
  if (!emergency || !userUid) return false;

  // Caller is the victim
  if (emergency.victimId && emergency.victimId === userUid) {
    return true;
  }

  // Caller is the designated helperId
  if (emergency.helperId && emergency.helperId === userUid) {
    return true;
  }

  // Caller is a registered responder
  if (emergency.responders && typeof emergency.responders === 'object') {
    if (Object.prototype.hasOwnProperty.call(emergency.responders, userUid)) {
      return true;
    }
  }

  return false;
}

/**
 * Format meters into coarse, privacy-preserving distance strings
 */
function formatCoarseDistance(meters) {
  if (meters === null || meters === undefined || isNaN(meters) || meters < 0) {
    return 'Distance temporarily unavailable (awaiting GPS acquisition)';
  }
  if (meters === 0 || meters < 0.5) {
    return 'At scene (0 meters)';
  }
  if (meters < 50) {
    return 'Immediate proximity (< 50 meters)';
  }
  if (meters < 1000) {
    // Round to nearest 50m to avoid pinpointing exact coordinates
    const rounded = Math.round(meters / 50) * 50;
    return `Approximately ${rounded} meters`;
  }
  // Coarse kilometer representation
  const km = (meters / 1000).toFixed(1);
  return `Approximately ${km} km`;
}

/**
 * Converts trusted authoritative emergency data into a safe, coarse, privacy-compliant snapshot.
 * Treats client-supplied metrics as untrusted and validates freshness before using.
 */
function sanitizeAuthoritativeEmergencyContext(authoritativeEmergency, callerUid, clientMetrics = null) {
  if (!authoritativeEmergency) return null;

  const isCallerVictim = authoritativeEmergency.victimId === callerUid;
  const responderKeys = authoritativeEmergency.responders ? Object.keys(authoritativeEmergency.responders) : [];
  const responderCount = responderKeys.length;

  let assignedRole = 'NONE';
  let primaryDistance = null;
  let etaText = null;
  let isRoadRoute = false;

  if (authoritativeEmergency.helperId) {
    if (authoritativeEmergency.helperId === callerUid) {
      assignedRole = 'PRIMARY_RESPONDER';
    } else if (isCallerVictim) {
      assignedRole = 'ASSIGNED_HELPER';
    } else {
      assignedRole = 'STANDBY_RESPONDER';
    }

    // Check if client provided fresh, verified metrics (< 60s old)
    let clientMetricsValid = false;
    if (clientMetrics && clientMetrics.timestamp) {
      const metricTime = new Date(clientMetrics.timestamp).getTime();
      const isFresh = !isNaN(metricTime) && Math.abs(Date.now() - metricTime) <= 60000;
      if (isFresh && typeof clientMetrics.distanceMeters === 'number' && clientMetrics.distanceMeters >= 0) {
        primaryDistance = clientMetrics.distanceMeters;
        isRoadRoute = Boolean(clientMetrics.isRoadRoute);
        etaText = clientMetrics.etaText || (isRoadRoute ? 'Calculating road ETA...' : 'Road ETA unavailable (direct straight-line navigation)');
        clientMetricsValid = true;
      }
    }

    // Fall back to server-side stored helper data if client metrics were absent or stale
    if (!clientMetricsValid) {
      const helperData = authoritativeEmergency.responders ? authoritativeEmergency.responders[authoritativeEmergency.helperId] : null;
      if (helperData) {
        if (typeof helperData.distanceToVictim === 'number') {
          primaryDistance = helperData.distanceToVictim;
        }
        if (helperData.etaText) {
          etaText = helperData.etaText;
        }
        isRoadRoute = Boolean(helperData.isRoadRoute);
      }
    }
  } else if (!isCallerVictim && responderKeys.includes(callerUid)) {
    assignedRole = 'STANDBY_RESPONDER';
  }

  // Calculate coarse elapsed time from authoritative creation timestamp
  let elapsedMinutes = 0;
  const createdAtRaw = authoritativeEmergency.createdAt;
  if (createdAtRaw) {
    let createdTime;
    if (typeof createdAtRaw.toDate === 'function') {
      createdTime = createdAtRaw.toDate().getTime();
    } else {
      createdTime = new Date(createdAtRaw).getTime();
    }
    if (!isNaN(createdTime)) {
      elapsedMinutes = Math.max(0, Math.floor((Date.now() - createdTime) / 60000));
    }
  }

  // Construct coarse distance description
  let coarseDistanceStr;
  if (authoritativeEmergency.helperId) {
    coarseDistanceStr = formatCoarseDistance(primaryDistance);
  } else {
    coarseDistanceStr = 'N/A (No responder assigned yet)';
  }

  // Construct safe ETA description
  let finalEtaText = etaText;
  if (!finalEtaText) {
    if (authoritativeEmergency.helperId) {
      finalEtaText = isRoadRoute ? 'Calculating road ETA...' : 'Road ETA unavailable (direct straight-line navigation)';
    } else {
      finalEtaText = 'ETA unavailable (searching for nearby responders)';
    }
  }

  // Purely operational, coarse snapshot with all PII and raw coordinates stripped
  return {
    emergencyType: authoritativeEmergency.type || 'GENERAL',
    status: authoritativeEmergency.status || 'SEARCHING',
    callerPerspective: isCallerVictim ? 'VICTIM' : (assignedRole === 'PRIMARY_RESPONDER' ? 'PRIMARY' : 'STANDBY'),
    elapsedMinutes,
    responderCount,
    hasAssignedResponder: Boolean(authoritativeEmergency.helperId),
    assignedResponderRole: assignedRole,
    coarseDistance: coarseDistanceStr,
    roadRouteAvailable: isRoadRoute,
    etaText: finalEtaText,
    // Exact latitude, longitude, victim names, phone numbers, auth tokens, blood groups are NEVER returned.
  };
}

module.exports = {
  loadAuthoritativeEmergency,
  setEmergencyLoaderForTesting,
  isEmergencyLookupConfigured,
  validateEmergencyAccess,
  formatCoarseDistance,
  sanitizeAuthoritativeEmergencyContext,
};
