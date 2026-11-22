// lib/repositories/emergency_repository.dart
//
// SafeReach — Emergency Repository (local-first, Phase 2)
// Package: com.example.safereach
//
// This is the single entry point for all Emergency mutations and reads.
// Phase 2: local DB only. Phase 3 adds Firestore sync on top.
//
// Design rules followed:
//   Rule #7 — IDs generated via Emergency.generateId() (Random.secure()).
//   Rule #8 — Every mutation is written locally first; sync queue managed here.
//   State machine — canTransitionTo() ALWAYS checked before any DB write.

import 'dart:async';

import '../models/emergency.dart';
import '../services/local_emergency_store.dart';
import '../services/location_service.dart';

// ---------------------------------------------------------------------------
// Result type for state transitions (avoids throwing for expected failures)
// ---------------------------------------------------------------------------

/// Outcome of an [EmergencyRepository.transitionStatus] call.
sealed class TransitionResult {
  const TransitionResult();
}

/// Transition succeeded; [emergency] is the updated record.
final class TransitionSuccess extends TransitionResult {
  final Emergency emergency;
  const TransitionSuccess(this.emergency);
}

/// Transition was rejected by the state machine.
final class TransitionRejected extends TransitionResult {
  final String reason;
  const TransitionRejected(this.reason);
}

/// Transition could not be completed because the emergency was not found.
final class TransitionNotFound extends TransitionResult {
  final String id;
  const TransitionNotFound(this.id);
}

// ---------------------------------------------------------------------------
// EmergencyRepository
// ---------------------------------------------------------------------------

/// Unified interface for creating, reading, watching, and transitioning
/// [Emergency] records. All writes go to [LocalEmergencyStore] first.
///
/// Phase 3 will add a [FirestoreSyncWorker] layer that drains
/// [getPendingSyncEmergencies] when connectivity is confirmed.
class EmergencyRepository {
  final LocalEmergencyStore _store;
  final LocationService _locationService;

  EmergencyRepository({
    required LocalEmergencyStore store,
    required LocationService locationService,
  })  : _store = store,
        _locationService = locationService;

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------

  /// Creates a new [Emergency] from a GPS fix and stores it locally.
  ///
  /// - ID is generated client-side via [Emergency.generateId()] (Rule #7).
  /// - Attempts a fresh GPS fix; falls back to cached coordinates if unavailable.
  /// - Initial status is always [EmergencyStatus.created].
  /// - Persisted with [SyncStatus.pending] for later Firestore sync (Rule #8).
  Future<Emergency> createEmergency({
    required String victimId,
    required EmergencyType type,
    DetectionSource detectionSource = DetectionSource.manualHelp,
    CommunicationMode communicationMode = CommunicationMode.offline,
    // Allow callers to supply a pre-acquired fix (e.g., from positionStream).
    LocationFix? locationOverride,
  }) async {
    final fix = locationOverride ?? await _bestAvailableFix();

    final emergency = Emergency(
      id: Emergency.generateId(),
      victimId: victimId,
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyMeters: fix.accuracyMeters ?? 0.0,
      type: type,
      createdAt: DateTime.now().toUtc(),
      detectionSource: detectionSource,
      status: EmergencyStatus.created,
      communicationMode: communicationMode,
      version: 1,
    );

    await _store.saveEmergency(emergency, syncStatus: SyncStatus.pending);
    return emergency;
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the [Emergency] for [id], or `null` if not found locally.
  Emergency? getById(String id) => _store.getEmergencyById(id);

  /// Returns all locally persisted emergencies, newest first.
  List<Emergency> getAll() => _store.getAllEmergencies();

  /// Returns all emergencies that are pending or failed sync.
  List<Emergency> getPendingSync() => _store.getPendingSyncEmergencies();

  // ---------------------------------------------------------------------------
  // Watch (Rule #6 — single-lifecycle stream, no duplication)
  // ---------------------------------------------------------------------------

  /// Stream that emits the latest [Emergency] for [id] on every local change.
  /// Returns `null` if the record doesn't exist yet.
  ///
  /// Callers must cancel their [StreamSubscription] in `dispose()` (Rule #6).
  Stream<Emergency?> watchById(String id) => _store.watchEmergency(id);

  // ---------------------------------------------------------------------------
  // State transitions
  // ---------------------------------------------------------------------------

  /// Attempts to transition [id] to [nextStatus].
  ///
  /// Enforces the state machine via [Emergency.canTransitionTo()].
  /// On success, the updated record is persisted locally with
  /// [SyncStatus.pending] (Rule #8) and the caller receives a
  /// [TransitionSuccess] result.
  ///
  /// Returns [TransitionRejected] or [TransitionNotFound] on failure —
  /// never throws for expected state-machine violations.
  Future<TransitionResult> transitionStatus(
    String id,
    EmergencyStatus nextStatus, {
    String? primaryResponderId,
    bool clearPrimaryResponderId = false,
    String? standbyResponderId,
    bool clearStandbyResponderId = false,
  }) async {
    final current = _store.getEmergencyById(id);
    if (current == null) return TransitionNotFound(id);

    if (!current.canTransitionTo(nextStatus)) {
      return TransitionRejected(
        'Cannot transition from ${current.status.name} to ${nextStatus.name}.',
      );
    }

    final updated = current.copyWith(
      status: nextStatus,
      primaryResponderId: primaryResponderId,
      clearPrimaryResponderId: clearPrimaryResponderId,
      standbyResponderId: standbyResponderId,
      clearStandbyResponderId: clearStandbyResponderId,
      // version auto-incremented by copyWith
    );

    await _store.saveEmergency(updated, syncStatus: SyncStatus.pending);
    return TransitionSuccess(updated);
  }

  /// Convenience shortcut: cancel an emergency (victim-initiated).
  Future<TransitionResult> cancelEmergency(String id) =>
      transitionStatus(id, EmergencyStatus.cancelled);

  // ---------------------------------------------------------------------------
  // Sync helpers (called by the sync worker in Phase 3)
  // ---------------------------------------------------------------------------

  /// Marks [id] as synced after a successful Firestore write.
  Future<void> markSynced(String id) => _store.markAsSynced(id);

  /// Marks [id] as failed after an unsuccessful Firestore write.
  Future<void> markFailed(String id) => _store.markAsFailed(id);

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<LocationFix> _bestAvailableFix() async {
    try {
      return await _locationService.getCurrentLocation();
    } catch (_) {
      // getCurrentLocation already attempts the full fallback chain.
      // If it still throws, use a truly last-resort zero fix so the
      // Emergency record is created rather than lost.
      return const LocationFix(
        latitude: 0.0,
        longitude: 0.0,
        accuracyMeters: null,
        source: LocationFixSource.appCached,
      );
    }
  }
}
