const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

// Set test environment before requiring app modules
process.env.NODE_ENV = 'test';
process.env.GEMINI_API_KEY = 'test_gemini_key';
process.env.ELEVENLABS_API_KEY = 'test_elevenlabs_key';
process.env.ADMIN_UIDS = 'admin_uid_1,admin_uid_2';

const app = require('../src/app');
const config = require('../src/config');
const { setTokenVerifierForTesting } = require('../src/middleware/auth');
const { setEmergencyLoaderForTesting } = require('../src/services/emergencyContextService');
const { setMockPoolForTesting, calculatePayloadHash } = require('../src/services/timescaleDbService');
const { getOperationalSummary, getSanitizedSummaryForGemini } = require('../src/services/analyticsSummaryService');
const { setMockGeminiClient } = require('../src/services/geminiService');

describe('Tiger Data / TimescaleDB Analytics Backend Tests', () => {
  let server;
  let baseUrl;

  // In-memory mock database store for SQL testing
  let mockRegistry;
  let mockLifecycleEvents;
  let mockRoutingEvents;
  let mockSyncEvents;
  let mockClient;
  let mockPool;

  before(async () => {
    server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, resolve));
    const port = server.address().port;
    baseUrl = `http://127.0.0.1:${port}`;
  });

  after(async () => {
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
  });

  beforeEach(() => {
    mockRegistry = new Map();
    mockLifecycleEvents = [];
    mockRoutingEvents = [];
    mockSyncEvents = [];

    // Construct mock database client with transaction support
    mockClient = {
      inTransaction: false,
      rolledBack: false,
      committed: false,
      query: async (queryText, params = []) => {
        const text = queryText.trim().toUpperCase();

        if (text === 'BEGIN') {
          mockClient.inTransaction = true;
          return { rows: [] };
        }
        if (text === 'COMMIT') {
          mockClient.committed = true;
          mockClient.inTransaction = false;
          return { rows: [] };
        }
        if (text === 'ROLLBACK') {
          mockClient.rolledBack = true;
          mockClient.inTransaction = false;
          return { rows: [] };
        }

        // Check registry
        if (text.startsWith('SELECT PAYLOAD_HASH FROM ANALYTICS_EVENT_REGISTRY')) {
          const eventId = params[0];
          if (mockRegistry.has(eventId)) {
            return { rows: [{ payload_hash: mockRegistry.get(eventId).payload_hash }] };
          }
          return { rows: [] };
        }

        // Insert into registry
        if (text.startsWith('INSERT INTO ANALYTICS_EVENT_REGISTRY')) {
          const [event_id, event_type, emergency_id, payload_hash] = params;
          mockRegistry.set(event_id, { event_id, event_type, emergency_id, payload_hash });
          return { rows: [] };
        }

        // Insert into lifecycle
        if (text.startsWith('INSERT INTO ANALYTICS_LIFECYCLE_EVENTS')) {
          mockLifecycleEvents.push({
            event_id: params[0],
            emergency_id: params[1],
            event_type: params[2],
            emergency_type: params[3],
            event_source: params[4],
            transport_mode: params[5],
            timestamp: params[6],
            duration_to_acceptance_ms: params[7],
            duration_to_arrival_ms: params[8],
            total_duration_ms: params[9],
            is_offline_created: params[10],
          });
          return { rows: [] };
        }

        // Insert into routing
        if (text.startsWith('INSERT INTO ANALYTICS_ROUTING_TELEMETRY')) {
          mockRoutingEvents.push({
            event_id: params[0],
            emergency_id: params[1],
            route_category: params[2],
            latency_ms: params[3],
            distance_bucket: params[4],
            success: params[5],
            failure_code: params[6],
            timestamp: params[7],
          });
          return { rows: [] };
        }

        // Insert into offline sync
        if (text.startsWith('INSERT INTO ANALYTICS_OFFLINE_SYNC_TELEMETRY')) {
          mockSyncEvents.push({
            event_id: params[0],
            emergency_id: params[1],
            retry_count: params[2],
            sync_latency_ms: params[3],
            terminal_status: params[4],
            success: params[5],
            error_category: params[6],
            timestamp: params[7],
          });
          return { rows: [] };
        }

        // Aggregation query for lifecycle
        if (text.includes('FROM ANALYTICS_LIFECYCLE_EVENTS') && text.includes('COUNT(DISTINCT EMERGENCY_ID)')) {
          const totalCreated = mockLifecycleEvents.filter(e => e.event_type === 'sos_created').length;
          const totalCompleted = mockLifecycleEvents.filter(e => e.event_type === 'emergency_completed').length;
          const totalCancelled = mockLifecycleEvents.filter(e => e.event_type === 'emergency_cancelled').length;
          const totalOffline = mockLifecycleEvents.filter(e => e.is_offline_created).length;

          const acceptTimes = mockLifecycleEvents
            .map(e => e.duration_to_acceptance_ms)
            .filter(d => d !== null && d !== undefined);
          const arrivalTimes = mockLifecycleEvents
            .map(e => e.duration_to_arrival_ms)
            .filter(d => d !== null && d !== undefined);

          const avgAccept = acceptTimes.length > 0 ? acceptTimes.reduce((a, b) => a + b, 0) / acceptTimes.length : null;
          const medianAccept = acceptTimes.length > 0 ? acceptTimes.sort((a, b) => a - b)[Math.floor(acceptTimes.length / 2)] : null;

          const avgArrival = arrivalTimes.length > 0 ? arrivalTimes.reduce((a, b) => a + b, 0) / arrivalTimes.length : null;
          const medianArrival = arrivalTimes.length > 0 ? arrivalTimes.sort((a, b) => a - b)[Math.floor(arrivalTimes.length / 2)] : null;

          return {
            rows: [{
              total_created: totalCreated,
              total_completed: totalCompleted,
              total_cancelled: totalCancelled,
              total_offline_created: totalOffline,
              avg_acceptance_ms: avgAccept,
              median_acceptance_ms: medianAccept,
              acceptance_sample_count: acceptTimes.length,
              avg_arrival_ms: avgArrival,
              median_arrival_ms: medianArrival,
              arrival_sample_count: arrivalTimes.length,
              avg_total_duration_ms: 120000,
            }],
          };
        }

        // Aggregation query for routing
        if (text.includes('FROM ANALYTICS_ROUTING_TELEMETRY')) {
          const totalRoutes = mockRoutingEvents.length;
          const successfulRoutes = mockRoutingEvents.filter(e => e.success).length;
          const failedRoutes = totalRoutes - successfulRoutes;
          const avgLatency = totalRoutes > 0 ? mockRoutingEvents.reduce((a, b) => a + b.latency_ms, 0) / totalRoutes : null;
          return {
            rows: [{
              total_routes: totalRoutes,
              successful_routes: successfulRoutes,
              failed_routes: failedRoutes,
              avg_latency_ms: avgLatency,
            }],
          };
        }

        // Aggregation query for offline sync
        if (text.includes('FROM ANALYTICS_OFFLINE_SYNC_TELEMETRY')) {
          const totalSyncs = mockSyncEvents.length;
          const successfulSyncs = mockSyncEvents.filter(e => e.success).length;
          const failedSyncs = totalSyncs - successfulSyncs;
          const avgLatency = totalSyncs > 0 ? mockSyncEvents.reduce((a, b) => a + b.sync_latency_ms, 0) / totalSyncs : null;
          const avgRetry = totalSyncs > 0 ? mockSyncEvents.reduce((a, b) => a + b.retry_count, 0) / totalSyncs : null;
          return {
            rows: [{
              total_syncs: totalSyncs,
              successful_syncs: successfulSyncs,
              failed_syncs: failedSyncs,
              avg_sync_latency_ms: avgLatency,
              avg_retry_count: avgRetry,
            }],
          };
        }

        // Comparison query
        if (text.includes('GROUP BY EVENT_SOURCE')) {
          return {
            rows: [
              { event_source: 'online', count: 5, avg_acceptance_ms: 45000, avg_arrival_ms: 180000 },
              { event_source: 'offline_p2p', count: 2, avg_acceptance_ms: 60000, avg_arrival_ms: 210000 },
            ],
          };
        }

        return { rows: [] };
      },
      release: () => {},
    };

    mockPool = {
      connect: async () => mockClient,
      on: () => {},
    };

    setMockPoolForTesting(mockPool);

    // Setup test token verifier
    setTokenVerifierForTesting((token) => {
      if (token === 'admin-token') {
        return { uid: 'admin_uid_1', email: 'admin@example.com', admin: true };
      }
      if (token === 'responder-token') {
        return { uid: 'responder_user_1', email: 'responder@example.com' };
      }
      if (token === 'victim-token') {
        return { uid: 'victim_user_1', email: 'victim@example.com' };
      }
      if (token === 'unauthorized-token') {
        return { uid: 'intruder_user_99', email: 'intruder@example.com' };
      }
      return null;
    });

    // Setup mock authoritative emergencies
    setEmergencyLoaderForTesting(async (emergencyId) => {
      if (emergencyId === 'em_test_active') {
        return {
          id: 'em_test_active',
          victimId: 'victim_user_1',
          type: 'MEDICAL',
          status: 'ASSIGNED',
          helperId: 'responder_user_1',
          responders: {
            responder_user_1: { role: 'PRIMARY' },
          },
          createdAt: new Date(Date.now() - 5 * 60000),
        };
      }
      return null;
    });
  });

  it('POST /api/analytics/events/batch rejects requests without Authorization header with 401', async () => {
    const res = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ events: [] }),
    });
    assert.equal(res.status, 401);
    const body = await res.json();
    assert.equal(body.error, 'UNAUTHORIZED');
  });

  it('Rejects request with empty events array with 400', async () => {
    const res = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer victim-token',
      },
      body: JSON.stringify({ events: [] }),
    });
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.equal(body.error, 'INVALID_BATCH');
  });

  it('Rejects batch exceeding max 50 limit with 400 BATCH_SIZE_EXCEEDED', async () => {
    const oversized = Array.from({ length: 51 }, (_, i) => ({
      eventId: `evt_${i}`,
      emergencyId: 'em_test_active',
      eventType: 'sos_created',
      timestamp: new Date().toISOString(),
    }));

    const res = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer victim-token',
      },
      body: JSON.stringify({ events: oversized }),
    });
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.equal(body.error, 'BATCH_SIZE_EXCEEDED');
  });

  it('Rejects events with future timestamps (>60s) with 400 FUTURE_TIMESTAMP_REJECTED', async () => {
    const futureTime = new Date(Date.now() + 5 * 60000).toISOString();
    const res = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer victim-token',
      },
      body: JSON.stringify({
        events: [
          {
            eventId: 'evt_future_1',
            emergencyId: 'em_test_active',
            eventType: 'sos_created',
            timestamp: futureTime,
          },
        ],
      }),
    });
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.equal(body.error, 'FUTURE_TIMESTAMP_REJECTED');
  });

  it('Rejects events containing forbidden PII or exact coordinates with 400 PRIVACY_VIOLATION', async () => {
    const res = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer victim-token',
      },
      body: JSON.stringify({
        events: [
          {
            eventId: 'evt_privacy_leak',
            emergencyId: 'em_test_active',
            eventType: 'sos_created',
            timestamp: new Date().toISOString(),
            latitude: 28.6139, // FORBIDDEN
            longitude: 77.2090, // FORBIDDEN
            victimName: 'Rahul Kumar', // FORBIDDEN
          },
        ],
      }),
    });
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.equal(body.error, 'PRIVACY_VIOLATION');
  });

  it('Rejects non-participant from ingesting analytics events for an emergency with 403 Forbidden', async () => {
    const res = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer unauthorized-token', // intruder
      },
      body: JSON.stringify({
        events: [
          {
            eventId: 'evt_intruder_1',
            emergencyId: 'em_test_active',
            eventType: 'sos_created',
            timestamp: new Date().toISOString(),
          },
        ],
      }),
    });
    assert.equal(res.status, 403);
    const body = await res.json();
    assert.equal(body.error, 'FORBIDDEN');
  });

  it('Authorizes legitimate participant and ingests batch of lifecycle, routing, and sync events', async () => {
    const timestamp = new Date().toISOString();
    const events = [
      {
        eventId: 'evt_life_1',
        emergencyId: 'em_test_active',
        eventType: 'sos_created',
        emergencyType: 'MEDICAL',
        eventSource: 'online',
        timestamp,
      },
      {
        eventId: 'evt_route_1',
        emergencyId: 'em_test_active',
        category: 'routing',
        routeCategory: 'scene_navigation',
        latencyMs: 150,
        distanceBucket: '500m-2km',
        success: true,
        timestamp,
      },
      {
        eventId: 'evt_sync_1',
        emergencyId: 'em_test_active',
        category: 'offline_sync',
        retryCount: 0,
        syncLatencyMs: 250,
        terminalStatus: 'COMPLETED',
        success: true,
        timestamp,
      },
    ];

    const res = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer responder-token',
      },
      body: JSON.stringify({ events }),
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(body.acceptedCount, 3);
    assert.equal(body.duplicateCount, 0);
    assert.equal(mockClient.committed, true);
    assert.equal(mockRegistry.size, 3);
    assert.equal(mockLifecycleEvents.length, 1);
    assert.equal(mockRoutingEvents.length, 1);
    assert.equal(mockSyncEvents.length, 1);
  });

  it('Enforces idempotency: repeated identical event ID is recognized as duplicate without re-inserting', async () => {
    const timestamp = new Date().toISOString();
    const event = {
      eventId: 'evt_idem_100',
      emergencyId: 'em_test_active',
      eventType: 'responder_accepted',
      emergencyType: 'MEDICAL',
      durationToAcceptanceMs: 35000,
      timestamp,
    };

    // First delivery
    const res1 = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer responder-token',
      },
      body: JSON.stringify({ events: [event] }),
    });
    assert.equal(res1.status, 200);
    const body1 = await res1.json();
    assert.equal(body1.acceptedCount, 1);
    assert.equal(body1.duplicateCount, 0);
    assert.equal(mockLifecycleEvents.length, 1);

    // Second delivery of identical event
    const res2 = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer responder-token',
      },
      body: JSON.stringify({ events: [event] }),
    });
    assert.equal(res2.status, 200);
    const body2 = await res2.json();
    assert.equal(body2.acceptedCount, 0);
    assert.equal(body2.duplicateCount, 1);
    assert.deepEqual(body2.duplicates, ['evt_idem_100']);
    // Verified: No second row added to lifecycle events table
    assert.equal(mockLifecycleEvents.length, 1);
  });

  it('Detects and flags conflicting payload reuse for the same event ID', async () => {
    const timestamp = new Date().toISOString();
    const eventOriginal = {
      eventId: 'evt_conflict_1',
      emergencyId: 'em_test_active',
      eventType: 'sos_created',
      timestamp,
    };

    // Ingest original
    await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer victim-token',
      },
      body: JSON.stringify({ events: [eventOriginal] }),
    });

    // Ingest modified payload using same event ID
    const eventModified = {
      eventId: 'evt_conflict_1',
      emergencyId: 'em_test_active',
      eventType: 'emergency_cancelled', // Modified!
      timestamp,
    };

    const res = await fetch(`${baseUrl}/api/analytics/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer victim-token',
      },
      body: JSON.stringify({ events: [eventModified] }),
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.acceptedCount, 0);
    assert.equal(body.conflicts.length, 1);
    assert.equal(body.conflicts[0], 'evt_conflict_1');
  });

  it('GET /api/analytics/summary rejects non-admin users with 403 Forbidden', async () => {
    const res = await fetch(`${baseUrl}/api/analytics/summary`, {
      method: 'GET',
      headers: {
        Authorization: 'Bearer responder-token', // Not an admin
      },
    });
    assert.equal(res.status, 403);
    const body = await res.json();
    assert.equal(body.error, 'FORBIDDEN_NOT_ADMIN');
  });

  it('GET /api/analytics/summary returns aggregate metrics for authorized administrator', async () => {
    // Populate mock events
    mockLifecycleEvents.push(
      {
        event_id: 'evt_1',
        emergency_id: 'em_1',
        event_type: 'sos_created',
        emergency_type: 'MEDICAL',
        event_source: 'online',
        is_offline_created: false,
        duration_to_acceptance_ms: 30000,
        duration_to_arrival_ms: 120000,
      },
      {
        event_id: 'evt_2',
        emergency_id: 'em_1',
        event_type: 'emergency_completed',
        emergency_type: 'MEDICAL',
        event_source: 'online',
        is_offline_created: false,
        duration_to_acceptance_ms: null,
        duration_to_arrival_ms: null,
      }
    );

    mockRoutingEvents.push(
      { success: true, latency_ms: 120 },
      { success: true, latency_ms: 180 }
    );

    const res = await fetch(`${baseUrl}/api/analytics/summary`, {
      method: 'GET',
      headers: {
        Authorization: 'Bearer admin-token',
      },
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(body.summary.sufficientData, true);
    assert.equal(body.summary.lifecycle.totalEmergencies, 1);
    assert.equal(body.summary.lifecycle.completed, 1);
    assert.equal(body.summary.responseTimes.timeToAcceptance.avgSeconds, 30);
    assert.equal(body.summary.responseTimes.timeToArrival.avgSeconds, 120);
    assert.equal(body.summary.routing.successRatePercent, 100);
  });

  it('Returns sufficientData=false when zero emergency records exist', async () => {
    const summary = await getOperationalSummary();
    assert.equal(summary.sufficientData, false);
    assert.equal(summary.metrics.totalEmergencies, 0);
  });

  it('getSanitizedSummaryForGemini returns clean summary text without PII', async () => {
    mockLifecycleEvents.push({
      event_id: 'evt_g1',
      emergency_id: 'em_g1',
      event_type: 'sos_created',
      duration_to_acceptance_ms: 45000,
      duration_to_arrival_ms: 150000,
    });
    mockRoutingEvents.push({ success: true, latency_ms: 100 });

    const geminiContext = await getSanitizedSummaryForGemini();
    assert.equal(geminiContext.available, true);
    assert.match(geminiContext.summaryText, /Operational Statistics/);
    assert.match(geminiContext.summaryText, /Total emergencies: 1/);
    assert.match(geminiContext.summaryText, /45s/);
  });

  it('GET /api/health reports timescaleDbConfigured state accurately', async () => {
    const res = await fetch(`${baseUrl}/api/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.readiness.timescaleDbConfigured, true);
  });

  it('POST /api/analytics/insights rejects non-admin users with 403 Forbidden', async () => {
    const res = await fetch(`${baseUrl}/api/analytics/insights`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer victim-token',
      },
      body: JSON.stringify({ focusArea: 'general' }),
    });

    assert.equal(res.status, 403);
    const body = await res.json();
    assert.equal(body.error, 'FORBIDDEN_NOT_ADMIN');
  });

  it('POST /api/analytics/insights returns available=false when data is insufficient', async () => {
    const res = await fetch(`${baseUrl}/api/analytics/insights`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer admin-token',
      },
      body: JSON.stringify({ focusArea: 'general' }),
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(body.available, false);
    assert.equal(body.reason, 'INSUFFICIENT_DATA');
  });

  it('POST /api/analytics/insights generates AI insights for authorized admin from aggregate metrics', async () => {
    // Populate mock events
    mockLifecycleEvents.push(
      {
        event_id: 'evt_i1',
        emergency_id: 'em_i1',
        event_type: 'sos_created',
        emergency_type: 'MEDICAL',
        event_source: 'online',
        is_offline_created: false,
        duration_to_acceptance_ms: 25000,
        duration_to_arrival_ms: 90000,
      },
      {
        event_id: 'evt_i2',
        emergency_id: 'em_i1',
        event_type: 'emergency_completed',
        emergency_type: 'MEDICAL',
        event_source: 'online',
        is_offline_created: false,
        duration_to_acceptance_ms: null,
        duration_to_arrival_ms: null,
      }
    );

    mockRoutingEvents.push({ success: true, latency_ms: 150 });
    mockSyncEvents.push({ success: true, sync_latency_ms: 200, retry_count: 0 });

    let capturedPrompt = null;
    let capturedSystemInstruction = null;

    setMockGeminiClient({
      models: {
        generateContent: async ({ contents, config: genConfig }) => {
          capturedPrompt = contents;
          capturedSystemInstruction = genConfig.systemInstruction;
          assert.deepStrictEqual(genConfig.thinkingConfig, { thinkingLevel: 'low' });
          return {
            text: '• Response Time: Average responder acceptance was 25s (N=1), indicating strong volunteer readiness.\n• Routing: 100% success rate with 150ms average latency.\n• Recommendation: Maintain current standby volunteer coverage.',
          };
        },
      },
    });

    const res = await fetch(`${baseUrl}/api/analytics/insights`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer admin-token',
      },
      body: JSON.stringify({ focusArea: 'response_times' }),
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(body.available, true);
    assert.equal(body.sampleSize, 1);
    assert.match(body.insights, /Response Time/);
    assert.match(body.insights, /25s/);
    assert.match(body.disclaimer, /AI-generated operational interpretation/);

    // Verify Gemini prompt never contained PII or coordinates
    assert.ok(capturedPrompt);
    assert.ok(!capturedPrompt.includes('latitude'));
    assert.ok(!capturedPrompt.includes('longitude'));
    assert.ok(!capturedPrompt.includes('victimName'));
    assert.ok(!capturedPrompt.includes('SELECT '));
    assert.ok(capturedSystemInstruction.includes('STRICT ANALYSIS & SAFETY RULES'));
  });
});
