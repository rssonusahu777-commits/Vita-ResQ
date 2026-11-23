import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/communication_mode.dart';
import '../models/emergency_model.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';
import 'p2p_diagnostics.dart';
import 'p2p_payload_integrity.dart';

/// Pluggable interface for Firestore document operations to facilitate unit testing without live Firebase connections.
abstract class IRelayFirestoreWriter {
  Future<bool> documentExists(String documentPath);
  Future<void> writeDocument(String documentPath, Map<String, dynamic> data);
}

/// Production implementation of [IRelayFirestoreWriter] using standard Cloud Firestore SDK.
class FirestoreRelayWriter implements IRelayFirestoreWriter {
  final FirebaseFirestore? _injectedFirestore;

  FirestoreRelayWriter([FirebaseFirestore? firestore])
      : _injectedFirestore = firestore;

  FirebaseFirestore? get _firestore {
    if (_injectedFirestore != null) return _injectedFirestore;
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> documentExists(String documentPath) async {
    try {
      final db = _firestore;
      if (db == null) return false;
      final snap = await db.doc(documentPath).get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> writeDocument(String documentPath, Map<String, dynamic> data) async {
    try {
      final db = _firestore;
      if (db == null) return;
      await db.doc(documentPath).set(data);
    } catch (_) {}
  }
}

/// Community Cloud Gateway Relay: 1-hop bystander P2P-to-Firestore bridge.
/// Bridges offline emergencies (JS-OFF-*) to Cloud Firestore when an authenticated
/// online volunteer discovers them nearby, ensuring life-safety alerts reach professional
/// responders while staying strictly within Firebase Free Spark plan limits (no Cloud Functions).
class CommunityRelayService {
  final IRelayFirestoreWriter _firestoreWriter;
  final ConnectivityService? _connectivity;
  final DateTime Function()? _clock;

  static CommunityRelayService? _mockInstance;
  static final CommunityRelayService _instance = CommunityRelayService._internal();

  factory CommunityRelayService({
    IRelayFirestoreWriter? firestoreWriter,
    ConnectivityService? connectivity,
    DateTime Function()? clock,
  }) {
    if (firestoreWriter != null || connectivity != null || clock != null) {
      return CommunityRelayService._internal(
        firestoreWriter: firestoreWriter,
        connectivity: connectivity,
        clock: clock,
      );
    }
    return _mockInstance ?? _instance;
  }

  CommunityRelayService._internal({
    IRelayFirestoreWriter? firestoreWriter,
    ConnectivityService? connectivity,
    DateTime Function()? clock,
  })  : _firestoreWriter = firestoreWriter ?? FirestoreRelayWriter(),
        _connectivity = connectivity,
        _clock = clock;

  @visibleForTesting
  static void setMockInstance(CommunityRelayService? mock) {
    _mockInstance = mock;
  }

  /// Evaluates an incoming P2P emergency against all 5 life-safety relay gates and,
  /// if eligible, idempotently creates the record in Cloud Firestore as 'SEARCHING'.
  Future<bool> relayOfflineAlertIfEligible({
    required EmergencyModel alert,
    Map<String, dynamic>? rawPayload,
    String? currentUserId,
    bool? isOnline,
    DateTime? now,
  }) async {
    final currentTime = now ?? _clock?.call() ?? DateTime.now();

    // -------------------------------------------------------------------------
    // Gate 1: Integrity Check (SHA-256 signature verification)
    // -------------------------------------------------------------------------
    if (rawPayload != null) {
      final isValidSig = P2PPayloadIntegrity.verifyPayload(rawPayload);
      if (!isValidSig) {
        P2PDiagnostics.log(alert.id, 'RELAY_SKIPPED_INVALID_SIG', {
          'reason': 'Payload integrity verification failed or hash mismatch',
        });
        return false;
      }
    }

    // -------------------------------------------------------------------------
    // Gate 2: Terminal Check (Never relay CANCELLED or COMPLETED alerts)
    // -------------------------------------------------------------------------
    if (alert.isTerminal) {
      P2PDiagnostics.log(alert.id, 'RELAY_SKIPPED_TERMINAL', {
        'status': alert.status.name,
      });
      return false;
    }

    // -------------------------------------------------------------------------
    // Gate 3: 10-Minute TTL Gate (Strict anti-stale upload enforcement)
    // -------------------------------------------------------------------------
    final ageSeconds = currentTime.difference(alert.createdAt).abs().inSeconds;
    if (ageSeconds > 600) {
      P2PDiagnostics.log(alert.id, 'RELAY_SKIPPED_STALE', {
        'ageSeconds': ageSeconds,
        'ttlLimit': 600,
      });
      return false;
    }

    // -------------------------------------------------------------------------
    // Gate 4: Online & Authenticated Check
    // -------------------------------------------------------------------------
    final bool online = isOnline ??
        ((_connectivity ?? ConnectivityService()).currentMode == CommunicationMode.online);

    String effectiveUid = currentUserId ?? '';
    if (effectiveUid.isEmpty) {
      try {
        effectiveUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      } catch (_) {
        effectiveUid = '';
      }
    }

    final bool isGuest = AuthService.isGuestOfflineSessionSync ||
        effectiveUid.startsWith('offline_guest');

    final bool isAuth = effectiveUid.isNotEmpty &&
        effectiveUid != 'offline_user' &&
        !isGuest;

    final bool isOfflineAlert = alert.id.startsWith('JS-OFF-');

    if (!online || !isAuth || !isOfflineAlert) {
      P2PDiagnostics.log(alert.id, 'RELAY_SKIPPED_NOT_ONLINE_OR_AUTH', {
        'isOnline': online,
        'isAuthenticated': isAuth,
        'isOfflineAlert': isOfflineAlert,
        'currentUserId': effectiveUid,
        'isGuest': isGuest,
      });
      return false;
    }

    // -------------------------------------------------------------------------
    // Gate 5: Idempotent Firestore Check (Read before write)
    // -------------------------------------------------------------------------
    try {
      final docPath = '${AppConstants.emergenciesCollection}/${alert.id}';
      final bool exists = await _firestoreWriter.documentExists(docPath);
      if (exists) {
        P2PDiagnostics.log(alert.id, 'RELAY_SKIPPED_EXISTS', {
          'emergencyId': alert.id,
        });
        return false;
      }

      final Map<String, dynamic> relayData = {
        'id': alert.id,
        'victimId': alert.victimId,
        if (alert.originDeviceId != null) 'originDeviceId': alert.originDeviceId,
        'type': alert.type,
        'latitude': alert.latitude,
        'longitude': alert.longitude,
        'status': 'SEARCHING',
        'helperId': alert.helperId,
        'currentRadiusMeters': 500.0,
        'notifiedUserIds': alert.notifiedUserIds,
        'responders': alert.responders.map((k, v) => MapEntry(k, v.toMap())),
        'createdAt': Timestamp.fromDate(alert.createdAt),
        'updatedAt': Timestamp.fromDate(alert.updatedAt),
        'isRelayedOffline': true,
        'relayedByUid': effectiveUid,
        if (alert.lastVictimLocation != null) 'lastVictimLocation': alert.lastVictimLocation,
        if (alert.lastHelperLocation != null) 'lastHelperLocation': alert.lastHelperLocation,
      };

      await _firestoreWriter.writeDocument(docPath, relayData);
      P2PDiagnostics.log(alert.id, 'RELAY_UPLOADED', {
        'emergencyId': alert.id,
        'relayedByUid': effectiveUid,
        'victimId': alert.victimId,
        'status': 'SEARCHING',
      });
      return true;
    } catch (e) {
      P2PDiagnostics.log(alert.id, 'RELAY_WRITE_FAILED', {
        'error': e.toString(),
      });
      return false;
    }
  }
}

