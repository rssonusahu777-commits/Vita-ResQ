const config = require('../config');

// In-memory per-user rate limiter for local development.
// Note: In a production multi-instance deployment, this should be backed by Redis or Memcached.
const rateLimitStores = [];

function createRateLimiter({
  getWindowMs = () => config.rateLimitWindowMs,
  getMaxRequests = () => config.rateLimitMaxRequests,
  message = (max) => `Too many requests. Limit is ${max} requests per minute.`,
  errorCode = 'RATE_LIMIT_EXCEEDED',
} = {}) {
  const userRequestLogs = new Map();
  rateLimitStores.push(userRequestLogs);

  const limiter = (req, res, next) => {
    // Rate limit by authenticated user UID if available, else by client IP
    const userKey = (req.user && req.user.uid) || req.ip || 'anonymous';
    const now = Date.now();
    const windowMs = typeof getWindowMs === 'function' ? getWindowMs() : getWindowMs;
    const maxRequests = typeof getMaxRequests === 'function' ? getMaxRequests() : getMaxRequests;

    let timestamps = userRequestLogs.get(userKey) || [];

    // Prune timestamps outside current window
    timestamps = timestamps.filter(ts => now - ts < windowMs);

    if (timestamps.length >= maxRequests) {
      const oldestTimestamp = timestamps[0];
      const retryAfterMs = Math.max(0, oldestTimestamp + windowMs - now);
      const retryAfterSec = Math.ceil(retryAfterMs / 1000);

      res.set('Retry-After', String(retryAfterSec));
      return res.status(429).json({
        success: false,
        error: errorCode,
        message: typeof message === 'function' ? message(maxRequests) : message,
        retryAfterSeconds: retryAfterSec,
      });
    }

    timestamps.push(now);
    userRequestLogs.set(userKey, timestamps);
    next();
  };

  limiter.reset = () => userRequestLogs.clear();
  return limiter;
}

const rateLimiter = createRateLimiter({
  getWindowMs: () => config.rateLimitWindowMs,
  getMaxRequests: () => config.rateLimitMaxRequests,
  message: (max) => `Too many AI assistant requests. Limit is ${max} requests per minute.`,
  errorCode: 'RATE_LIMIT_EXCEEDED',
});

const voiceRateLimiter = createRateLimiter({
  getWindowMs: () => config.voiceRateLimitWindowMs,
  getMaxRequests: () => config.voiceRateLimitMaxRequests,
  message: (max) => `Too many voice assistant requests. Limit is ${max} requests per minute.`,
  errorCode: 'VOICE_RATE_LIMIT_EXCEEDED',
});

function resetRateLimiterForTesting() {
  for (const store of rateLimitStores) {
    store.clear();
  }
}

module.exports = {
  rateLimiter,
  voiceRateLimiter,
  createRateLimiter,
  resetRateLimiterForTesting,
};
