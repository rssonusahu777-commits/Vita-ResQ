const crypto = require('crypto');
const { Pool } = require('pg');
const config = require('../config');

let pool = null;
let mockPool = null;

/**
 * Initializes or returns the PostgreSQL / TimescaleDB connection pool.
 * Fails safely if TIMESCALE_DATABASE_URL is not configured.
 */
function getPool() {
  if (config.nodeEnv !== 'production' && mockPool) {
    return mockPool;
  }

  if (!config.timescaleDatabaseUrl) {
    return null;
  }

  if (!pool) {
    pool = new Pool({
      connectionString: config.timescaleDatabaseUrl,
      max: 10,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
    });

    pool.on('error', (err) => {
      console.error('[TIMESCALE] Unexpected database pool error:', err.message);
    });
  }

  return pool;
}

/**
 * Reports whether the TimescaleDB analytics service is configured and available.
 */
function isTimescaleConfigured() {
  if (config.nodeEnv !== 'production' && mockPool) {
    return true;
  }
  return Boolean(config.timescaleDatabaseUrl);
}

/**
 * Allows automated tests to inject a mock connection pool.
 * Strictly forbidden in production mode.
 */
function setMockPoolForTesting(customMockPool) {
  if (config.nodeEnv === 'production') {
    throw new Error('Test database pool cannot be set in production mode.');
  }
  mockPool = customMockPool;
}

/**
 * Generates a deterministic SHA-256 hash of the canonical event payload
 * to enforce idempotency and detect conflicting payload modifications.
 */
function calculatePayloadHash(event) {
  const normalized = {
    eventId: event.eventId,
    emergencyId: event.emergencyId,
    eventType: event.eventType || event.category,
    timestamp: event.timestamp,
    emergencyType: event.emergencyType || null,
    eventSource: event.eventSource || null,
    transportMode: event.transportMode || null,
    durationToAcceptanceMs: event.durationToAcceptanceMs ?? null,
    durationToArrivalMs: event.durationToArrivalMs ?? null,
    totalDurationMs: event.totalDurationMs ?? null,
    routeCategory: event.routeCategory || null,
    latencyMs: event.latencyMs ?? null,
    distanceBucket: event.distanceBucket || null,
    success: event.success !== undefined ? Boolean(event.success) : null,
    failureCode: event.failureCode || null,
    retryCount: event.retryCount ?? null,
    terminalStatus: event.terminalStatus || null,
    errorCategory: event.errorCategory || null,
  };

  return crypto
    .createHash('sha256')
    .update(JSON.stringify(normalized))
    .digest('hex');
}

/**
 * Ingests a batch of validated analytics events within an atomic database transaction.
 * Detects duplicates and conflicting payloads using the event registry.
 *
 * @param {Array<Object>} events - Array of sanitized event objects
 * @returns {Promise<{accepted: string[], duplicates: string[], conflicts: string[], errors: string[]}>}
 */
async function ingestEventBatch(events) {
  const dbPool = getPool();
  if (!dbPool) {
    const err = new Error('TimescaleDB / Tiger Data Analytics database is unconfigured. Set TIMESCALE_DATABASE_URL to enable event ingestion.');
    err.statusCode = 503;
    err.code = 'ANALYTICS_DB_UNAVAILABLE';
    throw err;
  }

  const client = await dbPool.connect();
  const accepted = [];
  const duplicates = [];
  const conflicts = [];
  const errors = [];

  try {
    await client.query('BEGIN');

    for (const event of events) {
      try {
        const payloadHash = calculatePayloadHash(event);
        const eventId = event.eventId;
        const emergencyId = event.emergencyId;
        const eventType = event.eventType || event.category || 'unknown';
        const timestamp = new Date(event.timestamp);

        // 1. Check idempotency registry for existing event ID
        const existingRes = await client.query(
          'SELECT payload_hash FROM analytics_event_registry WHERE event_id = $1',
          [eventId]
        );

        if (existingRes.rows && existingRes.rows.length > 0) {
          const registeredHash = existingRes.rows[0].payload_hash;
          if (registeredHash === payloadHash) {
            // Identical payload delivered again: idempotent duplicate
            duplicates.push(eventId);
            continue;
          } else {
            // Conflicting payload with existing ID: reject
            conflicts.push(eventId);
            continue;
          }
        }

        // 2. Register new event ID
        await client.query(
          'INSERT INTO analytics_event_registry (event_id, event_type, emergency_id, payload_hash, first_received_at) VALUES ($1, $2, $3, $4, $5)',
          [eventId, eventType, emergencyId, payloadHash, new Date()]
        );

        // 3. Insert into the appropriate domain table
        const isLifecycle = ['sos_created', 'responder_accepted', 'responder_arrived', 'emergency_completed', 'emergency_cancelled'].includes(eventType) || event.category === 'lifecycle';
        const isRouting = event.category === 'routing' || event.routeCategory !== undefined;
        const isOfflineSync = event.category === 'offline_sync' || event.retryCount !== undefined;

        if (isLifecycle) {
          await client.query(
            `INSERT INTO analytics_lifecycle_events (
              event_id, emergency_id, event_type, emergency_type, event_source,
              transport_mode, timestamp, duration_to_acceptance_ms, duration_to_arrival_ms,
              total_duration_ms, is_offline_created
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
            [
              eventId,
              emergencyId,
              eventType,
              event.emergencyType || 'GENERAL',
              event.eventSource || 'online',
              event.transportMode || null,
              timestamp,
              event.durationToAcceptanceMs !== undefined ? event.durationToAcceptanceMs : null,
              event.durationToArrivalMs !== undefined ? event.durationToArrivalMs : null,
              event.totalDurationMs !== undefined ? event.totalDurationMs : null,
              Boolean(event.isOfflineCreated),
            ]
          );
        } else if (isRouting) {
          await client.query(
            `INSERT INTO analytics_routing_telemetry (
              event_id, emergency_id, route_category, latency_ms, distance_bucket,
              success, failure_code, timestamp
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
            [
              eventId,
              emergencyId,
              event.routeCategory || 'scene_navigation',
              parseInt(event.latencyMs, 10) || 0,
              event.distanceBucket || null,
              Boolean(event.success),
              event.failureCode || null,
              timestamp,
            ]
          );
        } else if (isOfflineSync) {
          await client.query(
            `INSERT INTO analytics_offline_sync_telemetry (
              event_id, emergency_id, retry_count, sync_latency_ms, terminal_status,
              success, error_category, timestamp
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
            [
              eventId,
              emergencyId,
              parseInt(event.retryCount, 10) || 0,
              parseInt(event.syncLatencyMs, 10) || 0,
              event.terminalStatus || null,
              Boolean(event.success),
              event.errorCategory || (event.success ? 'SUCCESS' : 'UNKNOWN'),
              timestamp,
            ]
          );
        }

        accepted.push(eventId);
      } catch (itemErr) {
        errors.push({ eventId: event.eventId, error: itemErr.message });
        throw itemErr; // Trigger transaction rollback
      }
    }

    await client.query('COMMIT');
    return { accepted, duplicates, conflicts, errors };
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    const dbErr = new Error('Database transaction failed during analytics batch ingestion: ' + err.message);
    dbErr.statusCode = 500;
    dbErr.code = 'ANALYTICS_TRANSACTION_FAILED';
    throw dbErr;
  } finally {
    client.release();
  }
}

module.exports = {
  getPool,
  isTimescaleConfigured,
  setMockPoolForTesting,
  calculatePayloadHash,
  ingestEventBatch,
};
