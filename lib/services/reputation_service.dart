// lib/services/reputation_service.dart
//
// Vindara — Verified Responder Reputation & Trust System (Phase 7)
// Package: com.vindara.app
//
// Design rules followed:
//   Anti-Gaming Rule — Zero points awarded merely for tapping "Accept".
//   Self-Farming Protection — Zero points awarded if primary responder == victim.
//   Resolution-Gated Rewards — Points and assist counters increment ONLY upon transition to resolved.

import '../models/emergency.dart';
import '../models/user_profile.dart';

class ReputationService {
  static const int pointsPrimaryResolution = 50;
  static const int pointsStandbyResolution = 20;

  // Milestone Badge IDs
  static const String badgeFirstResponder = 'first_responder'; // >= 1 assists
  static const String badgeCommunityGuardian = 'community_guardian'; // >= 5 assists
  static const String badgeVindaraVanguard = 'vindara_vanguard'; // >= 15 assists

  /// Calculates points earned by a responder for an emergency state transition.
  /// Anti-gaming:
  /// - Returns 0 if newStatus != resolved.
  /// - Returns 0 if responderId == victimId (self-farming prevention).
  /// - Returns 50 for primary responder, 20 for standby responder.
  static int calculateResolutionPoints({
    required Emergency emergency,
    required String responderId,
    required EmergencyStatus newStatus,
  }) {
    if (newStatus != EmergencyStatus.resolved) {
      return 0; // Anti-Gaming: Never award points on 'accepted' or 'inProgress'
    }

    if (responderId.isEmpty || responderId == emergency.victimId) {
      return 0; // Anti-Gaming: Block self-farming
    }

    if (emergency.primaryResponderId == responderId) {
      return pointsPrimaryResolution;
    }

    if (emergency.standbyResponderId == responderId) {
      return pointsStandbyResolution;
    }

    return 0;
  }

  /// Calculates the complete set of unlocked badges based on total successful assists.
  static List<String> calculateUnlockedBadges({
    required int successfulAssistanceCount,
    List<String> existingBadges = const [],
  }) {
    final badges = Set<String>.from(existingBadges);

    if (successfulAssistanceCount >= 1) {
      badges.add(badgeFirstResponder);
    }
    if (successfulAssistanceCount >= 5) {
      badges.add(badgeCommunityGuardian);
    }
    if (successfulAssistanceCount >= 15) {
      badges.add(badgeVindaraVanguard);
    }

    return badges.toList();
  }

  /// Human-readable title corresponding to a badge ID.
  static String getBadgeTitle(String badgeId) {
    switch (badgeId) {
      case badgeFirstResponder:
        return 'First Responder';
      case badgeCommunityGuardian:
        return 'Community Guardian';
      case badgeVindaraVanguard:
        return 'Vindara Vanguard';
      default:
        return badgeId;
    }
  }

  /// Responder Rank Title based on cumulative reputation points.
  static String getRankTitle(int reputationPoints) {
    if (reputationPoints >= 600) {
      return 'Master Guardian';
    } else if (reputationPoints >= 300) {
      return 'Senior Guardian';
    } else if (reputationPoints >= 100) {
      return 'Active Guardian';
    } else {
      return 'Novice Responder';
    }
  }

  /// Applies local resolution rewards to a UserProfile (useful for offline optimistic UI update).
  static UserProfile applyResolutionReward({
    required UserProfile profile,
    required Emergency emergency,
    required EmergencyStatus newStatus,
  }) {
    final points = calculateResolutionPoints(
      emergency: emergency,
      responderId: profile.uid,
      newStatus: newStatus,
    );

    if (points == 0) return profile;

    final isPrimary = emergency.primaryResponderId == profile.uid;
    final newAssistCount =
        profile.successfulAssistanceCount + (isPrimary ? 1 : 0);
    final newBadges = calculateUnlockedBadges(
      successfulAssistanceCount: newAssistCount,
      existingBadges: profile.badges,
    );

    return profile.copyWith(
      reputationPoints: profile.reputationPoints + points,
      successfulAssistanceCount: newAssistCount,
      badges: newBadges,
    );
  }
}
