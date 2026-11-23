const test = require('node:test');
const assert = require('node:assert');
const {
  sanitizeAuthoritativeEmergencyContext,
  formatCoarseDistance,
  validateEmergencyAccess,
} = require('../src/services/emergencyContextService');

test('Emergency Context Sanitization & Strict Privacy Tests', async (t) => {
  await t.test('Strips all PII: coordinates, real names, phone numbers, tokens, and blood groups', () => {
    const authoritativeEmergency = {
      id: 'EM-CONFIDENTIAL-999',
      victimId: 'victim_123',
      victimName: 'John Doe',
      victimPhone: '+919876543210',
      bloodGroup: 'B+ Positive',
      latitude: 28.6139345, // Exact coordinates
      longitude: 77.2090212,
      originDeviceId: 'device_secure_uuid_9999',
      helperId: 'responder_456',
      type: 'MEDICAL',
      status: 'ASSIGNED',
      createdAt: new Date(Date.now() - 300000).toISOString(), // 5 mins ago
      responders: {
        'responder_456': {
          userName: 'Alice Smith',
          phoneNumber: '+919123456780',
          role: 'PRIMARY',
          latitude: 28.6180,
          longitude: 77.2100,
          distanceToVictim: 475.0,
          etaText: '4 min',
          isRoadRoute: true,
        },
      },
    };

    const sanitized = sanitizeAuthoritativeEmergencyContext(authoritativeEmergency, 'victim_123');

    // 1. Assert PII is completely absent
    assert.strictEqual(sanitized.victimName, undefined);
    assert.strictEqual(sanitized.victimPhone, undefined);
    assert.strictEqual(sanitized.bloodGroup, undefined);
    assert.strictEqual(sanitized.latitude, undefined);
    assert.strictEqual(sanitized.longitude, undefined);
    assert.strictEqual(sanitized.originDeviceId, undefined);
    assert.strictEqual(sanitized.victimId, undefined);

    // 2. Assert operational coarse facts are preserved
    assert.strictEqual(sanitized.emergencyType, 'MEDICAL');
    assert.strictEqual(sanitized.status, 'ASSIGNED');
    assert.strictEqual(sanitized.callerPerspective, 'VICTIM');
    assert.strictEqual(sanitized.hasAssignedResponder, true);
    assert.strictEqual(sanitized.responderCount, 1);
    assert.strictEqual(sanitized.roadRouteAvailable, true);
    assert.strictEqual(sanitized.etaText, '4 min');
    assert.strictEqual(sanitized.elapsedMinutes, 5);

    // Coarse distance must not pinpoint exact meters
    assert.strictEqual(sanitized.coarseDistance, 'Approximately 500 meters');
  });

  await t.test('Client distance is treated as untrusted: stale client metrics (>60s) falls back to server data', () => {
    const authoritative = {
      victimId: 'victim_123',
      helperId: 'resp_1',
      status: 'ASSIGNED',
      responders: {
        'resp_1': { role: 'PRIMARY', distanceToVictim: 800.0, etaText: '6 min', isRoadRoute: true },
      },
    };

    // Client passes a forged/stale metric (timestamp 5 minutes ago)
    const staleMetrics = {
      distanceMeters: 50.0,
      etaText: '1 min',
      timestamp: new Date(Date.now() - 300000).toISOString(),
    };

    const sanitized = sanitizeAuthoritativeEmergencyContext(authoritative, 'victim_123', staleMetrics);
    // Must fall back to authoritative server data (800m -> ~800m), ignoring stale client metric
    assert.strictEqual(sanitized.coarseDistance, 'Approximately 800 meters');
    assert.strictEqual(sanitized.etaText, '6 min');
  });

  await t.test('Client distance cannot forge responder assignment when authoritative record has no helper', () => {
    const authoritative = {
      victimId: 'victim_123',
      helperId: null, // No primary helper assigned
      status: 'SEARCHING',
      responders: {},
    };

    // Client attempts to claim distance/ETA is 100m
    const forgedMetrics = {
      distanceMeters: 100.0,
      etaText: '1 min',
      timestamp: new Date().toISOString(),
    };

    const sanitized = sanitizeAuthoritativeEmergencyContext(authoritative, 'victim_123', forgedMetrics);
    // Must NOT state distance; must explicitly report no responder assigned
    assert.strictEqual(sanitized.hasAssignedResponder, false);
    assert.strictEqual(sanitized.coarseDistance, 'N/A (No responder assigned yet)');
    assert.strictEqual(sanitized.etaText, 'ETA unavailable (searching for nearby responders)');
  });

  await t.test('formatCoarseDistance correctly handles zero, near, kilometer and missing values', () => {
    // True zero distance
    assert.strictEqual(formatCoarseDistance(0.0), 'At scene (0 meters)');
    assert.strictEqual(formatCoarseDistance(0.2), 'At scene (0 meters)');

    // Immediate proximity
    assert.strictEqual(formatCoarseDistance(25.0), 'Immediate proximity (< 50 meters)');

    // Hundreds of meters rounded to nearest 50m
    assert.strictEqual(formatCoarseDistance(320.0), 'Approximately 300 meters');
    assert.strictEqual(formatCoarseDistance(340.0), 'Approximately 350 meters');

    // Kilometers
    assert.strictEqual(formatCoarseDistance(1520.0), 'Approximately 1.5 km');
    assert.strictEqual(formatCoarseDistance(3890.0), 'Approximately 3.9 km');

    // Missing, negative, or NaN
    assert.strictEqual(formatCoarseDistance(null), 'Distance temporarily unavailable (awaiting GPS acquisition)');
    assert.strictEqual(formatCoarseDistance(undefined), 'Distance temporarily unavailable (awaiting GPS acquisition)');
    assert.strictEqual(formatCoarseDistance(NaN), 'Distance temporarily unavailable (awaiting GPS acquisition)');
    assert.strictEqual(formatCoarseDistance(-10.0), 'Distance temporarily unavailable (awaiting GPS acquisition)');
  });

  await t.test('validateEmergencyAccess authorizes only legitimate participants', () => {
    const emergency = {
      victimId: 'victim_user',
      helperId: 'primary_helper',
      responders: {
        'primary_helper': { role: 'PRIMARY' },
        'standby_helper': { role: 'STANDBY' },
      },
    };

    assert.strictEqual(validateEmergencyAccess('victim_user', emergency), true);
    assert.strictEqual(validateEmergencyAccess('primary_helper', emergency), true);
    assert.strictEqual(validateEmergencyAccess('standby_helper', emergency), true);
    assert.strictEqual(validateEmergencyAccess('random_stranger', emergency), false);
    assert.strictEqual(validateEmergencyAccess('', emergency), false);
    assert.strictEqual(validateEmergencyAccess(null, emergency), false);
  });
});
