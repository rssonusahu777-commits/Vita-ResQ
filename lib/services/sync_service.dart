// lib/services/sync_service.dart
//
// Vindara — Idempotent Offline Sync Service
// Package: com.vindara.app
//
// Design rules:
//   Rule #7 — Collision-resistant EMG-2026-XXXXXXXX IDs are preserved.
//   Rule #8 — Idempotent sync; drained whenever isOnline becomes true.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'connectivity_service.dart';
import 'firestore_emergency_service.dart';
import 'local_emergency_store.dart';

/// Background engine syncing pending offline records to Cloud Firestore.
class SyncService {
  final LocalEmergencyStore _localStore;
  final FirestoreEmergencyService _firestoreService;
  final ConnectivityService _connectivityService;

  StreamSubscription<bool>? _connectivitySubscription;
  bool _isSyncing = false;

  SyncService({
    required this._localStore,
    required this._firestoreService,
    required this._connectivityService,
  });

  /// Initializes listening to connectivity transitions to trigger sync.
  Future<void> init() async {
    // If online right now at startup, trigger initial flush
    if (_connectivityService.isCurrentlyOnline) {
      await syncPendingEmergencies();
    }

    _connectivitySubscription = _connectivityService.isOnline.listen((isOnline) async {
      if (isOnline) {
        await syncPendingEmergencies();
      }
    });
  }

  /// Flushes all emergencies with syncStatus == pending or failed to Firestore.
  /// Idempotent: safe to run multiple times concurrently or repeatedly.
  Future<int> syncPendingEmergencies() async {
    if (_isSyncing) return 0;
    _isSyncing = true;

    int syncedCount = 0;
    try {
      final pending = _localStore.getPendingSyncEmergencies();
      for (final emergency in pending) {
        try {
          final success = await _firestoreService.upsertEmergency(emergency);
          if (success) {
            await _localStore.markAsSynced(emergency.id);
            syncedCount++;
          }
        } catch (e) {
          debugPrint('Sync failed for emergency ${emergency.id}: $e');
          await _localStore.markAsFailed(emergency.id);
        }
      }
    } finally {
      _isSyncing = false;
    }

    return syncedCount;
  }

  /// Disposes stream subscription (Rule #6).
  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
  }
}

