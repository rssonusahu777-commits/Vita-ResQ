// lib/services/firestore_emergency_service.dart
//
// Vindara — Cloud Firestore Emergency Service & Atomic Claims
// Package: com.vindara.app
//
// Design rules:
//   Rule #3 — Atomic responder claims using transactions.
//   Rule #4 — Firestore is the authoritative cloud truth.
//   Rule #7 — ID format: EMG-2026-XXXXXXXX.
//   Rule #8 — Idempotent version-guarded writes.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/emergency.dart';

/// Result outcome for claiming an emergency.
sealed class ClaimResult {
  const ClaimResult();
}

/// Successfully claimed as primary responder.
final class ClaimPrimarySuccess extends ClaimResult {
  final Emergency emergency;
  const ClaimPrimarySuccess(this.emergency);
}

/// Primary responder already assigned; assigned as standby responder.
final class ClaimStandbySuccess extends ClaimResult {
  final Emergency emergency;
  const ClaimStandbySuccess(this.emergency);
}

/// Both primary and standby roles are already claimed, or claim is rejected.
final class AlreadyClaimedResult extends ClaimResult {
  final String message;
  const AlreadyClaimedResult(this.message);
}

/// Emergency was not found on Firestore.
final class EmergencyNotFoundResult extends ClaimResult {
  final String emergencyId;
  const EmergencyNotFoundResult(this.emergencyId);
}

/// Service managing remote Firestore interactions for emergencies.
class FirestoreEmergencyService {
  final FirebaseFirestore _firestore;

  FirestoreEmergencyService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('emergencies');

  // ---------------------------------------------------------------------------
  // Upsert Emergency (Version Guarded)
  // ---------------------------------------------------------------------------

  /// Upserts an [Emergency] to Firestore.
  /// If the document already exists remotely with a newer or equal version,
  /// the remote write is rejected or merged carefully to prevent stale offline
  /// state from overwriting recent updates (Rule #8).
  Future<bool> upsertEmergency(Emergency emergency) async {
    final docRef = _collection.doc(emergency.id);

    return await _firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(docRef);

      if (snapshot.exists && snapshot.data() != null) {
        final remoteVersion = (snapshot.data()!['version'] as num?)?.toInt() ?? 0;
        if (remoteVersion > emergency.version) {
          // Remote is strictly newer than our local state. Do not overwrite.
          return false;
        }
      }

      transaction.set(
        docRef,
        emergency.toJson(),
        SetOptions(merge: true),
      );
      return true;
    });
  }

  // ---------------------------------------------------------------------------
  // Atomic Responder Claims (Rule #3)
  // ---------------------------------------------------------------------------

  /// Atomically claims an emergency for [responderId] using a transaction:
  /// 1. If status is `created` or `alerting` and `primaryResponderId == null`:
  ///    assigns [primaryResponderId] = [responderId], transitions to `accepted`,
  ///    increments `version`. Returns [ClaimPrimarySuccess].
  /// 2. If [primaryResponderId] is set (not equal to responderId) and [standbyResponderId == null]:
  ///    assigns [standbyResponderId] = [responderId], increments `version`. Returns [ClaimStandbySuccess].
  /// 3. Otherwise returns [AlreadyClaimedResult].
  Future<ClaimResult> claimEmergency(String emergencyId, String responderId) async {
    final docRef = _collection.doc(emergencyId);

    return await _firestore.runTransaction<ClaimResult>((transaction) async {
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists || snapshot.data() == null) {
        return EmergencyNotFoundResult(emergencyId);
      }

      final data = snapshot.data()!;
      final current = Emergency.fromJson(data);

      if ((current.status == EmergencyStatus.created ||
              current.status == EmergencyStatus.alerting) &&
          current.primaryResponderId == null) {
        final updated = current.copyWith(
          primaryResponderId: responderId,
          status: EmergencyStatus.accepted,
          communicationMode: CommunicationMode.online,
          version: current.version + 1,
        );

        transaction.update(docRef, updated.toJson());
        return ClaimPrimarySuccess(updated);
      } else if (current.primaryResponderId != null &&
          current.primaryResponderId != responderId &&
          current.standbyResponderId == null) {
        final updated = current.copyWith(
          standbyResponderId: responderId,
          communicationMode: CommunicationMode.online,
          version: current.version + 1,
        );

        transaction.update(docRef, updated.toJson());
        return ClaimStandbySuccess(updated);
      } else {
        return const AlreadyClaimedResult(
          'Emergency already has primary and standby responders assigned, or is in an ineligible status.',
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Atomic Release Primary Role (Rule #3)
  // ---------------------------------------------------------------------------

  /// Atomically releases the primary role held by [responderId]:
  /// - If [standbyResponderId] exists: promotes standby to primary, clears standby,
  ///   keeps status as `accepted`, increments `version`.
  /// - Else: clears primary, reverts status to `alerting` so other responders can claim,
  ///   increments `version`.
  Future<Emergency?> releasePrimaryRole(
      String emergencyId, String responderId) async {
    final docRef = _collection.doc(emergencyId);

    return await _firestore.runTransaction<Emergency?>((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists || snapshot.data() == null) return null;

      final current = Emergency.fromJson(snapshot.data()!);
      if (current.primaryResponderId != responderId) {
        // Not the primary responder
        return null;
      }

      Emergency updated;
      if (current.standbyResponderId != null) {
        // Promote standby to primary
        updated = current.copyWith(
          primaryResponderId: current.standbyResponderId,
          clearStandbyResponderId: true,
          status: EmergencyStatus.accepted,
          version: current.version + 1,
        );
      } else {
        // Revert to alerting
        updated = current.copyWith(
          clearPrimaryResponderId: true,
          status: EmergencyStatus.alerting,
          version: current.version + 1,
        );
      }

      transaction.update(docRef, updated.toJson());
      return updated;
    });
  }

  // ---------------------------------------------------------------------------
  // Read & Watch Remote Emergency
  // ---------------------------------------------------------------------------

  /// Reads current remote [Emergency] document.
  Future<Emergency?> getRemoteEmergency(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return Emergency.fromJson(doc.data()!);
  }

  /// Watches remote [Emergency] document (Rule #6 — single lifecycle stream).
  Stream<Emergency?> watchRemoteEmergency(String id) {
    return _collection.doc(id).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      try {
        return Emergency.fromJson(snapshot.data()!);
      } catch (_) {
        return null;
      }
    });
  }
}
