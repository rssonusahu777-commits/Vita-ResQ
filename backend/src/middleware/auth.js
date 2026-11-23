const fs = require('fs');
const admin = require('firebase-admin');
const config = require('../config');

let firebaseInitialized = false;
let customTokenVerifier = null;
let forceUnconfiguredForTesting = false;

/**
 * Initializes the Firebase Admin SDK using secure local credentials or local emulators.
 * Fails safely and returns false if credentials or emulators are not configured.
 */
function initFirebaseAdmin() {
  if (config.nodeEnv !== 'production' && forceUnconfiguredForTesting) {
    return false;
  }
  if (firebaseInitialized && admin.apps.length > 0) return true;
  try {
    if (admin.apps.length === 0) {
      // 0. Safe emulator-only initialization for local development and testing
      const authEmulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
      const firestoreEmulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
      const effectiveProjectId = process.env.FIREBASE_PROJECT_ID || process.env.GCLOUD_PROJECT || config.firebaseProjectId;
      const isDemoProject = typeof effectiveProjectId === 'string' && effectiveProjectId.startsWith('demo-');
      const isLocalHost = (host) => typeof host === 'string' && (host.startsWith('127.0.0.1:') || host.startsWith('localhost:'));

      if (
        config.nodeEnv !== 'production' &&
        isDemoProject &&
        isLocalHost(authEmulatorHost) &&
        isLocalHost(firestoreEmulatorHost)
      ) {
        admin.initializeApp({
          projectId: effectiveProjectId,
        });
        firebaseInitialized = true;
        return true;
      }

      // 1. Explicit service account JSON path from config / .env
      if (config.googleApplicationCredentials && fs.existsSync(config.googleApplicationCredentials)) {
        admin.initializeApp({
          credential: admin.credential.cert(config.googleApplicationCredentials),
          projectId: config.firebaseProjectId,
        });
        firebaseInitialized = true;
        return true;
      }

      // 2. Standard Google Application Default Credentials
      if (process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
        admin.initializeApp({
          credential: admin.credential.applicationDefault(),
          projectId: config.firebaseProjectId,
        });
        firebaseInitialized = true;
        return true;
      }

      // No trusted local credential file found — fail closed
      return false;
    }
    firebaseInitialized = true;
    return true;
  } catch (err) {
    return false;
  }
}

/**
 * Allows automated tests to reset the Firebase Admin instance in test isolation.
 * Strictly forbidden in production environments.
 */
function resetFirebaseAdminForTesting() {
  if (config.nodeEnv === 'production') {
    throw new Error('Test Firebase reset cannot be called in production mode.');
  }
  firebaseInitialized = false;
  forceUnconfiguredForTesting = false;
  customTokenVerifier = null;
  if (admin.apps.length > 0) {
    return Promise.all(admin.apps.map((app) => app.delete()));
  }
  return Promise.resolve();
}

/**
 * Reports whether Firebase authentication and admin services are configured.
 */
function isFirebaseConfigured() {
  if (config.nodeEnv !== 'production' && customTokenVerifier) {
    return true;
  }
  return initFirebaseAdmin();
}

/**
 * Allows automated tests to simulate unconfigured Firebase credentials.
 * Strictly forbidden in production environments.
 */
function setForceUnconfiguredForTesting(val) {
  if (config.nodeEnv === 'production') {
    throw new Error('Test unconfigured override cannot be set in production mode.');
  }
  forceUnconfiguredForTesting = Boolean(val);
}

/**
 * Allows automated tests to inject a mock token verifier.
 * Strictly forbidden in production environments.
 */
function setTokenVerifierForTesting(verifier) {
  if (config.nodeEnv === 'production') {
    throw new Error('Test token verifier cannot be set in production mode.');
  }
  customTokenVerifier = verifier;
}

/**
 * Middleware requiring a valid Firebase Auth ID token in Authorization header.
 * Fails closed with 401 or 503 if credentials or tokens are invalid.
 */
async function authenticateToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      message: 'Missing or malformed Authorization header. Expected: Bearer <firebase_id_token>',
    });
  }

  const token = authHeader.substring(7).trim();
  if (!token) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      message: 'Firebase Auth ID token is empty.',
    });
  }

  // 1. In non-production testing, check if explicit test verifier was injected
  if (config.nodeEnv !== 'production' && customTokenVerifier) {
    try {
      const decoded = await customTokenVerifier(token);
      if (!decoded || !decoded.uid) {
        return res.status(401).json({
          success: false,
          error: 'UNAUTHORIZED',
          message: 'Invalid or expired Firebase ID token.',
        });
      }
      req.user = decoded;
      return next();
    } catch (err) {
      return res.status(401).json({
        success: false,
        error: 'UNAUTHORIZED',
        message: 'Invalid or expired Firebase ID token: ' + err.message,
      });
    }
  }

  // 2. Production or standard environment verification
  const isReady = initFirebaseAdmin();
  if (!isReady) {
    return res.status(503).json({
      success: false,
      error: 'AUTH_SERVICE_UNCONFIGURED',
      message: 'Firebase Admin SDK is not configured on this server. Set GOOGLE_APPLICATION_CREDENTIALS to a valid service account JSON.',
    });
  }

  try {
    const decodedToken = await admin.auth().verifyIdToken(token);
    req.user = decodedToken;
    next();
  } catch (err) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      message: 'Failed to verify Firebase ID token: ' + (err.code || err.message),
    });
  }
}

module.exports = {
  authenticateToken,
  setTokenVerifierForTesting,
  setForceUnconfiguredForTesting,
  resetFirebaseAdminForTesting,
  initFirebaseAdmin,
  isFirebaseConfigured,
};
