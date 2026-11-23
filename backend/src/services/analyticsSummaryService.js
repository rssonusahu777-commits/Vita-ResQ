const { getPool, isTimescaleConfigured } = require('./timescaleDbService');

/**
 * Service to calculate privacy-preserving aggregate operational performance statistics
 * from PostgreSQL / TimescaleDB.
 *
 * Strict Rules:
 * - Returns ONLY aggregated statistical metrics (counts, averages, medians, rates).
 * - NEVER exposes individual victim names, user IDs, coordinates, or raw event payloads.
 * - Distinguishes NULL durations (e.g. cancelled before acceptance) from real zero durations.
 * - Explains sample sizes and flags metrics with insufficient data.
 */

/**
 * Retrieves aggregate operational statistics across emergencies, routing, and offline sync.
 *
 * @param {Object} options
 * @param {Date|string} [options.fromTime] - Start of time window (defaults to 30 days ago)
 * @param {Date|string} [options.toTime] - End of time window (defaults to now)
 * @param {string} [options.emergencyType] - Optional emergency type filter (e.g. 'MEDICAL')
 * @returns {Promise<Object>}
 */
async function getOperationalSummary(options = {}) {
  const dbPool = getPool();
  if (!dbPool) {
    const err = new Error('TimescaleDB / Tiger Data Analytics database is unconfigured.');
    err.statusCode = 503;
    err.code = 'ANALYTICS_DB_UNAVAILABLE';
    throw err;
  }

  const now = new Date();
  const fromTime = options.fromTime ? new Date(options.fromTime) : new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const toTime = options.toTime ? new Date(options.toTime) : now;
  const emergencyType = options.emergencyType || null;

  const client = await dbPool.connect();
  try {
    // 1. Lifecycle totals and breakdown
    const lifecycleQuery = `
      SELECT 
        COUNT(DISTINCT emergency_id) FILTER (WHERE event_type = 'sos_created') AS total_created,
        COUNT(DISTINCT emergency_id) FILTER (WHERE event_type = 'emergency_completed') AS total_completed,
        COUNT(DISTINCT emergency_id) FILTER (WHERE event_type = 'emergency_cancelled') AS total_cancelled,
        COUNT(DISTINCT emergency_id) FILTER (WHERE is_offline_created = TRUE) AS total_offline_created,
        AVG(duration_to_acceptance_ms) FILTER (WHERE duration_to_acceptance_ms IS NOT NULL) AS avg_acceptance_ms,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_to_acceptance_ms) FILTER (WHERE duration_to_acceptance_ms IS NOT NULL) AS median_acceptance_ms,
        COUNT(duration_to_acceptance_ms) FILTER (WHERE duration_to_acceptance_ms IS NOT NULL) AS acceptance_sample_count,
        AVG(duration_to_arrival_ms) FILTER (WHERE duration_to_arrival_ms IS NOT NULL) AS avg_arrival_ms,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_to_arrival_ms) FILTER (WHERE duration_to_arrival_ms IS NOT NULL) AS median_arrival_ms,
        COUNT(duration_to_arrival_ms) FILTER (WHERE duration_to_arrival_ms IS NOT NULL) AS arrival_sample_count,
        AVG(total_duration_ms) FILTER (WHERE total_duration_ms IS NOT NULL) AS avg_total_duration_ms
      FROM analytics_lifecycle_events
      WHERE timestamp >= $1 AND timestamp <= $2
      ${emergencyType ? 'AND emergency_type = $3' : ''}
    `;

    const lifecycleParams = emergencyType ? [fromTime, toTime, emergencyType] : [fromTime, toTime];
    const lifecycleRes = await client.query(lifecycleQuery, lifecycleParams);
    const lifeRow = lifecycleRes.rows[0] || {};

    const totalCreated = parseInt(lifeRow.total_created, 10) || 0;
    const totalCompleted = parseInt(lifeRow.total_completed, 10) || 0;
    const totalCancelled = parseInt(lifeRow.total_cancelled, 10) || 0;
    const totalOfflineCreated = parseInt(lifeRow.total_offline_created, 10) || 0;

    // Check if sufficient data exists
    if (totalCreated === 0) {
      return {
        sufficientData: false,
        timeWindow: {
          from: fromTime.toISOString(),
          to: toTime.toISOString(),
        },
        message: 'No operational emergency records found in the specified time window.',
        metrics: {
          totalEmergencies: 0,
          completed: 0,
          cancelled: 0,
          active: 0,
        },
      };
    }

    // 2. Routing Telemetry
    const routingQuery = `
      SELECT 
        COUNT(*) AS total_routes,
        COUNT(*) FILTER (WHERE success = TRUE) AS successful_routes,
        COUNT(*) FILTER (WHERE success = FALSE) AS failed_routes,
        AVG(latency_ms) AS avg_latency_ms
      FROM analytics_routing_telemetry
      WHERE timestamp >= $1 AND timestamp <= $2
    `;
    const routingRes = await client.query(routingQuery, [fromTime, toTime]);
    const routeRow = routingRes.rows[0] || {};
    const totalRoutes = parseInt(routeRow.total_routes, 10) || 0;
    const successfulRoutes = parseInt(routeRow.successful_routes, 10) || 0;
    const routingSuccessRate = totalRoutes > 0 ? ((successfulRoutes / totalRoutes) * 100).toFixed(1) : null;

    // 3. Offline Sync Telemetry
    const syncQuery = `
      SELECT 
        COUNT(*) AS total_syncs,
        COUNT(*) FILTER (WHERE success = TRUE) AS successful_syncs,
        COUNT(*) FILTER (WHERE success = FALSE) AS failed_syncs,
        AVG(sync_latency_ms) AS avg_sync_latency_ms,
        AVG(retry_count) AS avg_retry_count
      FROM analytics_offline_sync_telemetry
      WHERE timestamp >= $1 AND timestamp <= $2
    `;
    const syncRes = await client.query(syncQuery, [fromTime, toTime]);
    const syncRow = syncRes.rows[0] || {};
    const totalSyncs = parseInt(syncRow.total_syncs, 10) || 0;
    const successfulSyncs = parseInt(syncRow.successful_syncs, 10) || 0;
    const syncSuccessRate = totalSyncs > 0 ? ((successfulSyncs / totalSyncs) * 100).toFixed(1) : null;

    // 4. Online vs Offline Response Comparison
    const comparisonQuery = `
      SELECT 
        event_source,
        COUNT(*) AS count,
        AVG(duration_to_acceptance_ms) FILTER (WHERE duration_to_acceptance_ms IS NOT NULL) AS avg_acceptance_ms,
        AVG(duration_to_arrival_ms) FILTER (WHERE duration_to_arrival_ms IS NOT NULL) AS avg_arrival_ms
      FROM analytics_lifecycle_events
      WHERE timestamp >= $1 AND timestamp <= $2
      GROUP BY event_source
    `;
    const comparisonRes = await client.query(comparisonQuery, [fromTime, toTime]);
    const comparison = {};
    for (const row of comparisonRes.rows) {
      comparison[row.event_source] = {
        sampleCount: parseInt(row.count, 10) || 0,
        avgAcceptanceSec: row.avg_acceptance_ms ? Math.round(row.avg_acceptance_ms / 1000) : null,
        avgArrivalSec: row.avg_arrival_ms ? Math.round(row.avg_arrival_ms / 1000) : null,
      };
    }

    return {
      sufficientData: true,
      timeWindow: {
        from: fromTime.toISOString(),
        to: toTime.toISOString(),
      },
      lifecycle: {
        totalEmergencies: totalCreated,
        completed: totalCompleted,
        cancelled: totalCancelled,
        offlineInitiated: totalOfflineCreated,
        completionRatePercent: totalCreated > 0 ? Number(((totalCompleted / totalCreated) * 100).toFixed(1)) : 0,
      },
      responseTimes: {
        timeToAcceptance: {
          sampleCount: parseInt(lifeRow.acceptance_sample_count, 10) || 0,
          avgSeconds: lifeRow.avg_acceptance_ms ? Math.round(lifeRow.avg_acceptance_ms / 1000) : null,
          medianSeconds: lifeRow.median_acceptance_ms ? Math.round(lifeRow.median_acceptance_ms / 1000) : null,
        },
        timeToArrival: {
          sampleCount: parseInt(lifeRow.arrival_sample_count, 10) || 0,
          avgSeconds: lifeRow.avg_arrival_ms ? Math.round(lifeRow.avg_arrival_ms / 1000) : null,
          medianSeconds: lifeRow.median_arrival_ms ? Math.round(lifeRow.median_arrival_ms / 1000) : null,
        },
        avgTotalDurationSeconds: lifeRow.avg_total_duration_ms ? Math.round(lifeRow.avg_total_duration_ms / 1000) : null,
      },
      routing: {
        totalRequests: totalRoutes,
        successfulRequests: successfulRoutes,
        successRatePercent: routingSuccessRate ? parseFloat(routingSuccessRate) : null,
        avgLatencyMs: routeRow.avg_latency_ms ? Math.round(routeRow.avg_latency_ms) : null,
      },
      offlineSync: {
        totalSyncAttempts: totalSyncs,
        successfulSyncs,
        successRatePercent: syncSuccessRate ? parseFloat(syncSuccessRate) : null,
        avgSyncLatencyMs: syncRow.avg_sync_latency_ms ? Math.round(syncRow.avg_sync_latency_ms) : null,
        avgRetryCount: syncRow.avg_retry_count ? parseFloat(Number(syncRow.avg_retry_count).toFixed(2)) : null,
      },
      onlineVsOffline: comparison,
      generatedAt: new Date().toISOString(),
    };
  } finally {
    client.release();
  }
}

/**
 * Provides a clean aggregate statistical summary formatted for Gemini prompt enrichment.
 * Zero PII, zero coordinates, only verified high-level metrics.
 */
async function getSanitizedSummaryForGemini(options = {}) {
  try {
    const summary = await getOperationalSummary(options);
    if (!summary.sufficientData) {
      return {
        available: false,
        summaryText: 'Insufficient historical analytics data recorded to date.',
      };
    }

    const life = summary.lifecycle;
    const resp = summary.responseTimes;
    const text = `Operational Statistics: Total emergencies: ${life.totalEmergencies} (${life.completed} completed, ${life.cancelled} cancelled). ` +
      `Average responder acceptance time: ${resp.timeToAcceptance.avgSeconds !== null ? resp.timeToAcceptance.avgSeconds + 's' : 'N/A'}. ` +
      `Average responder arrival time: ${resp.timeToArrival.avgSeconds !== null ? resp.timeToArrival.avgSeconds + 's' : 'N/A'}. ` +
      `Routing success rate: ${summary.routing.successRatePercent !== null ? summary.routing.successRatePercent + '%' : 'N/A'}.`;

    return {
      available: true,
      summaryText: text,
      data: summary,
    };
  } catch (err) {
    return {
      available: false,
      summaryText: 'Operational analytics unavailable.',
      error: err.message,
    };
  }
}

module.exports = {
  getOperationalSummary,
  getSanitizedSummaryForGemini,
};
