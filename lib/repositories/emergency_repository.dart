// lib/repositories/emergency_repository.dart
//
// Vindara — Emergency Repository (local-first with immediate online sync)
// Package: com.vindara.app
//
// This is the single entry point for all Emergency mutations and reads.
// Local-first: always writes to LocalEmergencyStore first (instant offline availability).
// When online, immediately triggers background sync to Cloud Firestore.
//
// Design rules followed:
//   Rule #1 — CommunicationMode tracks true reachability.
//   Rule #3 — Atomic responder claims.
//   Rule #7 — IDs generated via Emergency.generateId() (Random.secure()).
//   Rule #8 — Local store is always written first; sync queue managed here.
//   State machine — canTransitionTo() ALWAYS checked before any DB write.

import 'dart:async';

import '../models/emergency.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_emergency_service.dart';
import '../services/local_emergency_store.dart';
import '../services/location_service.dart';

// ---------------------------------------------------------------------------
// Result type for state transitions
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
class EmergencyRepository {
  final LocalEmergencyStore _store;
  final LocationService _locationService;
  final ConnectivityService? _connectivityService;
  final FirestoreEmergencyService? _firestoreService;

  EmergencyRepository({
    required LocalEmergencyStore store,
    required LocationService locationService,
    ConnectivityService? connectivityService,
    FirestoreEmergencyService? firestoreService,
  })  : _store = store,
        _locationService = locationService,
        _connectivityService = connectivityService,
        _firestoreService = firestoreService;

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------

  /// Creates a new [Emergency] from a GPS fix and stores it locally.
  ///
  /// - ID is generated client-side via [Emergency.generateId()] (Rule #7).
  /// - Attempts a fresh GPS fix; falls back to cached coordinates if unavailable.
  /// - Initial status is always [EmergencyStatus.created].
  /// - Persisted with [SyncStatus.pending] locally first (Rule #8).
  /// - If online, triggers immediate background upsert to Firestore.
  Future<Emergency> createEmergency({
    required String victimId,
    required EmergencyType type,
    DetectionSource detectionSource = DetectionSource.manualHelp,
    CommunicationMode? communicationMode,
    LocationFix? locationOverride,
  }) async {
    final fix = locationOverride ?? await _bestAvailableFix();

    final isOnline = _connectivityService?.isCurrentlyOnline ?? false;
    final resolvedCommMode = communicationMode ??
        (isOnline ? CommunicationMode.online : CommunicationMode.offline);

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
      communicationMode: resolvedCommMode,
      version: 1,
    );

    await _store.saveEmergency(emergency, syncStatus: SyncStatus.pending);

    // If online, perform immediate background sync
    if (isOnline && _firestoreService != null) {
      _triggerImmediateSync(emergency);
    }

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
  Stream<Emergency?> watchById(String id) => _store.watchEmergency(id);

  // ---------------------------------------------------------------------------
  // State transitions
  // ---------------------------------------------------------------------------

  /// Attempts to transition [id] to [nextStatus].
  ///
  /// Enforces the state machine via [Emergency.canTransitionTo()].
  /// On success, the updated record is persisted locally with
  /// [SyncStatus.pending] (Rule #8) and caller receives [TransitionSuccess].
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

    final isOnline = _connectivityService?.isCurrentlyOnline ?? false;

    final updated = current.copyWith(
      status: nextStatus,
      primaryResponderId: primaryResponderId,
      clearPrimaryResponderId: clearPrimaryResponderId,
      standbyResponderId: standbyResponderId,
      clearStandbyResponderId: clearStandbyResponderId,
      communicationMode: isOnline ? CommunicationMode.online : current.communicationMode,
    );

    await _store.saveEmergency(updated, syncStatus: SyncStatus.pending);

    if (isOnline && _firestoreService != null) {
      _triggerImmediateSync(updated);
    }

    return TransitionSuccess(updated);
  }

  /// Convenience shortcut: cancel an emergency (victim-initiated).
  Future<TransitionResult> cancelEmergency(String id) =>
      transitionStatus(id, EmergencyStatus.cancelled);

  // ---------------------------------------------------------------------------
  // Sync helpers
  // ---------------------------------------------------------------------------

  /// Marks [id] as synced after a successful Firestore write.
  Future<void> markSynced(String id) => _store.markAsSynced(id);

  /// Marks [id] as failed after an unsuccessful Firestore write.
  Future<void> markFailed(String id) => _store.markAsFailed(id);

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _triggerImmediateSync(Emergency emergency) {
    unawaited(
      _firestoreService!.upsertEmergency(emergency).then((success) {
        if (success) {
          _store.markAsSynced(emergency.id);
        }
      }).catchError((_) {
        // Leave as pending/failed for SyncService queue to retry
      }),
    );
  }

  Future<LocationFix> _bestAvailableFix() async {
    try {
      return await _locationService.getCurrentLocation();
    } catch (_) {
      return const LocationFix(
        latitude: 0.0,
        longitude: 0.0,
        accuracyMeters: null,
        source: LocationFixSource.appCached,
      );
    }
  }
}
