-- Vita ResQ Tiger Data Analytics Schema Migration 001
-- PostgreSQL / TimescaleDB Schema for Operational Emergency Performance Telemetry
-- Strict Privacy: Zero PII, Zero Exact GPS Coordinates, Zero Raw Medical Data.

-- 1. Idempotency Registry Table (Global event deduplication across all tables/hypertables)
CREATE TABLE IF NOT EXISTS analytics_event_registry (
    event_id VARCHAR(64) PRIMARY KEY,
    event_type VARCHAR(64) NOT NULL,
    emergency_id VARCHAR(64) NOT NULL,
    payload_hash VARCHAR(64) NOT NULL,
    first_received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status VARCHAR(32) NOT NULL DEFAULT 'PROCESSED'
);

CREATE INDEX IF NOT EXISTS idx_registry_emergency_id ON analytics_event_registry(emergency_id);
CREATE INDEX IF NOT EXISTS idx_registry_first_received ON analytics_event_registry(first_received_at DESC);

-- 2. Lifecycle Events Table
CREATE TABLE IF NOT EXISTS analytics_lifecycle_events (
    event_id VARCHAR(64) NOT NULL,
    emergency_id VARCHAR(64) NOT NULL,
    event_type VARCHAR(64) NOT NULL, -- 'sos_created', 'responder_accepted', 'responder_arrived', 'emergency_completed', 'emergency_cancelled'
    emergency_type VARCHAR(32) NOT NULL, -- 'MEDICAL', 'ACCIDENT', 'FIRE', 'CRIME', 'GENERAL'
    event_source VARCHAR(32) NOT NULL, -- 'online', 'offline_p2p'
    transport_mode VARCHAR(32), -- 'DRIVING', 'WALKING', 'TWO_WHEELER', etc.
    timestamp TIMESTAMPTZ NOT NULL,
    duration_to_acceptance_ms BIGINT, -- NULL if cancelled before acceptance
    duration_to_arrival_ms BIGINT, -- NULL if cancelled or completed before arrival
    total_duration_ms BIGINT, -- Duration from creation to terminal state
    is_offline_created BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_analytics_lifecycle_events PRIMARY KEY (event_id, timestamp)
);

CREATE INDEX IF NOT EXISTS idx_lifecycle_emergency_id ON analytics_lifecycle_events(emergency_id);
CREATE INDEX IF NOT EXISTS idx_lifecycle_timestamp ON analytics_lifecycle_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_lifecycle_event_type ON analytics_lifecycle_events(event_type);
CREATE INDEX IF NOT EXISTS idx_lifecycle_emergency_type ON analytics_lifecycle_events(emergency_type);

-- 3. Routing Telemetry Table
CREATE TABLE IF NOT EXISTS analytics_routing_telemetry (
    event_id VARCHAR(64) NOT NULL,
    emergency_id VARCHAR(64) NOT NULL,
    route_category VARCHAR(32) NOT NULL, -- 'scene_navigation', 'hospital_transfer'
    latency_ms INTEGER NOT NULL,
    distance_bucket VARCHAR(32), -- '<500m', '500m-2km', '2km-5km', '5km-10km', '>10km'
    success BOOLEAN NOT NULL,
    failure_code VARCHAR(64), -- 'OSRM_TIMEOUT', 'NO_ROUTE_FOUND', 'NETWORK_OFFLINE', etc.
    timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_analytics_routing_telemetry PRIMARY KEY (event_id, timestamp)
);

CREATE INDEX IF NOT EXISTS idx_routing_timestamp ON analytics_routing_telemetry(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_routing_category ON analytics_routing_telemetry(route_category);
CREATE INDEX IF NOT EXISTS idx_routing_success ON analytics_routing_telemetry(success);

-- 4. Offline Synchronization Telemetry Table
CREATE TABLE IF NOT EXISTS analytics_offline_sync_telemetry (
    event_id VARCHAR(64) NOT NULL,
    emergency_id VARCHAR(64) NOT NULL,
    retry_count INTEGER NOT NULL DEFAULT 0,
    sync_latency_ms INTEGER NOT NULL,
    terminal_status VARCHAR(32), -- 'COMPLETED', 'CANCELLED', 'ASSIGNED', etc.
    success BOOLEAN NOT NULL,
    error_category VARCHAR(64), -- 'AUTH_MISMATCH', 'NETWORK_UNAVAILABLE', 'TERMINAL_CONFLICT', 'SUCCESS'
    timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_analytics_offline_sync_telemetry PRIMARY KEY (event_id, timestamp)
);

CREATE INDEX IF NOT EXISTS idx_offline_sync_timestamp ON analytics_offline_sync_telemetry(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_offline_sync_success ON analytics_offline_sync_telemetry(success);

-- 5. TimescaleDB Hypertable Conversion (Safely applied when TimescaleDB extension is active)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        PERFORM create_hypertable('analytics_lifecycle_events', 'timestamp', if_not_exists => TRUE);
        PERFORM create_hypertable('analytics_routing_telemetry', 'timestamp', if_not_exists => TRUE);
        PERFORM create_hypertable('analytics_offline_sync_telemetry', 'timestamp', if_not_exists => TRUE);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'TimescaleDB hypertable setup skipped or unsupported: %', SQLERRM;
END $$;
